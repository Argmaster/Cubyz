const main = @import("main");
const game = main.game;
const utils = main.utils;
const Vec3i = main.vec.Vec3i;
const Connection = main.network.Connection;

pub const WorldEditPosition = enum(u2) {
	selectedPos1 = 0,
	selectedPos2 = 1,
	clear = 2,
};

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	const typ = try reader.readEnum(WorldEditPosition);
	const pos: ?Vec3i = switch (typ) {
		.selectedPos1, .selectedPos2 => try reader.readVec(Vec3i),
		.clear => null,
	};
	switch (typ) {
		.selectedPos1 => game.Player.selectionPosition1 = pos,
		.selectedPos2 => game.Player.selectionPosition2 = pos,
		.clear => {
			game.Player.selectionPosition1 = null;
			game.Player.selectionPosition2 = null;
		},
	}
}

pub fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	const typ = try reader.readEnum(WorldEditPosition);
	const pos: ?Vec3i = switch (typ) {
		.selectedPos1, .selectedPos2 => try reader.readVec(Vec3i),
		.clear => null,
	};
	switch (typ) {
		.selectedPos1 => conn.user.?.worldEditData.selectionPosition1 = pos.?,
		.selectedPos2 => conn.user.?.worldEditData.selectionPosition2 = pos.?,
		.clear => {
			conn.user.?.worldEditData.selectionPosition1 = null;
			conn.user.?.worldEditData.selectionPosition2 = null;
		},
	}
}

pub fn send(conn: *Connection, posType: WorldEditPosition, maybePos: ?Vec3i) void {
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 25);
	defer writer.deinit();

	writer.writeEnum(WorldEditPosition, posType);
	if (maybePos) |pos| {
		writer.writeVec(Vec3i, pos);
	}

	conn.send(.secure, .@"cubyz:world_edit_pos", writer.data.items);
}
