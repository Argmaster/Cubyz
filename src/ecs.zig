
const std = @import("std");
const c = @import("c");

fn ecsId(Component: type) []const u8 {
	return "FLECS_ID" ++ @typeName(Component) ++ "ID_";
}

pub const World = struct {
	world: *c.ecs_world_t,

	pub fn init() World {
		return World{
			.world = c.ecs_init() orelse unreachable,
		};
	}
	pub fn deinit(self: World) void {
		std.debug.assert(c.ecs_fini(self.world) == 0);
	}
	pub fn new(self: World) FlecsEntity {
		return FlecsEntity.init(c.ecs_new(self.world), self.world);
	}
	pub fn addComponent(self: World, Component: type) void {
		var edesc = c.ecs_entity_desc_t{
			.use_low_id = true,
			.name = @tagName(Component),
			.symbol = @tagName(Component),
		};
		var desc = c.ecs_component_desc_t{
			.entity = c.ecs_entity_init(self.world, &edesc),
			.@"type" = .{
				.size = @sizeOf(Component),
				.alignment = @alignOf(Component),
			}
		};
		const result = c.ecs_component_init(self.world, &desc);
		std.debug.assert(result != 0, c.ECS_INVALID_PARAMETER, "failed to create component %s", @tagName(Component));
	}
};

pub const FlecsEntity = struct {
	entity_handle: c.ecs_entity_t,
	world_handle: *c.ecs_world_t,

	fn init(e: c.ecs_entity_t, w: *c.ecs_world_t) FlecsEntity {
		return FlecsEntity{
			.entity_handle = e,
			.world_handle = w,
		};
	}
	pub fn deinit(self: FlecsEntity) void {
		c.ecs_delete(self.world_handle, self.entity_handle);
	}
	pub fn isAlive(self: FlecsEntity) bool {
		return c.ecs_is_alive(self.world_handle, self.entity_handle) != 0;
	}
	fn get(self: FlecsEntity,  Component: type) *const Component {
		return c.ecs_get(self.world_handle, self.entity_handle, ecsId(Component));
	}
	fn set(self: FlecsEntity, Component: type, value: *const Component) void {
		c.ecs_set(self.world_handle, self.entity_handle, ecsId(Component), value);
	}
};


