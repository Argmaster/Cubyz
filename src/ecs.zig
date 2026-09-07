const std = @import("std");
const c = @import("c");
const components = @import("components");

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

pub const World = struct {
	ecsWorld: *c.ecs_world_t,
	componentIds: componentsMeta.ComponentIds,

	pub fn init() World {
		const world = c.ecs_init() orelse unreachable;
		var ids: componentsMeta.ComponentIds = undefined;

		inline for (@typeInfo(components).@"struct".decls) |declaration_info| {
			const component = @field(components, declaration_info.name);
			const result = c.ecs_component_init(
				world,
				&c.ecs_component_desc_t{
					.entity = c.ecs_entity_init(
						world,
						&c.ecs_entity_desc_t{
							.use_low_id = true,
							.name = @typeName(component),
							.symbol = @typeName(component),
						},
					),
					.type = .{
						.size = @sizeOf(component),
						.alignment = @alignOf(component),
					},
				},
			);
			@field(ids, ecsId(component)) = result;
			std.debug.assert(result != 0);
			std.log.debug("Registered component: {s}", .{ecsId(component)});
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
	fn get(self: FlecsEntity, Component: type) *const Component {
		const componentId = @field(self.world.componentIds, ecsId(Component));
		return c.ecs_get_id(self.world.ecsWorld, self.entity_handle, componentId);
	}
	fn set(self: FlecsEntity, Component: type, value: *const Component) void {
		const componentId = @field(self.world.componentIds, ecsId(Component));
		c.ecs_set_id(self.world.ecsWorld, self.entity_handle, componentId, value);
	}
};
