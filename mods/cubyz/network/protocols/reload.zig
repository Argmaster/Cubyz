const main = @import("main");
const utils = main.utils;
const Connection = main.network.Connection;

pub fn informClientOfRestart(conn: *Connection) void {
	var writer = utils.BinaryWriter.init(main.stackAllocator);
	defer writer.deinit();

	writer.writeInt(u32, conn.restartCounter);
	writer.writeEnum(main.server.User.State, conn.user.?.state);

	conn.send(.secure, .@"cubyz:reload", writer.data.items);
	conn.send(.lossy, .@"cubyz:reload", writer.data.items);
	conn.send(.slow, .@"cubyz:reload", writer.data.items);
}

pub fn informServerOfRestart(conn: *Connection) void {
	var writer = utils.BinaryWriter.init(main.stackAllocator);
	defer writer.deinit();

	writer.writeInt(u32, conn.restartCounter);
	conn.send(.secure, .@"cubyz:reload", writer.data.items);
	conn.send(.lossy, .@"cubyz:reload", writer.data.items);
	conn.send(.slow, .@"cubyz:reload", writer.data.items);
}
