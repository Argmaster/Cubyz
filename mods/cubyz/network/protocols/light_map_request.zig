const main = @import("main");
const utils = main.utils;
const Connection = main.network.Connection;

pub fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	while (reader.remaining.len >= 9) {
		const wx = try reader.readInt(i32);
		const wy = try reader.readInt(i32);
		const voxelSizeShift = try reader.readInt(u5);
		const request = main.server.terrain.SurfaceMap.MapFragmentPosition{
			.wx = wx,
			.wy = wy,
			.voxelSize = @as(u31, 1) << voxelSizeShift,
			.voxelSizeShift = voxelSizeShift,
		};
		if (conn.user) |user| {
			main.server.world.?.queueLightMap(request, user);
		}
	}
}
pub fn send(conn: *Connection, requests: []main.server.terrain.SurfaceMap.MapFragmentPosition) void {
	if (requests.len == 0) return;
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 9*requests.len);
	defer writer.deinit();
	for (requests) |req| {
		writer.writeInt(i32, req.wx);
		writer.writeInt(i32, req.wy);
		writer.writeInt(u8, req.voxelSizeShift);
	}
	conn.send(.secure, .@"cubyz:light_map_request", writer.data.items); // TODO: Can this use the slow channel?
}
