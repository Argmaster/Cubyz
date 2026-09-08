const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");
const main = @import("main");

pub const components = @import("components");

var wasCustomOsApiInitialized = false;

const allocationAlignment = std.mem.Alignment.fromByteUnits(64);
const allocationHeaderSizeBytes = 64;

fn custom_malloc(size: c.ecs_size_t) callconv(.c) ?*anyopaque {
	const requestedSize: usize = @intCast(size);
	const totalSizeBytes: usize = requestedSize + allocationHeaderSizeBytes;
	const allocation = main.globalAllocator.rawAlloc(totalSizeBytes, allocationAlignment, @returnAddress()) orelse return null;
	const header: *align(64) usize = @ptrCast(@alignCast(allocation));
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

	const oldAllocation: [*]align(64) u8 = @alignCast(@as([*]u8, @ptrCast(ptr.?)) - allocationHeaderSizeBytes);
	const oldHeader: *align(64) usize = @ptrCast(oldAllocation);
	const oldSize = oldHeader.*;
	const newAllocation = custom_malloc(size) orelse return null;
	const newSize: usize = @intCast(size);
	@memcpy(@as([*]u8, @ptrCast(newAllocation))[0..@min(oldSize, newSize)], @as([*]u8, @ptrCast(ptr.?))[0..@min(oldSize, newSize)]);
	custom_free(ptr);
	return newAllocation;
}

fn custom_free(ptr: ?*anyopaque) callconv(.c) void {
	const allocationPtr = ptr orelse return;
	const allocation: [*]align(64) u8 = @alignCast(@as([*]u8, @ptrCast(allocationPtr)) - allocationHeaderSizeBytes);
	const header: *align(64) usize = @ptrCast(allocation);
	const size = header.*;
	main.globalAllocator.rawFree(allocation[0 .. size + allocationHeaderSizeBytes], allocationAlignment, @returnAddress());
}

const componentsMeta = blk: {
	const componentCount = @typeInfo(components).@"struct".decls.len;
	var componentNames: [componentCount][]const u8 = undefined;

	for (@typeInfo(components).@"struct".decls, 0..) |declaration_info, index| {
		const component = @field(components, declaration_info.name);
		componentNames[index] = ecsId(component);
	}

	const Meta = struct {
		const count: usize = componentCount;
		const names: [componentCount][]const u8 = componentNames;

		const ComponentIds: type = @Struct(.@"extern", null, names[0..count], &@splat(u64), &@splat(.{}));
	};
	break :blk Meta;
};

fn ecsId(Component: type) []const u8 {
	return @typeName(Component);
}

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

pub const World = struct {
	ecsWorld: *c.ecs_world_t,
	/// We need to retain per-world component IDs to later use them for entities.
	componentIds: componentsMeta.ComponentIds,

	pub fn init() World {
		if (!wasCustomOsApiInitialized) initCustomOsApi();

		const world = c.ecs_init() orelse unreachable;
		var ids: componentsMeta.ComponentIds = undefined;

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
							const zigHooks = Hooks(Component);

							if (@hasDecl(Component, "init")) {
								hooks.ctor = &zigHooks.init;
							}

							break :blk hooks;
						},
					},
				},
			);
			@field(ids, ecsId(Component)) = result;
			std.debug.assert(result != 0);
			std.log.debug("Registered component: {s}", .{ecsId(Component)});
		}
		return World{
			.ecsWorld = world,
			.componentIds = ids,
		};
	}
	pub fn deinit(self: World) void {
		const result = c.ecs_fini(self.ecsWorld);
		std.debug.assert(result == 0);
	}
	pub fn new(self: *const World) FlecsEntity {
		return FlecsEntity.init(c.ecs_new(self.ecsWorld), self);
	}
};

pub fn Hooks(Component: type) type {
	return struct {
		pub fn init(ptr: ?*anyopaque, count: i32, type_info: ?*const c.ecs_type_info_t) callconv(.c) void {
			std.debug.print("Initializing component: {s}\n", .{@typeName(Component)});
			if (builtin.mode == .Debug) {
				if (@sizeOf(Component) != type_info.?.size)
					@panic("Component size mismatch in init for " ++ @typeName(Component));
				if (@alignOf(Component) != type_info.?.alignment)
					@panic("Component alignment mismatch in init for " ++ @typeName(Component));
			}
			const instances: []Component = @as([*]Component, @ptrCast(ptr.?))[0..@intCast(count)];
			for (instances) |*instance| {
				Component.init(instance, type_info.?);
			}
		}
	};
}

pub const FlecsEntity = struct {
	entity_handle: c.ecs_entity_t,
	world: *const World,

	fn init(e: c.ecs_entity_t, w: *const World) FlecsEntity {
		return FlecsEntity{
			.entity_handle = e,
			.world = w,
		};
	}
	pub fn deinit(self: FlecsEntity) void {
		c.ecs_delete(self.world.ecsWorld, self.entity_handle);
	}
	pub fn getName(self: FlecsEntity) [*:0]const u8 {
		return c.ecs_get_name(self.world.ecsWorld, self.entity_handle) orelse "<unnamed>";
	}
	pub fn isAlive(self: FlecsEntity) bool {
		return c.ecs_is_alive(self.world.ecsWorld, self.entity_handle);
	}
	pub fn get(self: FlecsEntity, Component: type) ?*const Component {
		const componentId = @field(self.world.componentIds, ecsId(Component));
		if (c.ecs_get_id(self.world.ecsWorld, self.entity_handle, componentId)) |result| {
			return @ptrCast(@alignCast(result));
		}
		return null;
	}
	pub fn set(self: FlecsEntity, Component: type, value: Component) void {
		const componentId = @field(self.world.componentIds, ecsId(Component));
		c.ecs_set_id(self.world.ecsWorld, self.entity_handle, componentId, @sizeOf(Component), &value);
	}
};

test "Entity with Velocity" {
	const world = World.init();
	defer world.deinit();

	const entity1 = world.new();
	try std.testing.expect(entity1.isAlive());

	const expected: components.@"cubyz:Velocity" = .{.vel = .{1, 2, 3}};

	entity1.set(components.@"cubyz:Velocity", expected);
	const actual = entity1.get(components.@"cubyz:Velocity");

	try std.testing.expect(actual != null);
	try std.testing.expect(@reduce(.And, expected.vel == actual.?.vel));

	entity1.deinit();
}

test "Entity with test component" {
	const world = World.init();
	defer world.deinit();

	const entity1 = world.new();
	try std.testing.expect(entity1.isAlive());

	entity1.set(components.@"cubyz:TestComponentFull", std.mem.zeroes(components.@"cubyz:TestComponentFull"));
	const actual = entity1.get(components.@"cubyz:TestComponentFull");

	try std.testing.expect(actual != null);
	// try std.testing.expect(1 == actual.?.initCalled);

	entity1.deinit();
}
