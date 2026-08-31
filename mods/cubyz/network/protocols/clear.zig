const main = @import("main");
const utils = main.utils;
const Connection = main.network.Connection;

const ClearType = enum(u1) {
	chat = 0,
};

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	const typ = try reader.readEnum(ClearType);
	switch (typ) {
		.chat => main.gui.windowlist.chat.clearChat(),
	}
}

pub fn send(conn: *Connection, cleartype: ClearType) void {
	conn.send(.lossy, .@"cubyz:clear", &.{@intFromEnum(cleartype)}); // TODO change channel afer #1879
}