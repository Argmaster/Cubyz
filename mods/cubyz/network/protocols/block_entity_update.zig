const main = @import("main");
const Block = main.blocks.Block;
const chunk = main.chunk;
const utils = main.utils;
const Vec3i = main.vec.Vec3i;
const Connection = main.network.Connection;

const mods = @import("mods");

pub fn serverReceive(_: *Connection, reader: *utils.BinaryReader) !void {
	const pos = try reader.readVec(Vec3i);
	const blockType = try reader.readInt(u16);
	const simChunk = main.server.world.?.getSimulationChunkAndIncreaseRefCount(pos[0], pos[1], pos[2]) orelse return;
	defer simChunk.decreaseRefCount();
	const ch = simChunk.chunk.load(.monotonic) orelse return;
	ch.mutex.lock();
	defer ch.mutex.unlock();
	const block = ch.getBlock(pos[0] - ch.super.pos.wx, pos[1] - ch.super.pos.wy, pos[2] - ch.super.pos.wz);
	if (block.typ != blockType) return;
	const blockEntity = block.blockEntity() orelse return;
	try blockEntity.updateServerData(pos, &ch.super, .{.update = reader});
	ch.setChanged();

	sendServerDataUpdateToClientsInternal(pos, &ch.super, block, blockEntity);
}

pub fn sendClientDataUpdateToServer(conn: *Connection, pos: Vec3i) void {
	const mesh = main.renderer.mesh_storage.getMesh(.initFromWorldPos(pos, 1)) orelse return;
	mesh.mutex.lock();
	defer mesh.mutex.unlock();
	const localPos = mesh.chunk.getLocalBlockPos(pos);
	const block = mesh.chunk.data.getValue(localPos.toIndex());
	const blockEntity = block.blockEntity() orelse return;

	var writer = utils.BinaryWriter.init(main.stackAllocator);
	defer writer.deinit();
	writer.writeVec(Vec3i, pos);
	writer.writeInt(u16, block.typ);
	blockEntity.getClientToServerData(pos, mesh.chunk, &writer);

	conn.send(.secure, .@"cubyz:block_entity_update", writer.data.items);
}

fn sendServerDataUpdateToClientsInternal(pos: Vec3i, ch: *chunk.Chunk, block: Block, blockEntity: *const main.block_entity.BlockEntityType) void {
	var writer = utils.BinaryWriter.init(main.stackAllocator);
	defer writer.deinit();
	blockEntity.getServerToClientData(pos, ch, &writer);

	const users = main.server.getUserList(main.stackAllocator);
	defer main.stackAllocator.free(users);

	for (users) |user| {
		mods.cubyz.network.protocols.block_update.send(user.conn, &.{.{.pos = pos, .newBlock = block, .blockEntityData = writer.data.items}});
	}
}

pub fn sendServerDataUpdateToClients(pos: Vec3i) void {
	const simChunk = main.server.world.?.getSimulationChunkAndIncreaseRefCount(pos[0], pos[1], pos[2]) orelse return;
	defer simChunk.decreaseRefCount();
	const ch = simChunk.chunk.load(.monotonic) orelse return;
	ch.mutex.lock();
	defer ch.mutex.unlock();
	const block = ch.getBlock(pos[0] - ch.super.pos.wx, pos[1] - ch.super.pos.wy, pos[2] - ch.super.pos.wz);
	const blockEntity = block.blockEntity() orelse return;

	sendServerDataUpdateToClientsInternal(pos, &ch.super, block, blockEntity);
}
