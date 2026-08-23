const std = @import("std");

const mods = @import("mods");

const Mod = struct {
	init: fn (mod: Mod) void,
	register: fn (mod: Mod) void,
	deinit: fn (mod: Mod) void,
};

fn init() void {
	for (@typeInfo(mods).@"struct".decls) |decl| {
		@field(mods, decl.name).init(@field(mods, decl.name));
	}
}

fn iterateFeature(comptime feature: []const u8) void {
	mods;
}
