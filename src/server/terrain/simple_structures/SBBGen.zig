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

pub fn generate(self: *SBBGen, x: i32, y: i32, z: i32, chunk: *ServerChunk, _: CaveMapView, seed: *u64, _: bool) void {
	placeSbb(self, self.structure, x, y, z, Neighbor.dirUp, chunk, seed);
}

fn placeSbb(self: *SBBGen, structureId: []const u8, x: i32, y: i32, z: i32, placementDirection: Neighbor, chunk: *ServerChunk, seed: *u64) void {
	const structureNullable = structure_building_blocks.getByStringId(structureId);
	if(structureNullable == null) {
		std.log.err("Could not find structure building block with id '{s}'", .{structureId});
		return;
	}
	const structure = structureNullable.?;
	const blueprintRef = structure.blueprintRef orelse {
		std.log.err("Blueprint '{s}' not found.", .{structureId});
		return;
	};
	const origin = structure.originBlock orelse {
		std.log.err("Blueprint '{s}' has no detected origin block", .{structureId});
		return;
	};

	const rotationCount = alignDirections(origin.direction(), placementDirection) catch |err| {
		std.log.err("Could not align directions {s} and {s} error: {s}", .{@tagName(origin.direction()), @tagName(placementDirection), @errorName(err)});
		return;
	};
	var rotated = blueprintRef.rotateZ(main.stackAllocator, @enumFromInt(rotationCount));
	defer rotated.deinit(main.stackAllocator);

	const directionReverse = origin.direction();

	for(structure.childrenBlocks.items) |childBlock| {
		const childNullable = structure.children.pickChild(childBlock.block, seed);
		if(childNullable) |child| {
			placeSbb(self, child.structure, x + childBlock.x, y + childBlock.y, z + childBlock.z, childBlock.direction(), chunk, seed);
		}
	}

	const pasteX = x - origin.x - directionReverse.relX();
	const pasteY = y - origin.y - directionReverse.relY();
	const pasteZ = z - origin.z - directionReverse.relZ();
	rotated.pasteInGeneration(.{pasteX, pasteY, pasteZ}, chunk, self.placeMode);
}

fn alignDirections(input: Neighbor, desired: Neighbor) !usize {
	var current = input;
	for(0..4) |i| {
		if(current == desired) return i;
		current = current.rotateZ();
	}
	return error.NotPossibleToAlign;
}
