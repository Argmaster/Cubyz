const std = @import("std");

const main = @import("main");
const c = main.c;

initCalled: u8,
moveCalled: u8,
copyCalled: u8,

const Self = @This();

pub fn init(self: *Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	self.initCalled = 1;
	_ = type_info;
}

pub fn move(dst: *Self, src: *Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	dst.moveCalled = src.moveCalled + 1;
	_ = type_info;
}

pub fn copy(dst: *Self, src: *const Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	dst.copyCalled = src.copyCalled + 1;
	_ = type_info;
}

pub fn deinit(self: *Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	_ = self;
	_ = type_info;
}
