const main = @import("main");
const game = main.game;
const utils = main.utils;
const Vec3d = main.vec.Vec3d;
const Connection = main.network.Connection;

pub fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	try conn.user.?.receiveData(reader);
}

var lastPositionSent: u16 = 0;
pub fn send(conn: *Connection, playerPos: Vec3d, playerVel: Vec3d, time: u16) void {
	if (time -% lastPositionSent < 50) {
		return; // Only send at most once every 50 ms.
	}
	lastPositionSent = time;
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 62);
	defer writer.deinit();
	writer.writeInt(u64, @bitCast(playerPos[0]));
	writer.writeInt(u64, @bitCast(playerPos[1]));
	writer.writeInt(u64, @bitCast(playerPos[2]));
	writer.writeInt(u64, @bitCast(playerVel[0]));
	writer.writeInt(u64, @bitCast(playerVel[1]));
	writer.writeInt(u64, @bitCast(playerVel[2]));
	writer.writeInt(u32, @bitCast(game.camera.rotation[0]));
	writer.writeInt(u32, @bitCast(game.camera.rotation[1]));
	writer.writeInt(u32, @bitCast(game.camera.rotation[2]));
	writer.writeInt(u16, time);
	conn.send(.lossy, .@"cubyz:player_position", writer.data.items);
}
