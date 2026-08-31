const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const utils = main.utils;
const Vec3i = main.vec.Vec3i;
const Connection = main.network.Connection;

pub fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	const basePosition = try reader.readVec(Vec3i);
	conn.user.?.clientUpdatePos = basePosition;
	conn.user.?.renderDistance = try reader.readInt(u16);
	while (reader.remaining.len >= 4) {
		const x: i32 = try reader.readInt(i8);
		const y: i32 = try reader.readInt(i8);
		const z: i32 = try reader.readInt(i8);
		const voxelSizeShift: u5 = try reader.readInt(u5);
		const positionMask = ~((@as(i32, 1) << voxelSizeShift + chunk.chunkShift) - 1);
		const request = chunk.ChunkPosition{
			.wx = (x << voxelSizeShift + chunk.chunkShift) +% (basePosition[0] & positionMask),
			.wy = (y << voxelSizeShift + chunk.chunkShift) +% (basePosition[1] & positionMask),
			.wz = (z << voxelSizeShift + chunk.chunkShift) +% (basePosition[2] & positionMask),
			.voxelSize = @as(u31, 1) << voxelSizeShift,
		};
		main.server.world.?.queueChunk(request, conn.user.?);
	}
}
pub fn send(conn: *Connection, requests: []chunk.ChunkPosition, basePosition: Vec3i, renderDistance: u16) void {
	if (requests.len == 0) return;
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 14 + 4*requests.len);
	defer writer.deinit();
	writer.writeVec(Vec3i, basePosition);
	writer.writeInt(u16, renderDistance);
	for (requests) |req| {
		const voxelSizeShift: u5 = std.math.log2_int(u31, req.voxelSize);
		const positionMask = ~((@as(i32, 1) << voxelSizeShift + chunk.chunkShift) - 1);
		writer.writeInt(i8, @intCast((req.wx -% (basePosition[0] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
		writer.writeInt(i8, @intCast((req.wy -% (basePosition[1] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
		writer.writeInt(i8, @intCast((req.wz -% (basePosition[2] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
		writer.writeInt(u5, voxelSizeShift);
	}
	conn.send(.secure, .@"cubyz:chunk_request", writer.data.items); // TODO: Can this use the slow channel?
}
