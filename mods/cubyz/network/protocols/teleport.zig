const std = @import("std");

const main = @import("main");
const game = main.game;
const BinaryReader = main.utils.BinaryReader;
const BinaryWriter = main.utils.BinaryWriter;
const Vec3d = main.vec.Vec3d;

const Connection = main.network.Connection;

pub fn clientReceive(_: *Connection, reader: *BinaryReader) !void {
	game.Player.setPosBlocking(try reader.readVec(Vec3d));
}

pub fn send(conn: *Connection, pos: Vec3d) void {
	var writer = BinaryWriter.initCapacity(main.stackAllocator, 25);
	defer writer.deinit();

	writer.writeVec(Vec3d, pos);

	conn.send(.secure, .@"cubyz:teleport", writer.data.items);
}
