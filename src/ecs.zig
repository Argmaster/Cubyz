const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");
const main = @import("main");

pub const components = @import("components");

const allocationAlignmentBytes = 64;
const allocationAlignment = std.mem.Alignment.fromByteUnits(allocationAlignmentBytes);
const allocationHeaderSizeBytes = allocationAlignmentBytes;

var wasCustomOsApiInitialized = false;

const ComponentIds = blk: {
	const count = @typeInfo(components).@"struct".decls.len;
	var names: [count][]const u8 = undefined;

	for (@typeInfo(components).@"struct".decls, 0..) |declaration_info, index| {
		const component = @field(components, declaration_info.name);
		names[index] = @typeName(component);
	}

	break :blk @Struct(.@"extern", null, names[0..count], &@splat(u64), &@splat(.{}));
};

var componentIds: ComponentIds = undefined;
var world: *c.ecs_world_t = undefined;

pub fn init() void {
	if (!wasCustomOsApiInitialized) initCustomOsApi();

	world = c.ecs_init().?;

	inline for (@typeInfo(components).@"struct".decls) |declaration_info| {
		const Component: type = @field(components, declaration_info.name);
		const result = c.ecs_component_init(
			world,
			&c.ecs_component_desc_t{
				.entity = c.ecs_entity_init(
					world,
					&c.ecs_entity_desc_t{
						.use_low_id = true,
						.name = @typeName(Component),
						.symbol = @typeName(Component),
					},
				),
				.type = .{
					.size = @sizeOf(Component),
					.alignment = @alignOf(Component),
					.hooks = blk: {
						var hooks: c.ecs_type_hooks_t = std.mem.zeroes(c.ecs_type_hooks_t);

						if (@hasDecl(Component, "init"))
							hooks.ctor = &EcsXTor(Component, "init").function;
						if (@hasDecl(Component, "move"))
							hooks.move = &EcsMove(Component).function;
						if (@hasDecl(Component, "copy"))
							hooks.copy = &EcsCopy(Component).function;
						if (@hasDecl(Component, "deinit"))
							hooks.dtor = &EcsXTor(Component, "deinit").function;
						if (@hasDecl(Component, "onSet"))
							hooks.on_set = &EcsHooks(Component).onSet;
						if (@hasDecl(Component, "onAdd"))
							hooks.on_add = &EcsHooks(Component).onAdd;
						if (@hasDecl(Component, "onRemove"))
							hooks.on_remove = &EcsHooks(Component).onRemove;
						if (@hasDecl(Component, "onReplace"))
							hooks.on_replace = &EcsHooks(Component).onReplace;

						break :blk hooks;
					},
				},
			},
		);
		@field(componentIds, @typeName(Component)) = result;
		std.log.debug("Registered component: {s} as {d}\n", .{@typeName(Component), result});
	}
}

pub fn deinit() void {
	const result = c.ecs_fini(world);
	std.debug.assert(result == 0);
}

pub fn new() FlecsEntity {
	return FlecsEntity.init(c.ecs_new(world));
}

/// We need to enforce 64 byte alignment for AVX512 SIMD operations.
/// See https://github.com/SanderMertens/flecs/issues/478
fn initCustomOsApi() void {
	wasCustomOsApiInitialized = true;

	c.ecs_os_set_api_defaults();

	var my_os_api: c.ecs_os_api_t = c.ecs_os_get_api();

	my_os_api.malloc_ = custom_malloc;
	my_os_api.calloc_ = custom_calloc;
	my_os_api.realloc_ = custom_realloc;
	my_os_api.free_ = custom_free;

	c.ecs_os_set_api(&my_os_api);
}
fn custom_malloc(size: c.ecs_size_t) callconv(.c) ?*anyopaque {
	const requestedSize: usize = @intCast(size);
	const totalSizeBytes: usize = requestedSize + allocationHeaderSizeBytes;
	const allocation = main.globalAllocator.rawAlloc(totalSizeBytes, allocationAlignment, @returnAddress()) orelse return null;
	const header: *align(allocationHeaderSizeBytes) usize = @ptrCast(@alignCast(allocation));
	header.* = requestedSize;
	return @ptrCast(allocation + allocationHeaderSizeBytes);
}

fn custom_calloc(size: c.ecs_size_t) callconv(.c) ?*anyopaque {
	const allocation = custom_malloc(size) orelse return null;
	@memset(@as([*]u8, @ptrCast(allocation))[0..@intCast(size)], 0);
	return allocation;
}

fn custom_realloc(ptr: ?*anyopaque, size: c.ecs_size_t) callconv(.c) ?*anyopaque {
	if (ptr == null) return custom_malloc(size);
	if (size == 0) {
		custom_free(ptr);
		return null;
	}

	const oldAllocation: [*]align(allocationAlignmentBytes) u8 = @alignCast(@as([*]u8, @ptrCast(ptr.?)) - allocationHeaderSizeBytes);
	const oldHeader: *align(allocationAlignmentBytes) usize = @ptrCast(oldAllocation);
	const oldSize = oldHeader.*;
	const newAllocation = custom_malloc(size) orelse return null;
	const newSize: usize = @intCast(size);
	@memcpy(@as([*]u8, @ptrCast(newAllocation))[0..@min(oldSize, newSize)], @as([*]u8, @ptrCast(ptr.?))[0..@min(oldSize, newSize)]);
	custom_free(ptr);
	return newAllocation;
}

fn custom_free(ptr: ?*anyopaque) callconv(.c) void {
	const allocationPtr = ptr orelse return;
	const allocation: [*]align(allocationAlignmentBytes) u8 = @alignCast(@as([*]u8, @ptrCast(allocationPtr)) - allocationHeaderSizeBytes);
	const header: *align(allocationAlignmentBytes) usize = @ptrCast(allocation);
	const size = header.*;
	main.globalAllocator.rawFree(allocation[0 .. size + allocationHeaderSizeBytes], allocationAlignment, @returnAddress());
}

pub fn EcsXTor(Component: type, comptime name: []const u8) type {
	return struct {
		pub fn function(ptrNullable: ?*anyopaque, count: i32, type_info: [*c]const c.ecs_type_info_t) callconv(.c) void {
			if (ptrNullable) |ptr| {
				for (@as([*]Component, @ptrCast(ptr))[0..@intCast(count)]) |*instance| {
					@field(Component, name)(instance, type_info);
				}
			}
		}
	};
}

pub fn EcsMove(Component: type) type {
	return struct {
		pub fn function(dstPtrNullable: ?*anyopaque, srcPtrNullable: ?*anyopaque, count: i32, type_info: [*c]const c.ecs_type_info_t) callconv(.c) void {
			for (
				@as([*]Component, @ptrCast(dstPtrNullable))[0..@intCast(count)],
				@as([*]Component, @ptrCast(srcPtrNullable))[0..@intCast(count)],
			) |*dst, *src| {
				Component.move(dst, src, type_info);
			}
		}
	};
}

pub fn EcsCopy(Component: type) type {
	return struct {
		pub fn function(dstPtrNullable: ?*anyopaque, srcPtrNullable: ?*const anyopaque, count: i32, type_info: [*c]const c.ecs_type_info_t) callconv(.c) void {
			for (
				@as([*]Component, @ptrCast(dstPtrNullable))[0..@intCast(count)],
				@as([*]const Component, @ptrCast(srcPtrNullable))[0..@intCast(count)],
			) |*dst, src| {
				Component.copy(dst, &src, type_info);
			}
		}
	};
}

pub fn EcsHooks(Component: type) type {
	return struct {
		pub fn onAdd(it: [*c]c.ecs_iter_t) callconv(.c) void {
			const iterator: *c.ecs_iter_t = @ptrCast(it);
			const selfAnySize: [*]Component = @ptrCast(@alignCast(c.ecs_field_w_size(it, @sizeOf(Component), 0).?));
			const selfIterator: []Component = selfAnySize[0..@intCast(iterator.count)];
			for (selfIterator) |*self|
				Component.onAdd(self);
		}
		pub fn onSet(it: [*c]c.ecs_iter_t) callconv(.c) void {
			const iterator: *c.ecs_iter_t = @ptrCast(it);
			const selfAnySize: [*]Component = @ptrCast(@alignCast(c.ecs_field_w_size(it, @sizeOf(Component), 0).?));
			const selfIterator: []Component = selfAnySize[0..@intCast(iterator.count)];
			for (selfIterator) |*self|
				Component.onSet(self);
		}
		pub fn onRemove(it: [*c]c.ecs_iter_t) callconv(.c) void {
			const iterator: *c.ecs_iter_t = @ptrCast(it);
			const selfAnySize: [*]Component = @ptrCast(@alignCast(c.ecs_field_w_size(it, @sizeOf(Component), 0).?));
			const selfIterator: []Component = selfAnySize[0..@intCast(iterator.count)];
			for (selfIterator) |*self|
				Component.onRemove(self);
		}
		pub fn onReplace(it: [*c]c.ecs_iter_t) callconv(.c) void {
			const iterator: *c.ecs_iter_t = @ptrCast(it);

			const oldAnySize: [*]const Component = @ptrCast(@alignCast(c.ecs_field_w_size(it, @sizeOf(Component), 0).?));
			const oldIterator: []const Component = oldAnySize[0..@intCast(iterator.count)];

			const newAnySize: [*]Component = @ptrCast(@alignCast(c.ecs_field_w_size(it, @sizeOf(Component), 1).?));
			const newIterator: []Component = newAnySize[0..@intCast(iterator.count)];

			for (oldIterator, newIterator) |*oldValue, *newValue|
				Component.onReplace(oldValue, newValue);
		}
	};
}

pub const FlecsEntity = struct {
	entityId: c.ecs_entity_t,

	fn init(e: c.ecs_entity_t) FlecsEntity {
		return .{.entityId = e};
	}
	pub fn deinit(self: FlecsEntity) void {
		c.ecs_delete(world, self.entityId);
	}
	pub fn getName(self: FlecsEntity) [*:0]const u8 {
		return c.ecs_get_name(world, self.entityId) orelse "<unnamed>";
	}
	pub fn isAlive(self: FlecsEntity) bool {
		return c.ecs_is_alive(world, self.entityId);
	}
	pub fn get(self: FlecsEntity, Component: type) ?*const Component {
		assertAliveDebugOnly(self);

		const componentId = @field(componentIds, @typeName(Component));
		if (c.ecs_get_id(world, self.entityId, componentId)) |result| {
			return @ptrCast(@alignCast(result));
		}
		return null;
	}
	pub fn add(self: FlecsEntity, Component: type) void {
		assertAliveDebugOnly(self);

		const componentId = @field(componentIds, @typeName(Component));
		c.ecs_add_id(world, self.entityId, componentId);
	}
	pub fn set(self: FlecsEntity, Component: type, value: Component) void {
		assertAliveDebugOnly(self);

		const componentId = @field(componentIds, @typeName(Component));
		c.ecs_set_id(world, self.entityId, componentId, @sizeOf(Component), &value);
	}
	pub fn remove(self: FlecsEntity, Component: type) void {
		assertAliveDebugOnly(self);

		const componentId = @field(componentIds, @typeName(Component));
		c.ecs_remove_id(world, self.entityId, componentId);
	}
};

inline fn assertAliveDebugOnly(self: FlecsEntity) void {
	if (builtin.mode == .Debug and !self.isAlive()) @panic("Entity is not alive!");
}

test "Entity with Trivial Component" {
	init();
	defer deinit();

	const entity1 = new();
	try std.testing.expect(entity1.isAlive());

	const expected: components.@"cubyz:Velocity" = .{.vel = .{1, 2, 3}};

	entity1.set(components.@"cubyz:Velocity", expected);
	const actual = entity1.get(components.@"cubyz:Velocity");

	try std.testing.expect(actual != null);
	try std.testing.expect(@reduce(.And, expected.vel == actual.?.vel));

	entity1.deinit();
}

test "Entity with TestComponentRuleOf5" {
	init();
	defer deinit();

	const entity1 = new();
	try std.testing.expect(entity1.isAlive());

	entity1.set(components.@"cubyz:TestComponentRuleOf5", std.mem.zeroes(components.@"cubyz:TestComponentRuleOf5"));
	const actual = entity1.get(components.@"cubyz:TestComponentRuleOf5");

	try std.testing.expect(actual != null);
	try std.testing.expectEqual(1, actual.?.initCalled);
	try std.testing.expectEqual(0, actual.?.moveCalled);
	try std.testing.expectEqual(1, actual.?.copyCalled);

	entity1.deinit();
}

test "Entity with component Hooks" {
	init();
	defer deinit();

	const entity1 = new();
	try std.testing.expect(entity1.isAlive());

	entity1.add(components.@"cubyz:TestComponentHooks");
	entity1.set(components.@"cubyz:TestComponentHooks", std.mem.zeroes(components.@"cubyz:TestComponentHooks"));
	const actual = entity1.get(components.@"cubyz:TestComponentHooks");

	try std.testing.expect(actual != null);

	try std.testing.expectEqual(@intFromPtr(actual), actual.?.selfAddress);

	// try std.testing.expectEqual(1, actual.?.onAddCalled);
	try std.testing.expectEqual(1, actual.?.onSetCalled);

	entity1.deinit();
}
