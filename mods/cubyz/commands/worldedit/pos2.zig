const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;
const Vec3i = main.vec.Vec3i;

const mods = @import("mods");

pub const description = "Select the player position as position 2.";
pub const usage = "/pos2";

pub const Args = union(enum) {
	@"/pos2": struct {},
};

pub fn execute(_: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	const pos: Vec3i = @floor(user.player().pos);

	user.worldEditData.selectionPosition2 = pos;
	mods.cubyz.network.protocols.world_edit_pos.send(user.conn, .selectedPos2, pos);

	user.sendMessage("Position 2: {}", .{pos});
}
