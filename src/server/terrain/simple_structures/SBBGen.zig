const std = @import("std");

const main = @import("root");
//const main = @import("../../../main.zig");
const CaveMapView = main.server.terrain.CaveMap.CaveMapView;
const structure_building_blocks = main.structure_building_blocks;
const Blueprint = main.blueprint.Blueprint;
const ZonElement = main.ZonElement;
const Neighbor = main.chunk.Neighbor;
const ServerChunk = main.chunk.ServerChunk;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub var structures: ?std.StringHashMap(ZonElement) = null;

pub const id = "cubyz:sbb";
pub const generationMode = .floor;

const SBBGen = @This();

structure: []const u8,
placeMode: Blueprint.PasteMode,

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: ZonElement) *SBBGen {
	const self = arenaAllocator.create(SBBGen);
	self.* = .{
		.structure = parameters.get(?[]const u8, "structure", null) orelse unreachable,
		.placeMode = std.meta.stringToEnum(Blueprint.PasteMode, parameters.get([]const u8, "placeMode", "replaceAir")) orelse Blueprint.PasteMode.replaceAir,
	};
	return self;
}

pub fn generate(self: *SBBGen, x: i32, y: i32, z: i32, chunk: *ServerChunk, _: CaveMapView, _: *u64, _: bool) void {
	const structureNullable = structure_building_blocks.getByStringId(self.structure);
	if(structureNullable == null) {
		std.log.err("Could not find structure building block with id '{s}'", .{self.structure});
		return;
	}
	const direction = Neighbor.dirUp;
	const structure = structureNullable.?;
	const blueprintRef = structure.blueprintRef orelse {
		std.log.err("Blueprint '{s}' not found.", .{self.structure});
		return;
	};
	const origin = structure.originBlock orelse {
		std.log.err("Blueprint '{s}' has no detected origin block", .{self.structure});
		return;
	};

	if(origin.direction().axis() != direction.axis()) return {
		std.log.err("Origin axis ('{s}') of blueprint '{s}' is not aligned with the placement axis '{s}'.", .{@tagName(origin.direction().axis()), self.structure, @tagName(direction.axis())});
		return;
	};

	const rotationCount = alignDirections(origin.direction(), direction) catch |err| {
		std.log.err("Could not align directions {s} and {s} error: {s}", .{@tagName(origin.direction()), @tagName(direction), @errorName(err)});
		return;
	};
	var blueprint = blueprintRef.clone(main.stackAllocator);
	defer blueprint.deinit(main.stackAllocator);

	for(0..rotationCount) |_| {
		blueprint.rotateZ();
	}
	const pasteX = x - origin.x;
	const pasteY = y - origin.y;
	const pasteZ = z - origin.z;
	blueprint.pasteInGeneration(.{pasteX, pasteY, pasteZ}, chunk, self.placeMode);
}

fn alignDirections(input: Neighbor, desired: Neighbor) !usize {
	var current = input;
	for(0..4) |i| {
		if(current == desired) return i;
		current = current.rotateZ();
	}
	return error.NotPossibleToAlign;
}
