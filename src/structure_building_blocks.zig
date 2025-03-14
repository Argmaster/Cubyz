const std = @import("std");

// const main = @import("root");
const main = @import("main.zig");
const terrain = main.server.terrain;
const ZonElement = main.ZonElement;
const Blueprint = main.blueprint.Blueprint;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const alloc = arena.allocator();
const allocator = alloc.allocator;

var current: ?std.StringHashMapUnmanaged(ZonElement) = null;
var blueprints: ?std.StringHashMapUnmanaged(Blueprint) = null;

pub fn registerSBB(structures: *std.StringHashMap(ZonElement)) void {
	std.log.info("Registering {} structure building blocks", .{structures.count()});
	if(current != null) freeMapAndEntries(ZonElement, &current.?);

	current = .{};
	current.?.ensureTotalCapacity(allocator, structures.count()) catch unreachable;

	var iterator = structures.iterator();
	while(iterator.next()) |entry| {
		current.?.put(allocator, allocator.dupe(u8, entry.key_ptr.*) catch unreachable, entry.value_ptr.clone(alloc)) catch unreachable;
		std.log.info("Registered structure building block: {s}", .{entry.key_ptr.*});
	}
}

fn freeMapAndEntries(comptime T: type, map: *std.StringHashMapUnmanaged(T)) void {
	var iterator = map.iterator();
	while(iterator.next()) |entry| {
		allocator.free(entry.key_ptr.*);
		entry.value_ptr.deinit(alloc);
	}
	map.deinit(allocator);
}

pub fn reset() void {
	if(current != null) freeMapAndEntries(ZonElement, &current.?);
}
