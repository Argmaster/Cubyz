const main = @import("main");
const Block = main.blocks.Block;
const renderer = main.renderer;
const utils = main.utils;
const Vec3i = main.vec.Vec3i;
const BlockUpdate = renderer.mesh_storage.BlockUpdate;
const Connection = main.network.Connection;

pub fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	while (reader.remaining.len != 0) {
		renderer.mesh_storage.updateBlock(.{
			.pos = try reader.readVec(Vec3i),
			.newBlock = Block.fromInt(try reader.readInt(u32)),
			.blockEntityData = try reader.readSlice(try reader.readInt(usize)),
		});
	}
}

pub fn send(conn: *Connection, updates: []const BlockUpdate) void {
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 16);
	defer writer.deinit();

	for (updates) |update| {
		writer.writeVec(Vec3i, update.pos);
		writer.writeInt(u32, update.newBlock.toInt());
		writer.writeInt(usize, update.blockEntityData.len);
		writer.writeSlice(update.blockEntityData);
	}
	conn.send(.secure, .@"cubyz:block_update", writer.data.items);
}
