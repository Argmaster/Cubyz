const std = @import("std");

const mods = @import("mods");

pub const Feature = enum {
	other,
	@"callbacks/block/client",
	@"callbacks/block/server",
	@"callbacks/block/touch",
	commands,
	@"ecs/client/components",
	@"ecs/server/components",
	@"ecs/storage",
	@"ecs/systems",
	@"gui/components",
	@"gui/windows",
	items,
	key_binds,
	modifiers,
	@"network/protocols",
	rotations,
	@"sync/atomics",
	@"sync/messages",
	@"sync/transactions",
	@"terrain/cave_biome_gen",
	@"terrain/cave_gen",
	@"terrain/chunk_gen",
	@"terrain/climate_gen",
	@"terrain/map_gen",
	@"terrain/sdf_models",
	@"terrain/simple_structures",
	@"terrain/structure_map_gen",
};

pub const ObjectDescriptor = struct {
	mod: []const u8,
	id: []const u8,
	object: type,
};

const Mod = struct {
	init: fn (mod: Mod) void,
	register: fn (mod: Mod) void,
	deinit: fn (mod: Mod) void,
};

pub fn init() void {
	for (@typeInfo(mods).@"struct".decls) |decl| {
		@field(mods, decl.name).init(@field(mods, decl.name));
	}
}

pub fn walkFeature(
	comptime feature: []const []const u8,
	comptime ContextT: type,
	comptime context: ContextT,
	comptime callback: fn (context: ContextT, feature: ObjectDescriptor) void,
) void {
	inline for (mods._ModMeta.directoryIterator) |modDesc| {
		for (@typeInfo(@field(mods, modDesc.mod)).@"struct".fields) |field| {
			const featureList = @field(@field(mods, modDesc.mod), field.name);
			callback(context, @field(featureList, feature));
		}
	}
}
