const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const mods = @import("mods");

pub const ClientBlockCallback = Callback(struct { block: Block, chunk: *main.chunk.Chunk, blockPos: Vec3i }, .@"callbacks/block/client");
pub const ServerBlockCallback = Callback(struct { block: Block, chunk: *main.chunk.ServerChunk, blockPos: main.chunk.BlockPos }, .@"callbacks/block/server");

pub const BlockTouchCallback = Callback(struct { entity: *main.server.Entity, source: Block, blockPos: Vec3i, deltaTime: f64 }, .@"callbacks/block/touch");

pub const Result = enum { handled, ignored };

pub fn init() void {
	ClientBlockCallback.globalInit();
	ServerBlockCallback.globalInit();
	BlockTouchCallback.globalInit();
}

pub const Creator = union(enum) {
	block: main.blocks.Block,
};

fn Callback(_Params: type, feature: main.mods.Feature) type {
	return struct {
		data: *anyopaque,
		inner: *const fn (self: *anyopaque, params: Params) Result,

		pub const Params = _Params;

		const VTable = struct {
			init: *const fn (zon: main.ZonElement, creator: Creator) ?*anyopaque,
			run: *const fn (self: *anyopaque, params: Params) Result,
		};

		var eventCreationMap: std.StringHashMapUnmanaged(VTable) = .{};

		fn globalInit() void {
			main.mods.walkFeatureContext(feature, *std.StringHashMapUnmanaged(VTable), &eventCreationMap, registerEvent);
		}

		fn registerEvent(map: *std.StringHashMapUnmanaged(VTable), descriptor: main.mods.ObjectDescriptor) void {
			map.put(main.globalArena.allocator, descriptor.id, .{
				.init = main.meta.castFunctionReturnToOptionalAnyopaque(descriptor.object.init),
				.run = main.meta.castFunctionSelfToAnyopaque(descriptor.object.run),
			}) catch unreachable;
		}

		pub fn init(zon: main.ZonElement, creator: Creator) ?@This() {
			const typ = zon.get([]const u8, "type") orelse {
				std.log.err("Missing field \"type\"", .{});
				return null;
			};
			const vtable = eventCreationMap.get(typ) orelse {
				std.log.err("Couldn't find block interact event {s}", .{typ});
				return null;
			};
			return .{
				.data = vtable.init(zon, creator) orelse return null,
				.inner = vtable.run,
			};
		}

		pub const noop: @This() = .{
			.data = undefined,
			.inner = &noopCallback,
		};

		fn noopCallback(_: *anyopaque, _: Params) Result {
			return .ignored;
		}

		pub fn run(self: @This(), params: Params) Result {
			return self.inner(self.data, params);
		}

		pub fn isNoop(self: @This()) bool {
			return self.inner == &noopCallback;
		}
	};
}

pub const SimpleCallback = struct {
	data: *anyopaque = undefined,
	inner: ?*const fn (*anyopaque) void = null,

	fn genericWrapper(callbackFunction: fn () void) *const fn (*anyopaque) void {
		return &struct {
			fn wrapper(_: *anyopaque) void {
				callbackFunction();
			}
		}.wrapper;
	}

	pub fn init(comptime callbackFunction: fn () void) SimpleCallback {
		return .{
			.inner = genericWrapper(callbackFunction),
		};
	}

	pub fn initWithPtr(callbackFunction: anytype, data: *anyopaque) SimpleCallback {
		return .{
			.inner = main.meta.castFunctionSelfToAnyopaque(callbackFunction),
			.data = data,
		};
	}

	pub fn initWithInt(callbackFunction: fn (usize) void, data: usize) SimpleCallback {
		@setRuntimeSafety(false);
		return .{
			.inner = @ptrCast(&callbackFunction),
			.data = @ptrFromInt(data),
		};
	}

	pub fn run(self: SimpleCallback) void {
		if (self.inner) |callback| {
			callback(self.data);
		}
	}
};
