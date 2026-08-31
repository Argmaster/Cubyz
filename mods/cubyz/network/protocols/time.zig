const main = @import("main");
const utils = main.utils;
const Connection = main.network.Connection;

pub fn clientReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	const world = conn.manager.world.?;
	const expectedTime = try reader.readInt(i64);

	var curTime = world.gameTime.load(.monotonic);
	if (@abs(curTime -% expectedTime) >= 10) {
		world.gameTime.store(expectedTime, .monotonic);
	} else if (curTime < expectedTime) { // world.gameTime++
		while (world.gameTime.cmpxchgWeak(curTime, curTime +% 1, .monotonic, .monotonic)) |actualTime| {
			curTime = actualTime;
		}
	} else { // world.gameTime--
		while (world.gameTime.cmpxchgWeak(curTime, curTime -% 1, .monotonic, .monotonic)) |actualTime| {
			curTime = actualTime;
		}
	}
}

pub fn send(conn: *Connection, world: *const main.server.ServerWorld) void {
	var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 13);
	defer writer.deinit();

	writer.writeInt(i64, world.gameTime);

	conn.send(.secure, .@"cubyz:time", writer.data.items);
}