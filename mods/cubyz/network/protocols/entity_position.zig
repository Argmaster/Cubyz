const main = @import("main");
const utils = main.utils;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Connection = main.network.Connection;

const Type = enum(u8) {
	noVelocityEntity = 0,
	f16VelocityEntity = 1,
	f32VelocityEntity = 2,
	noVelocityItem = 3,
	f16VelocityItem = 4,
	f32VelocityItem = 5,
};

pub fn clientReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	if (conn.manager.world) |world| {
		const time = try reader.readInt(i16);
		const playerPos = try reader.readVec(Vec3d);
		var entityData: main.ListManaged(main.entity.EntityNetworkData) = .init(main.stackAllocator);
		defer entityData.deinit();
		var itemData: main.ListManaged(main.itemdrop.ItemDropNetworkData) = .init(main.stackAllocator);
		defer itemData.deinit();
		while (reader.remaining.len != 0) {
			const typ = try reader.readEnum(Type);
			switch (typ) {
				.noVelocityEntity, .f16VelocityEntity, .f32VelocityEntity => {
					entityData.append(.{
						.vel = switch (typ) {
							.noVelocityEntity => @splat(0),
							.f16VelocityEntity => @floatCast(try reader.readVec(@Vector(3, f16))),
							.f32VelocityEntity => @floatCast(try reader.readVec(@Vector(3, f32))),
							else => unreachable,
						},
						.id = try reader.readEnum(main.entity.Entity),
						.pos = playerPos + try reader.readVec(Vec3f),
						.rot = try reader.readVec(Vec3f),
					});
				},
				.noVelocityItem, .f16VelocityItem, .f32VelocityItem => {
					itemData.append(.{
						.vel = switch (typ) {
							.noVelocityItem => @splat(0),
							.f16VelocityItem => @floatCast(try reader.readVec(@Vector(3, f16))),
							.f32VelocityItem => @floatCast(try reader.readVec(Vec3f)),
							else => unreachable,
						},
						.index = try reader.readInt(u16),
						.pos = playerPos + try reader.readVec(Vec3f),
					});
				},
			}
		}
		main.client.entity_manager.serverUpdate(time, entityData.items);
		world.itemDrops.readPosition(time, itemData.items);
	}
}
pub fn send(conn: *Connection, playerPos: Vec3d, entityData: []const main.entity.EntityNetworkData, itemData: []const main.itemdrop.ItemDropNetworkData) void {
	var writer = utils.BinaryWriter.init(main.stackAllocator);
	defer writer.deinit();

	writer.writeInt(i16, @truncate(main.timestamp().toMilliseconds()));
	writer.writeVec(Vec3d, playerPos);
	for (entityData) |data| {
		const velocityMagnitudeSqr = vec.lengthSquare(data.vel);
		if (velocityMagnitudeSqr < 1e-6*1e-6) {
			writer.writeEnum(Type, .noVelocityEntity);
		} else if (velocityMagnitudeSqr > 1000*1000) {
			writer.writeEnum(Type, .f32VelocityEntity);
			writer.writeVec(Vec3f, @floatCast(data.vel));
		} else {
			writer.writeEnum(Type, .f16VelocityEntity);
			writer.writeVec(@Vector(3, f16), @floatCast(data.vel));
		}
		writer.writeEnum(main.entity.Entity, data.id);
		writer.writeVec(Vec3f, @floatCast(data.pos - playerPos));
		writer.writeVec(Vec3f, data.rot);
	}
	for (itemData) |data| {
		const velocityMagnitudeSqr = vec.lengthSquare(data.vel);
		if (velocityMagnitudeSqr < 1e-6*1e-6) {
			writer.writeEnum(Type, .noVelocityItem);
		} else if (velocityMagnitudeSqr > 1000*1000) {
			writer.writeEnum(Type, .f32VelocityItem);
			writer.writeVec(Vec3f, @floatCast(data.vel));
		} else {
			writer.writeEnum(Type, .f16VelocityItem);
			writer.writeVec(@Vector(3, f16), @floatCast(data.vel));
		}
		writer.writeInt(u16, data.index);
		writer.writeVec(Vec3f, @floatCast(data.pos - playerPos));
	}
	conn.send(.lossy, .@"cubyz:entity_position", writer.data.items);
}
