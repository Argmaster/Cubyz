const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const utils = main.utils;
const Connection = main.network.Connection;

pub fn clientReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	const zonArray = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
	defer zonArray.deinit(main.stackAllocator);
	var i: u32 = 0;
	while (i < zonArray.array.items.len) : (i += 1) {
		const elem = zonArray.array.items[i];
		switch (elem) {
			.int => {
				main.client.entity_manager.removeEntity(@enumFromInt(elem.as(u32) orelse return error.Invalid));
			},
			.object => {
				try main.client.entity_manager.addEntity(elem);
			},
			.null => {
				i += 1;
				break;
			},
			else => {
				std.log.err("Unrecognized zon parameters for \"cubyz:entity\" protocol: {s}", .{reader.remaining});
			},
		}
	}
	while (i < zonArray.array.items.len) : (i += 1) {
		const elem: ZonElement = zonArray.array.items[i];
		if (elem == .int) {
			conn.manager.world.?.itemDrops.remove(elem.as(u16) orelse return error.Invalid);
		} else if (!elem.getChild("array").isNull()) {
			conn.manager.world.?.itemDrops.loadFrom(elem);
		} else {
			conn.manager.world.?.itemDrops.addFromZon(elem);
		}
	}
}
pub fn send(conn: *Connection, msg: []const u8) void {
	conn.send(.secure, .@"cubyz:entity", msg);
}
