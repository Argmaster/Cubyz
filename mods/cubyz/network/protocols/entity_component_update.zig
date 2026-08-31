const main = @import("main");
const utils = main.utils;
const Connection = main.network.Connection;

const ActionType = enum(u8) {
	unload = 0,
	load = 1,
};

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	const entityId: main.entity.Entity = @enumFromInt(try reader.readVarInt(u32));
	const componentId = try reader.readVarInt(u32);
	const actionType: ActionType = try reader.readEnum(ActionType);

	if (actionType == .load) {
		const componentVersion = try reader.readVarInt(u32);
		try main.entity.loadComponent(.client, componentId, entityId, reader.remaining, componentVersion);
	} else if (actionType == .unload) {
		try main.entity.unloadComponent(.client, componentId, entityId);
	}
}

pub fn unload(conn: *Connection, entityId: main.entity.Entity, componentId: u32) void {
	var writer = utils.BinaryWriter.init(main.stackAllocator);
	defer writer.deinit();

	writer.writeVarInt(u32, @intFromEnum(entityId));
	writer.writeVarInt(u32, componentId);
	writer.writeEnum(ActionType, ActionType.unload);

	conn.send(.secure, .@"cubyz:entity_component_update", writer.data.items);
}

pub fn load(conn: *Connection, entityId: main.entity.Entity, componentId: u32, version: u32, componentData: []const u8) void {
	var writer = utils.BinaryWriter.init(main.stackAllocator);
	defer writer.deinit();

	writer.writeVarInt(u32, @intFromEnum(entityId));
	writer.writeVarInt(u32, componentId);
	writer.writeEnum(ActionType, ActionType.load);
	// specific to `load`
	writer.writeVarInt(u32, version);
	writer.writeSlice(componentData);

	conn.send(.secure, .@"cubyz:entity_component_update", writer.data.items);
}
