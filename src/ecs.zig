
const std = @import("std");
const c = @import("c");
const components = @import("components");

fn ecsId(Component: type) []const u8 {
	return "FLECS_ID" ++ @typeName(Component) ++ "ID_";
}

const componentsMeta = blk: {
	var componentCount: usize = 0;
	var componentTypes: [1024]type = undefined;
	var componentNames: [1024][]const u8 = undefined;

	for (@typeInfo(components).@"struct".decls) |declaration_info| {
		const componentModule = @field(components, declaration_info.name);
		for (componentModule.register()) |componentType| {
			componentTypes[componentCount] = componentType;
			componentNames[componentCount] = @typeName(componentType);
			componentCount += 1;
		}
	}

	const Meta = struct {
		const count: usize = componentCount;

		const typesStatic: [1024]type = componentTypes;
		const types: []const type = typesStatic[0..componentCount];

		const namesStatic: [1024][]const u8 = componentNames;
		const names: []const []const u8 = namesStatic[0..componentCount];

		const IdsType: type = @Struct(.@"extern", null, names[0..count], &@splat(u64), &@splat(.{}));
	};
	break :blk Meta;
};

pub const World = struct {
	ecsWorld: *c.ecs_world_t,
	componentIds: componentsMeta.IdsType,

	pub fn init() World {
		const world = c.ecs_init() orelse unreachable;
		var ids: componentsMeta.IdsType = undefined;

		inline for (componentsMeta.types, componentsMeta.names) |typ, name| {
			const result = c.ecs_component_init(world, &c.ecs_component_desc_t{
				.entity = c.ecs_entity_init(world, &c.ecs_entity_desc_t{
					.use_low_id = true,
					.name = @typeName(typ),
					.symbol = @typeName(typ),
				}),
				.@"type" = .{
					.size = @sizeOf(typ),
					.alignment = @alignOf(typ),
				}
			});
			@field(ids, name) = result;
			std.debug.assert(result != 0);
			std.log.debug("Registered component: {s}", .{name});
		}
		return World{
			.ecsWorld = world,
			.componentIds = ids,
		};
	}
	pub fn deinit(self: World) void {
		std.debug.assert(c.ecs_fini(self.ecsWorld) == 0);
	}
	pub fn new(self: World) FlecsEntity {
		return FlecsEntity.init(c.ecs_new(self.ecsWorld), &self);
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
	fn get(self: FlecsEntity,  Component: type) *const Component {
		return c.ecs_get_id(self.world.ecsWorld, self.entity_handle, ecsId(Component));
	}
	fn set(self: FlecsEntity, Component: type, value: *const Component) void {
		c.ecs_set_id(self.world.ecsWorld, self.entity_handle, ecsId(Component), value);
	}
};

pub const ComponentId = enum (u64) {
	_,
};


