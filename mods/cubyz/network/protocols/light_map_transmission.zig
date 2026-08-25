const std = @import("std");

const main = @import("main");
const renderer = main.renderer;
const utils = main.utils;
const Connection = main.network.Connection;

const LightMapTask = struct {
	wx: i32,
	wy: i32,
	voxelSizeShift: u5,
	data: []const u8,

	const vtable = utils.ThreadPool.VTable{
		.getPriority = main.meta.castFunctionSelfToAnyopaque(getPriority),
		.isStillNeeded = main.meta.castFunctionSelfToAnyopaque(isStillNeeded),
		.run = main.meta.castFunctionSelfToAnyopaque(run),
		.clean = main.meta.castFunctionSelfToAnyopaque(clean),
		.taskType = .misc,
	};

	pub fn getPriority(_: *LightMapTask) f32 {
		return std.math.floatMax(f32);
	}

	pub fn isStillNeeded(_: *LightMapTask) bool {
		if (main.game.world == null or main.game.world.?.paused) return false;
		return true;
	}

	pub fn run(self: *LightMapTask) void {
		defer self.clean();

		const pos = main.server.terrain.SurfaceMap.MapFragmentPosition{
			.wx = self.wx,
			.wy = self.wy,
			.voxelSize = @as(u31, 1) << self.voxelSizeShift,
			.voxelSizeShift = self.voxelSizeShift,
		};
		const _inflatedData = main.stackAllocator.alloc(u8, main.server.terrain.LightMap.LightMapFragment.mapSize*main.server.terrain.LightMap.LightMapFragment.mapSize*2);
		defer main.stackAllocator.free(_inflatedData);
		const _inflatedLen = utils.Compression.inflateTo(_inflatedData, self.data) catch |err| {
			std.log.err("Got error {s} while decompressing lightmap data at position {} with data {any}", .{@errorName(err), pos, self.data});
			main.game.world.?.conn.disconnect();
			return;
		};
		if (_inflatedLen != main.server.terrain.LightMap.LightMapFragment.mapSize*main.server.terrain.LightMap.LightMapFragment.mapSize*2) {
			std.log.err("Transmission of light map has invalid size: {}. Input data: {any}, After inflate: {any}", .{_inflatedLen, self.data, _inflatedData[0.._inflatedLen]});
			main.game.world.?.conn.disconnect();
			return;
		}
		var ligthMapReader = utils.BinaryReader.init(_inflatedData);
		const map = main.globalAllocator.create(main.server.terrain.LightMap.LightMapFragment);
		map.init(pos.wx, pos.wy, pos.voxelSize);
		for (&map.startHeight) |*val| {
			val.* = ligthMapReader.readInt(i16) catch |err| {
				std.log.err("Got error {s} while reading decompressed lightmap data at position {} with data {any}", .{@errorName(err), pos, _inflatedData});
				main.game.world.?.conn.disconnect();
				return;
			};
		}
		renderer.mesh_storage.updateLightMap(map);
	}

	pub fn clean(self: *LightMapTask) void {
		main.globalAllocator.free(self.data);
		main.globalAllocator.destroy(self);
	}
};

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	const task = main.globalAllocator.create(LightMapTask);
	errdefer main.globalAllocator.destroy(task);
	task.* = .{
		.wx = try reader.readInt(i32),
		.wy = try reader.readInt(i32),
		.voxelSizeShift = try reader.readInt(u5),
		.data = main.globalAllocator.dupe(u8, reader.remaining),
	};
	main.threadPool.addTask(task, &LightMapTask.vtable);
}
pub fn send(conn: *Connection, map: *main.server.terrain.LightMap.LightMapFragment) void {
	var ligthMapWriter = utils.BinaryWriter.initCapacity(main.stackAllocator, @sizeOf(@TypeOf(map.startHeight)));
	defer ligthMapWriter.deinit();
	for (&map.startHeight) |val| {
		ligthMapWriter.writeInt(i16, val);
	}
	const compressedData = utils.Compression.deflate(main.stackAllocator, ligthMapWriter.data.items, .default);
	defer main.stackAllocator.free(compressedData);
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 9 + compressedData.len);
	defer writer.deinit();
	writer.writeInt(i32, map.pos.wx);
	writer.writeInt(i32, map.pos.wy);
	writer.writeInt(u8, map.pos.voxelSizeShift);
	writer.writeSlice(compressedData);
	conn.send(.secure, .@"cubyz:light_map_transmission", writer.data.items); // TODO: Can this use the slow channel?
}
