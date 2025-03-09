const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");

/// Allows for stack-like allocations in a fast and safe way.
/// It is safe in the sense that a regular allocator will be used when the buffer is full.
pub const StackAllocator = struct { // MARK: StackAllocator
	const AllocationTrailer = packed struct {wasFreed: bool, previousAllocationTrailer: u31};
	backingAllocator: NeverFailingAllocator,
	buffer: []align(4096) u8,
	index: usize,

	pub fn init(backingAllocator: NeverFailingAllocator, size: u31) StackAllocator {
		return .{
			.backingAllocator = backingAllocator,
			.buffer = backingAllocator.alignedAlloc(u8, 4096, size),
			.index = 0,
		};
	}

	pub fn deinit(self: StackAllocator) void {
		if(self.index != 0) {
			std.log.err("Memory leak in Stack Allocator", .{});
		}
		self.backingAllocator.free(self.buffer);
	}

	pub fn allocator(self: *StackAllocator) NeverFailingAllocator {
		return .{
			.allocator = .{
				.vtable = &.{
					.alloc = &alloc,
					.resize = &resize,
					.remap = &remap,
					.free = &free,
				},
				.ptr = self,
			},
			.IAssertThatTheProvidedAllocatorCantFail = {},
		};
	}

	fn isInsideBuffer(self: *StackAllocator, buf: []u8) bool {
		const bufferStart = @intFromPtr(self.buffer.ptr);
		const bufferEnd = bufferStart + self.buffer.len;
		const compare = @intFromPtr(buf.ptr);
		return compare >= bufferStart and compare < bufferEnd;
	}

	fn indexInBuffer(self: *StackAllocator, buf: []u8) usize {
		const bufferStart = @intFromPtr(self.buffer.ptr);
		const compare = @intFromPtr(buf.ptr);
		return compare - bufferStart;
	}

	fn getTrueAllocationEnd(start: usize, len: usize) usize {
		const trailerStart = std.mem.alignForward(usize, start + len, @alignOf(AllocationTrailer));
		return trailerStart + @sizeOf(AllocationTrailer);
	}

	fn getTrailerBefore(self: *StackAllocator, end: usize) *AllocationTrailer {
		const trailerStart = end - @sizeOf(AllocationTrailer);
		return @ptrCast(@alignCast(self.buffer[trailerStart..].ptr));
	}

	fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
		const self: *StackAllocator = @ptrCast(@alignCast(ctx));
		const start = std.mem.alignForward(usize, self.index, @as(usize, 1) << @intCast(@intFromEnum(alignment)));
		const end = getTrueAllocationEnd(start, len);
		if(end >= self.buffer.len) return self.backingAllocator.rawAlloc(len, alignment, ret_addr);
		const trailer = self.getTrailerBefore(end);
		trailer.* = .{.wasFreed = false, .previousAllocationTrailer = @intCast(self.index)};
		self.index = end;
		return self.buffer.ptr + start;
	}

	fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
		const self: *StackAllocator = @ptrCast(@alignCast(ctx));
		if(self.isInsideBuffer(memory)) {
			const start = self.indexInBuffer(memory);
			const end = getTrueAllocationEnd(start, memory.len);
			if(end != self.index) return false;
			const newEnd = getTrueAllocationEnd(start, new_len);
			if(newEnd >= self.buffer.len) return false;

			const trailer = self.getTrailerBefore(end);
			std.debug.assert(!trailer.wasFreed);
			const newTrailer = self.getTrailerBefore(newEnd);

			newTrailer.* = .{.wasFreed = false, .previousAllocationTrailer = trailer.previousAllocationTrailer};
			self.index = newEnd;
			return true;
		} else {
			return self.backingAllocator.rawResize(memory, alignment, new_len, ret_addr);
		}
	}

	fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
		if(resize(ctx, memory, alignment, new_len, ret_addr)) return memory.ptr;
		return null;
	}

	fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
		const self: *StackAllocator = @ptrCast(@alignCast(ctx));
		if(self.isInsideBuffer(memory)) {
			const start = self.indexInBuffer(memory);
			const end = getTrueAllocationEnd(start, memory.len);
			const trailer = self.getTrailerBefore(end);
			std.debug.assert(!trailer.wasFreed); // Double Free

			if(end == self.index) {
				self.index = trailer.previousAllocationTrailer;
				if(self.index != 0) {
					var previousTrailer = self.getTrailerBefore(trailer.previousAllocationTrailer);
					while(previousTrailer.wasFreed) {
						self.index = previousTrailer.previousAllocationTrailer;
						if(self.index == 0) break;
						previousTrailer = self.getTrailerBefore(previousTrailer.previousAllocationTrailer);
					}
				}
			} else {
				trailer.wasFreed = true;
			}
		} else {
			self.backingAllocator.rawFree(memory, alignment, ret_addr);
		}
	}
};

/// An allocator that handles OutOfMemory situations by panicing or freeing memory(TODO), making it safe to ignore errors.
pub const ErrorHandlingAllocator = struct { // MARK: ErrorHandlingAllocator
	backingAllocator: Allocator,

	pub fn init(backingAllocator: Allocator) ErrorHandlingAllocator {
		return .{
			.backingAllocator = backingAllocator,
		};
	}

	pub fn allocator(self: *ErrorHandlingAllocator) NeverFailingAllocator {
		return .{
			.allocator = .{
				.vtable = &.{
					.alloc = &alloc,
					.resize = &resize,
					.remap = &remap,
					.free = &free,
				},
				.ptr = self,
			},
			.IAssertThatTheProvidedAllocatorCantFail = {},
		};
	}

	fn handleError() noreturn {
		@panic("Out Of Memory. Please download more RAM, reduce the render distance, or close some of your 100 browser tabs.");
	}

	/// Return a pointer to `len` bytes with specified `alignment`, or return
	/// `null` indicating the allocation failed.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
		const self: *ErrorHandlingAllocator = @ptrCast(@alignCast(ctx));
		return self.backingAllocator.rawAlloc(len, alignment, ret_addr) orelse handleError();
	}

	/// Attempt to expand or shrink memory in place.
	///
	/// `memory.len` must equal the length requested from the most recent
	/// successful call to `alloc`, `resize`, or `remap`. `alignment` must
	/// equal the same value that was passed as the `alignment` parameter to
	/// the original `alloc` call.
	///
	/// A result of `true` indicates the resize was successful and the
	/// allocation now has the same address but a size of `new_len`. `false`
	/// indicates the resize could not be completed without moving the
	/// allocation to a different address.
	///
	/// `new_len` must be greater than zero.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
		const self: *ErrorHandlingAllocator = @ptrCast(@alignCast(ctx));
		return self.backingAllocator.rawResize(memory, alignment, new_len, ret_addr);
	}

	/// Attempt to expand or shrink memory, allowing relocation.
	///
	/// `memory.len` must equal the length requested from the most recent
	/// successful call to `alloc`, `resize`, or `remap`. `alignment` must
	/// equal the same value that was passed as the `alignment` parameter to
	/// the original `alloc` call.
	///
	/// A non-`null` return value indicates the resize was successful. The
	/// allocation may have same address, or may have been relocated. In either
	/// case, the allocation now has size of `new_len`. A `null` return value
	/// indicates that the resize would be equivalent to allocating new memory,
	/// copying the bytes from the old memory, and then freeing the old memory.
	/// In such case, it is more efficient for the caller to perform the copy.
	///
	/// `new_len` must be greater than zero.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
		const self: *ErrorHandlingAllocator = @ptrCast(@alignCast(ctx));
		return self.backingAllocator.rawRemap(memory, alignment, new_len, ret_addr);
	}

	/// Free and invalidate a region of memory.
	///
	/// `memory.len` must equal the length requested from the most recent
	/// successful call to `alloc`, `resize`, or `remap`. `alignment` must
	/// equal the same value that was passed as the `alignment` parameter to
	/// the original `alloc` call.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
		const self: *ErrorHandlingAllocator = @ptrCast(@alignCast(ctx));
		self.backingAllocator.rawFree(memory, alignment, ret_addr);
	}
};

/// An allocator interface signaling that you can use
pub const NeverFailingAllocator = struct { // MARK: NeverFailingAllocator
	allocator: Allocator,
	IAssertThatTheProvidedAllocatorCantFail: void,

	const Alignment = std.mem.Alignment;
	const math = std.math;

	/// This function is not intended to be called except from within the
	/// implementation of an `Allocator`.
	pub inline fn rawAlloc(a: NeverFailingAllocator, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
		return a.allocator.vtable.alloc(a.allocator.ptr, len, alignment, ret_addr);
	}

	/// This function is not intended to be called except from within the
	/// implementation of an `Allocator`.
	pub inline fn rawResize(a: NeverFailingAllocator, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
		return a.allocator.vtable.resize(a.allocator.ptr, memory, alignment, new_len, ret_addr);
	}

	/// This function is not intended to be called except from within the
	/// implementation of an `Allocator`.
	pub inline fn rawRemap(a: NeverFailingAllocator, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
		return a.allocator.vtable.remap(a.allocator.ptr, memory, alignment, new_len, ret_addr);
	}

	/// This function is not intended to be called except from within the
	/// implementation of an `Allocator`.
	pub inline fn rawFree(a: NeverFailingAllocator, memory: []u8, alignment: Alignment, ret_addr: usize) void {
		return a.allocator.vtable.free(a.allocator.ptr, memory, alignment, ret_addr);
	}

	/// Returns a pointer to undefined memory.
	/// Call `destroy` with the result to free the memory.
	pub fn create(self: NeverFailingAllocator, comptime T: type) *T {
		return self.allocator.create(T) catch unreachable;
	}

	/// `ptr` should be the return value of `create`, or otherwise
	/// have the same address and alignment property.
	pub fn destroy(self: NeverFailingAllocator, ptr: anytype) void {
		self.allocator.destroy(ptr);
	}

	/// Allocates an array of `n` items of type `T` and sets all the
	/// items to `undefined`. Depending on the Allocator
	/// implementation, it may be required to call `free` once the
	/// memory is no longer needed, to avoid a resource leak. If the
	/// `Allocator` implementation is unknown, then correct code will
	/// call `free` when done.
	///
	/// For allocating a single item, see `create`.
	pub fn alloc(self: NeverFailingAllocator, comptime T: type, n: usize) []T {
		return self.allocator.alloc(T, n) catch unreachable;
	}

	pub fn allocWithOptions(
		self: NeverFailingAllocator,
		comptime Elem: type,
		n: usize,
		/// null means naturally aligned
		comptime optional_alignment: ?u29,
		comptime optional_sentinel: ?Elem,
	) AllocWithOptionsPayload(Elem, optional_alignment, optional_sentinel) {
		return self.allocator.allocWithOptions(Elem, n, optional_alignment, optional_sentinel) catch unreachable;
	}

	pub fn allocWithOptionsRetAddr(
		self: NeverFailingAllocator,
		comptime Elem: type,
		n: usize,
		/// null means naturally aligned
		comptime optional_alignment: ?u29,
		comptime optional_sentinel: ?Elem,
		return_address: usize,
	) AllocWithOptionsPayload(Elem, optional_alignment, optional_sentinel) {
		return self.allocator.allocWithOptionsRetAddr(Elem, n, optional_alignment, optional_sentinel, return_address) catch unreachable;
	}

	fn AllocWithOptionsPayload(comptime Elem: type, comptime alignment: ?u29, comptime sentinel: ?Elem) type {
		if(sentinel) |s| {
			return [:s]align(alignment orelse @alignOf(Elem)) Elem;
		} else {
			return []align(alignment orelse @alignOf(Elem)) Elem;
		}
	}

	/// Allocates an array of `n + 1` items of type `T` and sets the first `n`
	/// items to `undefined` and the last item to `sentinel`. Depending on the
	/// Allocator implementation, it may be required to call `free` once the
	/// memory is no longer needed, to avoid a resource leak. If the
	/// `Allocator` implementation is unknown, then correct code will
	/// call `free` when done.
	///
	/// For allocating a single item, see `create`.
	pub fn allocSentinel(
		self: NeverFailingAllocator,
		comptime Elem: type,
		n: usize,
		comptime sentinel: Elem,
	) [:sentinel]Elem {
		return self.allocator.allocSentinel(Elem, n, sentinel) catch unreachable;
	}

	pub fn alignedAlloc(
		self: NeverFailingAllocator,
		comptime T: type,
		/// null means naturally aligned
		comptime alignment: ?u29,
		n: usize,
	) []align(alignment orelse @alignOf(T)) T {
		return self.allocator.alignedAlloc(T, alignment, n) catch unreachable;
	}

	pub inline fn allocAdvancedWithRetAddr(
		self: NeverFailingAllocator,
		comptime T: type,
		/// null means naturally aligned
		comptime alignment: ?u29,
		n: usize,
		return_address: usize,
	) []align(alignment orelse @alignOf(T)) T {
		return self.allocator.allocAdvancedWithRetAddr(T, alignment, n, return_address) catch unreachable;
	}

	fn allocWithSizeAndAlignment(self: NeverFailingAllocator, comptime size: usize, comptime alignment: u29, n: usize, return_address: usize) [*]align(alignment) u8 {
		return self.allocator.allocWithSizeAndAlignment(alignment, size, alignment, n, return_address) catch unreachable;
	}

	fn allocBytesWithAlignment(self: NeverFailingAllocator, comptime alignment: u29, byte_count: usize, return_address: usize) [*]align(alignment) u8 {
		return self.allocator.allocBytesWithAlignment(alignment, byte_count, return_address) catch unreachable;
	}

	/// Request to modify the size of an allocation.
	///
	/// It is guaranteed to not move the pointer, however the allocator
	/// implementation may refuse the resize request by returning `false`.
	///
	/// `allocation` may be an empty slice, in which case a new allocation is made.
	///
	/// `new_len` may be zero, in which case the allocation is freed.
	pub fn resize(self: NeverFailingAllocator, allocation: anytype, new_len: usize) bool {
		return self.allocator.resize(allocation, new_len);
	}

	/// Request to modify the size of an allocation, allowing relocation.
	///
	/// A non-`null` return value indicates the resize was successful. The
	/// allocation may have same address, or may have been relocated. In either
	/// case, the allocation now has size of `new_len`. A `null` return value
	/// indicates that the resize would be equivalent to allocating new memory,
	/// copying the bytes from the old memory, and then freeing the old memory.
	/// In such case, it is more efficient for the caller to perform those
	/// operations.
	///
	/// `allocation` may be an empty slice, in which case a new allocation is made.
	///
	/// `new_len` may be zero, in which case the allocation is freed.
	pub fn remap(self: NeverFailingAllocator, allocation: anytype, new_len: usize) t: {
		const Slice = @typeInfo(@TypeOf(allocation)).pointer;
		break :t ?[]align(Slice.alignment) Slice.child;
	} {
		return self.allocator.remap(allocation, new_len);
	}

	/// This function requests a new byte size for an existing allocation, which
	/// can be larger, smaller, or the same size as the old memory allocation.
	///
	/// If `new_n` is 0, this is the same as `free` and it always succeeds.
	///
	/// `old_mem` may have length zero, which makes a new allocation.
	///
	/// This function only fails on out-of-memory conditions, unlike:
	/// * `remap` which returns `null` when the `Allocator` implementation cannot
	///   do the realloc more efficiently than the caller
	/// * `resize` which returns `false` when the `Allocator` implementation cannot
	///   change the size without relocating the allocation.
	pub fn realloc(self: NeverFailingAllocator, old_mem: anytype, new_n: usize) t: {
		const Slice = @typeInfo(@TypeOf(old_mem)).pointer;
		break :t []align(Slice.alignment) Slice.child;
	} {
		return self.allocator.realloc(old_mem, new_n) catch unreachable;
	}

	pub fn reallocAdvanced(
		self: NeverFailingAllocator,
		old_mem: anytype,
		new_n: usize,
		return_address: usize,
	) t: {
		const Slice = @typeInfo(@TypeOf(old_mem)).pointer;
		break :t []align(Slice.alignment) Slice.child;
	} {
		return self.allocator.reallocAdvanced(old_mem, new_n, return_address) catch unreachable;
	}

	/// Free an array allocated with `alloc`.
	/// If memory has length 0, free is a no-op.
	/// To free a single item, see `destroy`.
	pub fn free(self: NeverFailingAllocator, memory: anytype) void {
		self.allocator.free(memory);
	}

	/// Copies `m` to newly allocated memory. Caller owns the memory.
	pub fn dupe(self: NeverFailingAllocator, comptime T: type, m: []const T) []T {
		return self.allocator.dupe(T, m) catch unreachable;
	}

	/// Copies `m` to newly allocated memory, with a null-terminated element. Caller owns the memory.
	pub fn dupeZ(self: NeverFailingAllocator, comptime T: type, m: []const T) [:0]T {
		return self.allocator.dupeZ(T, m) catch unreachable;
	}
};

pub const NeverFailingArenaAllocator = struct { // MARK: NeverFailingArena
	arena: std.heap.ArenaAllocator,

	pub fn init(child_allocator: NeverFailingAllocator) NeverFailingArenaAllocator {
		return .{
			.arena = .init(child_allocator.allocator),
		};
	}

	pub fn deinit(self: NeverFailingArenaAllocator) void {
		self.arena.deinit();
	}

	pub fn allocator(self: *NeverFailingArenaAllocator) NeverFailingAllocator {
		return .{
			.allocator = self.arena.allocator(),
			.IAssertThatTheProvidedAllocatorCantFail = {},
		};
	}

	/// Resets the arena allocator and frees all allocated memory.
	///
	/// `mode` defines how the currently allocated memory is handled.
	/// See the variant documentation for `ResetMode` for the effects of each mode.
	///
	/// The function will return whether the reset operation was successful or not.
	/// If the reallocation  failed `false` is returned. The arena will still be fully
	/// functional in that case, all memory is released. Future allocations just might
	/// be slower.
	///
	/// NOTE: If `mode` is `free_all`, the function will always return `true`.
	pub fn reset(self: *NeverFailingArenaAllocator, mode: std.heap.ArenaAllocator.ResetMode) bool {
		return self.arena.reset(mode);
	}

	pub fn shrinkAndFree(self: *NeverFailingArenaAllocator) void {
		const node = self.arena.state.buffer_list.first orelse return;
		const allocBuf = @as([*]u8, @ptrCast(node))[0..node.data];
		const dataSize = std.mem.alignForward(usize, @sizeOf(std.SinglyLinkedList(usize).Node) + self.arena.state.end_index, @alignOf(std.SinglyLinkedList(usize).Node));
		if(self.arena.child_allocator.rawResize(allocBuf, @enumFromInt(std.math.log2(@alignOf(std.SinglyLinkedList(usize).Node))), dataSize, @returnAddress())) {
			node.data = dataSize;
		}
	}
};
