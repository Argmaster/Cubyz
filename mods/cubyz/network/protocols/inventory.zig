const std = @import("std");

const main = @import("main");
const utils = main.utils;
const Connection = main.network.Connection;

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	const typ = try reader.readInt(u8);
	if (typ == 0xff) { // Confirmation
		try main.sync.client.receiveConfirmation(reader);
	} else if (typ == 0xfe) { // Failure
		main.sync.client.receiveFailure();
	} else {
		try main.sync.client.receiveSyncOperation(reader);
	}
}
pub fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	const user = conn.user.?;
	if (reader.remaining[0] == 0xff) return error.Invalid;
	main.sync.server.receiveCommand(user, reader);
}
pub fn sendCommand(conn: *Connection, payloadType: main.sync.Command.PayloadType, _data: []const u8) void {
	std.debug.assert(conn.user == null);
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, _data.len + 1);
	defer writer.deinit();
	writer.writeEnum(main.sync.Command.PayloadType, payloadType);
	std.debug.assert(writer.data.items[0] != 0xff);
	writer.writeSlice(_data);
	conn.send(.secure, .@"cubyz:inventory", writer.data.items);
}
pub fn sendConfirmation(conn: *Connection, _data: []const u8) void {
	std.debug.assert(conn.isServerSide());
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, _data.len + 1);
	defer writer.deinit();
	writer.writeInt(u8, 0xff);
	writer.writeSlice(_data);
	conn.send(.secure, .@"cubyz:inventory", writer.data.items);
}
pub fn sendFailure(conn: *Connection) void {
	std.debug.assert(conn.isServerSide());
	conn.send(.secure, .@"cubyz:inventory", &.{0xfe});
}
pub fn sendSyncOperation(conn: *Connection, _data: []const u8) void {
	std.debug.assert(conn.isServerSide());
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, _data.len + 1);
	defer writer.deinit();
	writer.writeInt(u8, 0);
	writer.writeSlice(_data);
	conn.send(.secure, .@"cubyz:inventory", writer.data.items);
}
