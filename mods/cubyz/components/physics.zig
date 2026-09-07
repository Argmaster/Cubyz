const main = @import("main");
const ecs = main.ecs;
const vec = main.vec;

pub const Velocity = extern struct {
	vel: vec.Vec3d,
};

pub const Position = extern struct {
	pos: vec.Vec3d,
};

pub const Rotation = extern struct {
	rot: vec.Vec3f,
};

pub fn register() []const type {
	return &.{Velocity, Position, Rotation};
}
