const std = @import("std");

const main = @import("main");
const c = main.c;

initCalled: u8,

const Self = @This();

pub fn init(self: *Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	self.initCalled = 1;
	std.debug.print("\nInitializing TestComponentRuleOf5 {*} {}\n", .{self, self.initCalled});
	_ = type_info;
}

pub fn move(dst: *Self, src: *Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	std.debug.print("Moving TestComponentRuleOf5 from {*} to {*}\n", .{src, dst});
	_ = type_info;
}

pub fn copy(dst: *Self, src: *const Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	std.debug.print("Copying TestComponentRuleOf5 from {*} to {*}\n", .{src, dst});
	_ = type_info;
}

pub fn deinit(self: *Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	std.debug.print("Deinitializing TestComponentRuleOf5 {*}\n", .{self});
	_ = type_info;
}
