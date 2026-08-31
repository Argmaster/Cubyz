const main = @import("main");
const Mod = main.mods.Mod;
const mods = @import("mods");
const cubyz = mods.cubyz;

fn init(_: Mod) void {}

fn register(_: Mod) void {}

fn deinit(_: Mod) void {
	main.deinit();
}
