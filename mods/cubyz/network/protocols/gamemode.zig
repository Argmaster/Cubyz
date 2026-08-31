const main = @import("main");
const utils = main.utils;
const Connection = main.network.Connection;

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	main.sync.setGamemode(null, try reader.readEnum(main.game.Gamemode));
}

pub fn send(conn: *Connection, gamemode: main.game.Gamemode) void {
	conn.send(.secure, .@"cubyz:gamemode", &.{@intFromEnum(gamemode)});
}