const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const game = main.game;
const settings = main.settings;
const utils = main.utils;

const network = main.network;
const Connection = network.Connection;

pub const MeshGenerationTask = struct {
	pos: chunk.ChunkPosition,
	data: []const u8,

	pub const vtable = utils.ThreadPool.VTable{
		.getPriority = main.meta.castFunctionSelfToAnyopaque(getPriority),
		.isStillNeeded = main.meta.castFunctionSelfToAnyopaque(isStillNeeded),
		.run = main.meta.castFunctionSelfToAnyopaque(run),
		.clean = main.meta.castFunctionSelfToAnyopaque(clean),
		.taskType = .meshgenAndLighting,
	};

	pub fn getPriority(self: *MeshGenerationTask) f32 {
		return self.pos.getPriority(game.Player.getPosBlocking()); // TODO: This is called in loop, find a way to do this without calling the mutex every time.
	}

	pub fn isStillNeeded(self: *MeshGenerationTask) bool {
		if (main.game.world == null or main.game.world.?.paused) return false;
		const distanceSqr = self.pos.getMinDistanceSquared(@trunc(game.Player.getPosBlocking())); // TODO: This is called in loop, find a way to do this without calling the mutex every time.
		var maxRenderDistance = settings.renderDistance*chunk.chunkSize*self.pos.voxelSize;
		maxRenderDistance += 2*self.pos.voxelSize*chunk.chunkSize;
		return distanceSqr < maxRenderDistance*maxRenderDistance;
	}

	pub fn run(self: *MeshGenerationTask) void {
		defer self.clean();
		const pos = self.pos;
		const mesh = main.renderer.chunk_meshing.ChunkMesh.init(pos, self.data) catch |err| {
			std.log.err("Could not load chunk mesh from server: {s} Disconnecting.", .{@errorName(err)});
			main.game.world.?.conn.disconnect();
			return;
		};
		mesh.generateLightingData() catch mesh.deferredDeinit();
	}

	pub fn clean(self: *MeshGenerationTask) void {
		main.globalAllocator.free(self.data);
		main.globalAllocator.destroy(self);
	}
};

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	const task = main.globalAllocator.create(MeshGenerationTask);
	errdefer main.globalAllocator.destroy(task);
	task.* = .{
		.pos = .{
			.wx = try reader.readInt(i32),
			.wy = try reader.readInt(i32),
			.wz = try reader.readInt(i32),
			.voxelSize = try reader.readInt(u31),
		},
		.data = main.globalAllocator.dupe(u8, reader.remaining),
	};
	main.threadPool.addTask(task, &MeshGenerationTask.vtable);
}

pub fn send(conn: *Connection, ch: *chunk.ServerChunk) void {
	ch.mutex.lock();
	const chunkData = main.server.storage.ChunkCompression.storeChunk(main.stackAllocator, &ch.super, .toClient, ch.super.pos.voxelSize != 1);
	ch.mutex.unlock();
	defer main.stackAllocator.free(chunkData);
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, chunkData.len + 16);
	defer writer.deinit();
	writer.writeInt(i32, ch.super.pos.wx);
	writer.writeInt(i32, ch.super.pos.wy);
	writer.writeInt(i32, ch.super.pos.wz);
	writer.writeInt(u31, ch.super.pos.voxelSize);
	writer.writeSlice(chunkData);
	conn.send(.secure, .@"cubyz:chunk_transmission", writer.data.items); // TODO: Can this use the slow channel?
}
