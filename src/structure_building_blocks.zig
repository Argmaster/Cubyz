const std = @import("std");

const main = @import("main.zig");
const terrain = main.server.terrain;
const ZonElement = main.ZonElement;
const Blueprint = main.blueprint.Blueprint;
const List = main.List;
const Neighbor = main.chunk.Neighbor;
const Block = main.blocks.Block;
const parseBlock = main.blocks.parseBlock;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const cubyz_allocator = arena.allocator();
const std_allocator = cubyz_allocator.allocator;

var structureCache: ?std.StringHashMapUnmanaged(StructureBuildingBlock) = null;
var blueprintCache: ?std.StringHashMapUnmanaged(Blueprint) = null;

const originBlockStringId = "cubyz:sbb/origin";
var originBlockNumericId: u16 = 0;

const childrenBlockStringId = [_][]const u8{
	"cubyz:sbb/child/aqua",
	"cubyz:sbb/child/black",
	"cubyz:sbb/child/blue",
	"cubyz:sbb/child/brown",
	"cubyz:sbb/child/crimson",
	"cubyz:sbb/child/cyan",
	"cubyz:sbb/child/dark_grey",
	"cubyz:sbb/child/green",
	"cubyz:sbb/child/grey",
	"cubyz:sbb/child/indigo",
	"cubyz:sbb/child/lime",
	"cubyz:sbb/child/magenta",
	"cubyz:sbb/child/orange",
	"cubyz:sbb/child/pink",
	"cubyz:sbb/child/purple",
	"cubyz:sbb/child/red",
	"cubyz:sbb/child/violet",
	"cubyz:sbb/child/viridian",
	"cubyz:sbb/child/white",
	"cubyz:sbb/child/yellow",
};
var childrenBlockNumericId = [_]u16{
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
};

const StructureBlock = struct {
	x: i32,
	y: i32,
	z: i32,
	block: Block,

	pub inline fn direction(self: StructureBlock) Neighbor {
		return @enumFromInt(self.block.data);
	}
};

const StructureBuildingBlock = struct {
	stringId: []const u8,
	blueprintId: []const u8,
	children: Children,

	blueprintRef: ?*Blueprint,
	originBlock: ?StructureBlock,
	childrenBlocks: List(StructureBlock),

	fn initFromZon(stringId: []const u8, zon: ZonElement) StructureBuildingBlock {
		const blueprintId = zon.get(?[]const u8, "blueprint", null);
		if(blueprintId == null) {
			std.log.err("[{s}] Missing blueprint field.", .{stringId});
			return undefined;
		}
		const blueprintRef = blueprintCache.?.getEntry(blueprintId.?);
		if(blueprintRef == null) {
			std.log.err("[{s}] Could not find blueprint '{s}'.", .{stringId, blueprintId.?});
			return undefined;
		}

		var self = StructureBuildingBlock{
			.stringId = cubyz_allocator.dupe(u8, stringId),
			.blueprintId = cubyz_allocator.dupe(u8, blueprintId.?),
			.children = Children.initFromZon(stringId, zon.getChild("children")),
			.blueprintRef = if(blueprintRef) |bp| bp.value_ptr else null,
			.originBlock = null,
			.childrenBlocks = List(StructureBlock).init(cubyz_allocator),
		};
		if(blueprintRef != null) self.findOriginAndChildrenBlocks();

		return self;
	}

	fn findOriginAndChildrenBlocks(self: *StructureBuildingBlock) void {
		std.debug.assert(self.blueprintRef != null);

		var blockIndex: usize = 0;
		const blueprint = self.blueprintRef.?;

		for(0..blueprint.sizeX) |x| {
			for(0..blueprint.sizeY) |y| {
				for(0..blueprint.sizeZ) |z| {
					const block = blueprint.blocks.items[blockIndex];
					if(isOriginBlock(block)) {
						if(self.originBlock != null) {
							std.log.err("[{s}] Multiple origin blocks found.", .{self.stringId});
						} else {
							self.originBlock = StructureBlock{
								.x = @intCast(x),
								.y = @intCast(y),
								.z = @intCast(z),
								.block = block,
							};
						}
					} else if(isChildBlock(block)) {
						self.childrenBlocks.append(StructureBlock{
							.x = @intCast(x),
							.y = @intCast(y),
							.z = @intCast(z),
							.block = block,
						});
					}
					blockIndex += 1;
				}
			}
		}
		if(self.originBlock == null) {
			std.log.err("[{s}] No origin block found.", .{self.stringId});
		}
	}
};

pub fn isChildBlock(block: Block) bool {
	for(childrenBlockNumericId) |numericId| {
		if(block.typ == numericId) return true;
	}
	return false;
}

pub fn isOriginBlock(block: Block) bool {
	return block.typ == originBlockNumericId;
}

const Children = struct {
	aqua: ?List(Child),
	black: ?List(Child),
	blue: ?List(Child),
	brown: ?List(Child),
	crimson: ?List(Child),
	cyan: ?List(Child),
	dark_grey: ?List(Child),
	green: ?List(Child),
	grey: ?List(Child),
	indigo: ?List(Child),
	lime: ?List(Child),
	magenta: ?List(Child),
	orange: ?List(Child),
	pink: ?List(Child),
	purple: ?List(Child),
	red: ?List(Child),
	violet: ?List(Child),
	viridian: ?List(Child),
	white: ?List(Child),
	yellow: ?List(Child),

	fn initFromZon(stringId: []const u8, zon: ZonElement) Children {
		return .{
			.aqua = initChildListFromZon("aqua", stringId, zon.getChild("aqua")),
			.black = initChildListFromZon("black", stringId, zon.getChild("black")),
			.blue = initChildListFromZon("blue", stringId, zon.getChild("blue")),
			.brown = initChildListFromZon("brown", stringId, zon.getChild("brown")),
			.crimson = initChildListFromZon("crimson", stringId, zon.getChild("crimson")),
			.cyan = initChildListFromZon("cyan", stringId, zon.getChild("cyan")),
			.dark_grey = initChildListFromZon("dark_grey", stringId, zon.getChild("dark_grey")),
			.green = initChildListFromZon("green", stringId, zon.getChild("green")),
			.grey = initChildListFromZon("grey", stringId, zon.getChild("grey")),
			.indigo = initChildListFromZon("indigo", stringId, zon.getChild("indigo")),
			.lime = initChildListFromZon("lime", stringId, zon.getChild("lime")),
			.magenta = initChildListFromZon("magenta", stringId, zon.getChild("magenta")),
			.orange = initChildListFromZon("orange", stringId, zon.getChild("orange")),
			.pink = initChildListFromZon("pink", stringId, zon.getChild("pink")),
			.purple = initChildListFromZon("purple", stringId, zon.getChild("purple")),
			.red = initChildListFromZon("red", stringId, zon.getChild("red")),
			.violet = initChildListFromZon("violet", stringId, zon.getChild("violet")),
			.viridian = initChildListFromZon("viridian", stringId, zon.getChild("viridian")),
			.white = initChildListFromZon("white", stringId, zon.getChild("white")),
			.yellow = initChildListFromZon("yellow", stringId, zon.getChild("yellow")),
		};
	}
};

fn initChildListFromZon(comptime childName: []const u8, stringId: []const u8, zon: ZonElement) ?List(Child) {
	if(zon == .null) return null;
	if(zon != .array) {
		std.log.err("[{s}->{s}] Incorrect child data structure, array expected.", .{stringId, childName});
		return null;
	}
	var list = List(Child).initCapacity(cubyz_allocator, zon.array.items.len);
	if(zon.array.items.len == 0) {
		std.log.warn("[{s}->{s}] Empty children list.", .{stringId, childName});
	}
	for(zon.array.items, 0..) |entry, i| {
		list.appendAssumeCapacity(Child.initFromZon(childName, stringId, i, entry));
	}
	return list;
}

const Child = struct {
	childBlockStringId: []const u8,
	structure: []const u8,
	chance: f32,

	fn initFromZon(comptime childName: []const u8, stringId: []const u8, i: usize, zon: ZonElement) Child {
		const self = Child{
			.childBlockStringId = std.fmt.allocPrint(std_allocator, "cubyz:sbb/child/{s}", .{childName}) catch unreachable,
			.structure = cubyz_allocator.dupe(u8, zon.get([]const u8, "structure", "")),
			.chance = zon.get(f32, "chance", 0.0),
		};
		if(self.chance == 0) {
			std.log.warn("[{s}->{s}->{}] Child node has has 0.0 spawn chance.", .{stringId, childName, i});
		}
		if(self.chance < 0.0 or self.chance > 1.0) {
			std.log.warn("[{s}->{s}->{}] Child node has spawn chance outside of [0, 1] range ({}).", .{stringId, childName, i, self.chance});
		}
		if(self.structure.len == 0) {
			std.log.warn("[{s}->{s}->{}] Child node has empty structure field.", .{stringId, childName, i});
		}
		return self;
	}
};

pub fn registerSBB(structures: *std.StringHashMap(ZonElement)) !void {
	std.log.info("Registering {} structure building blocks", .{structures.count()});
	if(structureCache != null) {
		std.log.err("Attempting to register new SBBs without resetting cache.", .{});
		return error.AlreadyRegistered;
	}

	originBlockNumericId = parseBlock(originBlockStringId).typ;
	std.log.info("Origin block numeric id: {}", .{originBlockNumericId});
	for(0..childrenBlockNumericId.len) |i| {
		childrenBlockNumericId[i] = parseBlock(childrenBlockStringId[i]).typ;
		std.log.info("Child block '{s}'' numeric id: {}", .{childrenBlockStringId[i], childrenBlockNumericId[i]});
	}

	structureCache = .{};
	structureCache.?.ensureTotalCapacity(std_allocator, structures.count()) catch unreachable;

	var iterator = structures.iterator();
	while(iterator.next()) |entry| {
		structureCache.?.put(std_allocator, cubyz_allocator.dupe(u8, entry.key_ptr.*), StructureBuildingBlock.initFromZon(entry.key_ptr.*, entry.value_ptr.*)) catch unreachable;
		std.log.info("Registered structure building block: {s}", .{entry.key_ptr.*});
	}
}

pub fn registerBlueprints(blueprints: *std.StringHashMap([]u8)) !void {
	std.log.info("Registering {} blueprints", .{blueprints.count()});
	if(blueprintCache != null) {
		std.log.err("Attempting to register new blueprints without resetting cache.", .{});
		return error.AlreadyRegistered;
	}

	blueprintCache = .{};
	blueprintCache.?.ensureTotalCapacity(std_allocator, blueprints.count()) catch unreachable;

	var iterator = blueprints.iterator();
	while(iterator.next()) |entry| {
		const stringId = entry.key_ptr.*;
		var blueprint = Blueprint.init(cubyz_allocator);

		blueprint.load(entry.value_ptr.*) catch |err| {
			std.log.err("Could not load blueprint {s}: {s}", .{stringId, @errorName(err)});
			continue;
		};

		blueprintCache.?.put(std_allocator, cubyz_allocator.dupe(u8, stringId), blueprint) catch unreachable;
		std.log.info("Registered blueprint: {s}", .{stringId});
	}
}

pub fn getByStringId(stringId: []const u8) ?StructureBuildingBlock {
	return structureCache.?.get(stringId);
}

pub fn reset() void {
	_ = arena.reset(.free_all);
	structureCache = null;
	blueprintCache = null;
}
