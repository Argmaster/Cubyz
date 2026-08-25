const main = @import("main");
const utils = main.utils;
const Connection = main.network.Connection;

pub fn clientReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	const world = conn.manager.world.?;
	const biomeId = try reader.readInt(u32);

	const newBiome = main.server.terrain.biomes.getByIndex(biomeId) orelse return error.MissingBiome;
	const oldBiome = world.playerBiome.swap(newBiome, .monotonic);
	if (oldBiome != newBiome) {
		main.audio.setMusic(newBiome.preferredMusic);
	}
}

pub fn send(conn: *Connection, biomeIndex: u32) void {
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 13);
	defer writer.deinit();

	writer.writeInt(u32, biomeIndex);

	conn.send(.secure, .@"cubyz:biome", writer.data.items);
}
