hooksCalled: u8

pub fn onSet(self: *Self) void {
	self.hooksCalled += 1;
}