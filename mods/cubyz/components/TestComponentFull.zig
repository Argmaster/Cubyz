const main = @import("main");
const c = main.c;

initCalled: u8,
deinitCalled: u8,

const Self = @This();

pub fn init(self: *Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	self.initCalled += 1;
	_ = type_info;
}

pub fn deinit(self: *Self, type_info: *const c.ecs_type_info_t) callconv(.c) void {
	self.deinitCalled += 1;
	_ = type_info;
}
