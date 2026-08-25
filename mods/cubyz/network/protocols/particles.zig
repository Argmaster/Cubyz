const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const Block = main.blocks.Block;
const chunk = main.chunk;
const particles = main.particles;
const items = main.items;
const ZonElement = main.ZonElement;
const game = main.game;
const settings = main.settings;
const renderer = main.renderer;
const utils = main.utils;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const BlockUpdate = renderer.mesh_storage.BlockUpdate;

const network = main.network;
const Connection = network.Connection;

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	const particleIdLen = try reader.readVarInt(u16);
	const particleId = try reader.readSlice(particleIdLen);
	const pos = try reader.readVec(Vec3d);
	const collides = try reader.readBool();
	const count = try reader.readVarInt(u32);
	const spawnZonLen = try reader.readVarInt(usize);
	const spawnZon = try reader.readSlice(spawnZonLen);

	var emitter: particles.Emitter = undefined;
	if (spawnZonLen != 0) {
		const zon = ZonElement.parseFromString(main.stackAllocator, null, spawnZon);
		defer zon.deinit(main.stackAllocator);
		emitter = .initFromZon(particleId, collides, zon);
	} else {
		const emitterProperties = particles.EmitterProperties{
			.speed = .init(1, 1.5),
			.lifeTime = .init(0.75, 1),
			.randomizeRotation = true,
		};
		emitter = .init(particleId, collides, .{.point = .{}}, emitterProperties, .spread);
	}

	particles.ParticleSystem.addParticlesFromNetwork(emitter, pos, count);
}

pub fn send(conn: *Connection, particleId: []const u8, pos: Vec3d, collides: bool, count: u32, spawnZon: []const u8) void {
	const bufferSize = particleId.len*8 + 32;
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, bufferSize);
	defer writer.deinit();

	writer.writeVarInt(u16, @intCast(particleId.len));
	writer.writeSlice(particleId);
	writer.writeVec(Vec3d, pos);
	writer.writeBool(collides);
	writer.writeVarInt(u32, count);
	writer.writeVarInt(usize, spawnZon.len);
	writer.writeSlice(spawnZon);

	conn.send(.secure, .@"cubyz:particles", writer.data.items);
}
