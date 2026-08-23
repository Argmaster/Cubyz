const main = @import("main");
const Mod = main.mods.Mod;
const cubyz = main.mods.cubyz;


fn init(_: Mod) void {
}

fn register(mod: Mod) void {
	mod.registerRotations();
}

fn deinit(_: Mod) void {
	main.deinit();
}
