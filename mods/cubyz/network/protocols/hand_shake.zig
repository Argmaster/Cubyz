const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const settings = main.settings;
const utils = main.utils;
const network = main.network;
const Connection = network.Connection;

var assetsLoadedCondition: main.utils.Condition = .{};
var hasFinishedLoadingAssets: bool = false;
var handshakeZon: ZonElement = undefined;

pub fn clientReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	const newState = try reader.readEnum(Connection.HandShakeState);
	if (@intFromEnum(conn.handShakeState.load(.monotonic)) < @intFromEnum(newState)) {
		conn.handShakeState.store(newState, .monotonic);
		switch (newState) {
			.userData, .signatureResponse, .reload => return error.InvalidSide,
			.signatureRequest => {
				const signature1Len = try reader.readVarInt(usize);
				const signature1 = try reader.readSlice(signature1Len);
				const signature2Len = try reader.readVarInt(usize);
				const signature2 = try reader.readSlice(signature2Len);

				var writer: utils.BinaryWriter = .init(main.stackAllocator);
				defer writer.deinit();
				writer.writeEnum(Connection.HandShakeState, .signatureResponse);
				conn.handShakeState.store(.signatureResponse, .monotonic);

				network.authentication.KeyCollection.sign(&writer, std.meta.stringToEnum(network.authentication.KeyTypeEnum, signature1) orelse return error.Invalid, conn.secureChannel.verificationDataForClientSignature.items);
				if (signature2.len != 0) {
					network.authentication.KeyCollection.sign(&writer, std.meta.stringToEnum(network.authentication.KeyTypeEnum, signature2) orelse return error.Invalid, conn.secureChannel.verificationDataForClientSignature.items);
				}
				conn.send(.secure, .@"cubyz:hand_shake", writer.data.items);
			},
			.assets => {
				std.log.info("Received assets.", .{});
				main.files.cubyzDir().deleteTree("serverAssets") catch {}; // Delete old assets.
				var dir = try main.files.cubyzDir().openDir("serverAssets");
				defer dir.close();
				try utils.Compression.unpack(dir, reader.remaining);
			},
			.serverData => {
				handshakeZon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
				defer handshakeZon.deinit(main.stackAllocator);
				conn.handShakeState.store(.complete, .monotonic);
				conn.handShakeWaiting.broadcast(); // Notify the waiting client thread.
				conn.mutex.lock();
				while (!hasFinishedLoadingAssets) {
					assetsLoadedCondition.wait(&conn.mutex);
				}
				conn.mutex.unlock();
				hasFinishedLoadingAssets = false;
			},
			.start, .complete => {},
		}
	} else {
		// Ignore packages that refer to an unexpected state. Normally those might be packages that were resent by the other side.
	}
}

pub fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
	const newState = try reader.readEnum(Connection.HandShakeState);
	if (@intFromEnum(conn.handShakeState.load(.monotonic)) < @intFromEnum(newState)) {
		conn.handShakeState.store(newState, .monotonic);
		stateSwitch: switch (newState) {
			.userData => {
				conn.secureChannel.finishedCollectingClientVerificationData = true;
				const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
				defer zon.deinit(main.stackAllocator);
				const name = zon.get([]const u8, "name") orelse "unnamed";
				if (!std.unicode.utf8ValidateSlice(name)) {
					std.log.err("Received player name with invalid UTF-8 characters.", .{});
					return error.Invalid;
				}
				if (name.len > 500 or main.graphics.TextBuffer.Parser.countVisibleCharacters(name) > 50) {
					std.log.err("Player has too long name with {}/{} characters.", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(name), name.len});
					return error.Invalid;
				}
				const version = zon.get([]const u8, "version") orelse "unknown";
				std.log.info("User {s} joined using version {s}", .{name, version});

				if (!try settings.version.isCompatibleClientVersion(version)) {
					std.log.warn("Version incompatible with server version {s}", .{settings.version.version});
					return error.IncompatibleVersion;
				}

				if (main.server.world.?.mode != .singleplayer) {
					const keys = zon.getChild("keys");
					try conn.user.?.identifyFromKeysAndName(name, keys, main.server.world.?.settings.whitelistEnabled.load(.monotonic));

					var writer: utils.BinaryWriter = .init(main.stackAllocator);
					defer writer.deinit();
					writer.writeEnum(Connection.HandShakeState, .signatureRequest);
					conn.handShakeState.store(.signatureRequest, .monotonic);
					writer.writeVarInt(usize, @tagName(conn.user.?.key).len);
					writer.writeSlice(@tagName(conn.user.?.key));
					if (conn.user.?.legacyKey) |legacyKey| {
						writer.writeVarInt(usize, @tagName(legacyKey).len);
						writer.writeSlice(@tagName(legacyKey));
					} else {
						writer.writeVarInt(usize, 0);
					}
					conn.send(.secure, .@"cubyz:hand_shake", writer.data.items);
				} else {
					try conn.user.?.identifyAsLocal(name);
					continue :stateSwitch .signatureResponse;
				}
			},
			.signatureResponse, .reload => {
				if (newState != .reload) {
					if (main.server.world.?.mode != .singleplayer) {
						try conn.user.?.verifySignatures(reader);
					}
					conn.user.?.state = .connectedVerified;
				} else {
					// check if player is attempting to reload without logging in (or in an otherwise unexpected state).
					if (conn.user.?.state != .awaitingReloadVerified) return error.KeysNotVerified;
				}
				{
					const path = main.stackAllocator.print("saves/{s}/assets/", .{main.server.world.?.path});
					defer main.stackAllocator.free(path);
					var dir = try main.files.cubyzDir().openIterableDir(path);
					defer dir.close();
					var writer = try std.Io.Writer.Allocating.initCapacity(main.stackAllocator.allocator, 16);
					defer writer.deinit();
					try writer.writer.writeByte(@intFromEnum(Connection.HandShakeState.assets));
					try utils.Compression.pack(dir, &writer.writer);
					conn.send(.secure, .@"cubyz:hand_shake", writer.written());
				}
				conn.handShakeState.store(.assets, .monotonic);

				main.server.connect(conn.user.?);
			},
			.assets, .serverData, .signatureRequest => return error.InvalidSide,
			.start, .complete => {},
		}
	} else {
		// Ignore packages that refer to an unexpected state. Normally those might be packages that were resent by the other side.
	}
}

pub fn serverSide(conn: *Connection) void {
	conn.handShakeState.store(.start, .monotonic);
}

pub fn sendServerPlayerData(conn: *Connection) void {
	const zonObject = ZonElement.initObject(main.stackAllocator);
	defer zonObject.deinit(main.stackAllocator);
	zonObject.put("player", conn.user.?.player().save(main.stackAllocator, .playerHimself));
	zonObject.put("player_id", @intFromEnum(conn.user.?.id));
	zonObject.put("gamemode", @intFromEnum(conn.user.?.gamemode.raw));
	zonObject.put("blockPalette", main.server.world.?.blockPalette.storeToZon(main.stackAllocator));
	zonObject.put("itemPalette", main.server.world.?.itemPalette.storeToZon(main.stackAllocator));
	zonObject.put("toolPalette", main.server.world.?.proceduralItemPalette.storeToZon(main.stackAllocator));
	zonObject.put("biomePalette", main.server.world.?.biomePalette.storeToZon(main.stackAllocator));
	zonObject.put("entityModelPalette", main.server.world.?.entityModelPalette.storeToZon(main.stackAllocator));
	zonObject.put("entityComponentPalette", main.server.world.?.entityComponentPalette.storeToZon(main.stackAllocator));

	const outData = zonObject.toStringEfficient(main.stackAllocator, &[1]u8{@intFromEnum(Connection.HandShakeState.serverData)});
	defer main.stackAllocator.free(outData);
	conn.send(.secure, .@"cubyz:hand_shake", outData);
}

pub fn clientSide(conn: *Connection, name: []const u8) !ZonElement {
	switch (conn.handShakeState.load(.monotonic)) {
		.start => {
			const zonObject = ZonElement.initObject(main.stackAllocator);
			defer zonObject.deinit(main.stackAllocator);

			zonObject.putOwnedString("version", settings.version.version);
			zonObject.putOwnedString("name", name);
			if (main.network.authentication.KeyCollection.initialized) {
				zonObject.put("keys", main.network.authentication.KeyCollection.getPublicKeys(main.stackAllocator));
			}
			try conn.secureChannel.startTlsHandshake();
			conn.secureChannel.finishedCollectingClientVerificationData = true;

			const prefix: [1]u8 = .{@intFromEnum(Connection.HandShakeState.userData)};
			const data = zonObject.toStringEfficient(main.stackAllocator, &prefix);
			defer main.stackAllocator.free(data);

			conn.send(.secure, .@"cubyz:hand_shake", data);
		},
		.reload => {
			conn.send(.secure, .@"cubyz:hand_shake", &.{@intFromEnum(Connection.HandShakeState.reload)});
		},
		else => unreachable,
	}

	{
		conn.mutex.lock();
		defer conn.mutex.unlock();
		while (true) {
			try main.io.checkCancel();
			conn.handShakeWaiting.timedWait(&conn.mutex, .fromMilliseconds(16)) catch {
				main.heap.GarbageCollection.syncPoint();
				continue;
			};
			break;
		}
		if (conn.connectionState.load(.monotonic) == .disconnected) return error.DisconnectedByServer;
	}

	return handshakeZon;
}

pub fn signalLoadedAssets() void {
	hasFinishedLoadingAssets = true;
	assetsLoadedCondition.signal();
}
