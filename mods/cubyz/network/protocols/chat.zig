const std = @import("std");

const main = @import("main");
const utils = main.utils;
const Connection = main.network.Connection;

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	const msg = reader.remaining;
	if (!std.unicode.utf8ValidateSlice(msg)) {
		std.log.err("Received chat message with invalid UTF-8 characters.", .{});
		return error.Invalid;
	}
	main.gui.windowlist.chat.addMessage(msg);
}
pub fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	const msg = reader.remaining;
	if (!std.unicode.utf8ValidateSlice(msg)) {
		std.log.err("Received chat message with invalid UTF-8 characters.", .{});
		return error.Invalid;
	}
	const user = conn.user.?;
	if (msg.len > 10000 or main.graphics.TextBuffer.Parser.countVisibleCharacters(msg) > 1000) {
		std.log.err("Received too long chat message with {}/{} characters.", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(msg), msg.len});
		return error.Invalid;
	}
	main.server.messageFrom(msg, user);
}

pub fn send(conn: *Connection, msg: []const u8) void {
	conn.send(.lossy, .@"cubyz:chat", msg);
}
