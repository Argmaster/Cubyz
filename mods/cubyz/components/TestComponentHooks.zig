const std = @import("std");

const main = @import("main");
const Vec3d = main.vec.Vec3d;

avxAlignedField: Vec3d,
onSetCalled: u32,
onAddCalled: u32,
selfAddress: u64,

const Self = @This();

pub fn onAdd(self: *Self) void {
	self.onAddCalled += 1;
	self.selfAddress = @intFromPtr(self);
	std.debug.print("address {}\n", .{self.selfAddress});
}

pub fn onSet(self: *Self) void {
	self.onSetCalled += 1;
	self.selfAddress = @intFromPtr(self);
}
