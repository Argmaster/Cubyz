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

const mods = @import("mods");


pub const ProtocolBackingInt = u8;
const maxProtocolCount = std.math.maxInt(ProtocolBackingInt);
const protocolCount = main.mods.getFeatureCount(.@"network/protocols");

pub const Protocols = blk: {
	if (protocolCount > maxProtocolCount) { // TODO: Use VarInt if more than 255 protocols are needed.
		@compileError("Too many protocols.");
	}

	var names: [protocolCount][]const u8 = @splat("");
	var values: [protocolCount]ProtocolBackingInt = @splat(0);

	for (main.mods.getFeatures(.@"network/protocols"), 0..) |protocol, i| {
		names[i] = protocol.id;
		values[i] = @truncate(i);
	}

	break :blk @Enum(ProtocolBackingInt, .nonexhaustive, &names, &values);
};

var clientReceiveList: [protocolCount]?*const fn (*Connection, *utils.BinaryReader) anyerror!void = @splat(null);
var serverReceiveList: [protocolCount]?*const fn (*Connection, *utils.BinaryReader) anyerror!void = @splat(null);
pub var bytesReceived: [protocolCount]Atomic(usize) = @splat(.init(0));
pub var bytesSent: [protocolCount]Atomic(usize) = @splat(.init(0));

pub fn init() void { // MARK: init()
	main.mods.walkFeatureContext(.@"network/protocols", void, undefined, registerProtocol);
}

fn registerProtocol(_: void, descriptor: main.mods.ObjectDescriptor) void {
	const id = std.meta.stringToEnum(Protocols, descriptor.id) orelse unreachable;
	const index: ProtocolBackingInt = @intFromEnum(id);

	std.debug.assert(clientReceiveList[index] == null);
	std.debug.assert(serverReceiveList[index] == null);

	var flags: u8 = 0;

	if (@hasDecl(descriptor.object, "clientReceive")) {
		clientReceiveList[index] = descriptor.object.clientReceive;
		flags |= 0b01;
	} else {
		clientReceiveList[index] = failingClientReceive;
	}
	if (@hasDecl(descriptor.object, "serverReceive")) {
		serverReceiveList[index] = descriptor.object.serverReceive;
		flags |= 0b10;
	} else {
		serverReceiveList[index] = failingServerReceive;
	}

	std.log.debug("Registered protocol {s} as {} ({b:0<2})", .{descriptor.id, index, flags});
}

pub fn onReceive(conn: *Connection, protocolIndex: u8, data: []const u8) !void { // MARK: onReceive()
	if (protocolIndex >= protocolCount) return error.Invalid;
	const proto: Protocols = @enumFromInt(protocolIndex);

	if (conn.handShakeState.raw != .complete and proto != .@"cubyz:hand_shake") return error.HandshakeIncomplete;
	const protocolReceive = blk: {
		if (conn.isServerSide()) break :blk serverReceiveList[protocolIndex] orelse return error.Invalid;
		break :blk clientReceiveList[protocolIndex] orelse return error.Invalid;
	};

	var reader = utils.BinaryReader.init(data);
	protocolReceive(conn, &reader) catch |err| {
		std.log.debug("Got error while executing protocol {} with data {any}", .{proto, data});
		return err;
	};

	_ = bytesReceived[protocolIndex].fetchAdd(data.len, .monotonic);
}

fn failingServerReceive(_: *Connection, _: *utils.BinaryReader) !void {
	return error.ServerReceiveNotSupported;
}

fn failingClientReceive(_: *Connection, _: *utils.BinaryReader) !void {
	return error.ClientReceiveNotSupported;
}

pub fn getIndex(comptime proto: Protocols) ProtocolBackingInt {
	return @intFromEnum(proto);
}
