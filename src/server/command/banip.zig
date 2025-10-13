const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Ban player IP";
pub const usage = "/banip <ip>";

pub fn execute(args: []const u8, source: *User) void {
	const ip = main.network.Socket.resolveIP(args) catch {
		source.sendMessage("#ffff00{s}", .{@tagName(source.gamemode.load(.monotonic))});
		std.log.err("Invalid IP {s}", .{args});
		return;
	};
	for(main.server.connectionManager.banned.items) |ip_| {
		if(ip_ == ip) return;
	}
	main.server.connectionManager.banned.append(main.globalAllocator, ip);

	var zon = main.ZonElement.initArray(main.stackAllocator);
	defer zon.deinit(main.stackAllocator);
	for(main.server.connectionManager.banned.items) |ip_| {
		zon.append(ip_);
	}
	main.files.cwd().writeZon("banned_ips.zig.zon", zon) catch {
		source.sendMessage("#ffff00Failed to save banned IPs to zon.", .{});
		std.log.err("Failed to save banned IPs to zon.", .{});
		return;
	};
}
