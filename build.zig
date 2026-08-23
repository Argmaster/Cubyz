const std = @import("std");

fn libName(b: *std.Build, name: []const u8, target: std.Target) []const u8 {
	return switch (target.os.tag) {
		.windows => b.fmt("{s}.lib", .{name}),
		else => b.fmt("lib{s}.a", .{name}),
	};
}

fn linkLibraries(b: *std.Build, exe: *std.Build.Step.Compile, useLocalDeps: bool) void {
	const target = exe.root_module.resolved_target.?;
	const t = target.result;
	const optimize = exe.root_module.optimize.?;

	const depsLib = b.fmt("cubyz_deps_{s}-{s}-{s}", .{@tagName(t.cpu.arch), @tagName(t.os.tag), switch (t.os.tag) {
		.linux => "musl",
		.macos => "none",
		.windows => "gnu",
		else => "none",
	}});
	const artifactName = libName(b, depsLib, t);

	var depsName: []const u8 = b.fmt("cubyz_deps_{s}_{s}", .{@tagName(t.cpu.arch), @tagName(t.os.tag)});
	if (useLocalDeps) depsName = "local";

	const libsDeps = b.lazyDependency(depsName, .{
		.target = target,
		.optimize = optimize,
	}) orelse {
		// Lazy dependencies with a `url` field will fail here the first time.
		// build.zig will restart and try again.
		std.log.info("Downloading cubyz_deps libraries {s}.", .{depsName});
		return;
	};
	const headersDeps = if (useLocalDeps) libsDeps else b.lazyDependency("cubyz_deps_headers", .{}) orelse {
		std.log.info("Downloading cubyz_deps headers {s}.", .{depsName});
		return;
	};

	exe.root_module.addIncludePath(headersDeps.path("include"));
	exe.root_module.addObjectFile(libsDeps.path("lib").path(b, artifactName));
	const subPath = libsDeps.path("lib").path(b, depsLib);
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "glslang", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "MachineIndependent", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "GenericCodeGen", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "glslang-default-resource-limits", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "SPIRV", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "SPIRV-Tools", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "SPIRV-Tools-opt", t)));

	const translate_c = b.addTranslateC(.{
		.root_source_file = b.path("src/c.h"),
		.target = target,
		.optimize = optimize,
	});
	translate_c.addIncludePath(headersDeps.path("include"));

	exe.root_module.addImport("c", translate_c.createModule());

	if (t.os.tag == .macos) {
		const moltenVkLibInstall = b.addInstallFile(subPath.path(b, "libMoltenVK.dylib"), "bin/Cubyz.app/Contents/Frameworks/libMoltenVK.dylib");
		const moltenVkJsonInstall = b.addInstallFile(subPath.path(b, "MoltenVK_icd.json"), "bin/Cubyz.app/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json");
		exe.step.dependOn(&moltenVkLibInstall.step);
		exe.step.dependOn(&moltenVkJsonInstall.step);

		const validationLayerLibInstall = b.addInstallFile(subPath.path(b, "libVkLayer_khronos_validation.dylib"), "bin/Cubyz.app/Contents/Frameworks/libVkLayer_khronos_validation.dylib");
		const validationLayerJsonInstall = b.addInstallFile(subPath.path(b, "VkLayer_khronos_validation.json"), "bin/Cubyz.app/Contents/Resources/vulkan/explicit_layer.d/VkLayer_khronos_validation.json");
		exe.step.dependOn(&validationLayerLibInstall.step);
		exe.step.dependOn(&validationLayerJsonInstall.step);
	}

	if (t.os.tag == .windows) {
		exe.root_module.linkSystemLibrary("bcrypt", .{});
		exe.root_module.linkSystemLibrary("comdlg32", .{});
		exe.root_module.linkSystemLibrary("crypt32", .{});
		exe.root_module.linkSystemLibrary("gdi32", .{});
		exe.root_module.linkSystemLibrary("ole32", .{});
		exe.root_module.linkSystemLibrary("opengl32", .{});
		exe.root_module.linkSystemLibrary("ws2_32", .{});
	} else if (t.os.tag == .macos) {
		exe.root_module.linkFramework("Cocoa", .{});
		exe.root_module.linkFramework("CoreFoundation", .{});
		exe.root_module.linkFramework("IOKit", .{});
		exe.root_module.linkFramework("QuartzCore", .{});
	} else if (t.os.tag != .linux) {
		std.log.err("Unsupported target: {}\n", .{t.os.tag});
	}
}

const ModFeatures = struct {
	/// Modding framework recognizes certain files that will be automatically digested by the engine.
	/// This is the list of directory prefixes that are used to check if given file is one of those features.
	pub const knownFeatures: []const []const []const u8 = &.{
		&.{"callbacks", "block", "client"},
		&.{"callbacks", "block", "server"},
		&.{"callbacks", "block", "touch"},
		&.{"commands"},
		&.{"ecs", "client", "components"},
		&.{"ecs", "server", "componenets"},
		&.{"ecs", "storage"},
		&.{"ecs", "systems"},
		&.{"gui", "components"},
		&.{"gui", "windows"},
		&.{"items"},
		&.{"key_binds"},
		&.{"modifiers"},
		&.{"network", "protocols"},
		&.{"rotations"},
		&.{"sync", "atomics"},
		&.{"sync", "messages"},
		&.{"sync", "transactions"},
		&.{"terrain", "cave_biome_gen"},
		&.{"terrain", "cave_gen"},
		&.{"terrain", "chunk_gen"},
		&.{"terrain", "climate_gen"},
		&.{"terrain", "map_gen"},
		&.{"terrain", "sdf_models"},
		&.{"terrain", "simple_structures"},
		&.{"terrain", "structure_map_gen"},
	};

	fn addStep(b: *std.Build, exe: *std.Build.Step.Compile) !void {
		const step = try b.allocator.create(std.Build.Step);
		step.* = std.Build.Step.init(.{
			.id = .custom,
			.name = "Create Mods",
			.owner = b,
			.makeFn = generateModFeatureFiles,
		});
		exe.step.dependOn(step);

		const module = b.createModule(.{
			.root_source_file = b.path(b.fmt("mods/_mods.zig", .{})),
			.target = exe.root_module.resolved_target,
			.optimize = exe.root_module.optimize,
		});
		module.addImport("main", exe.root_module);
		module.addImport("mods", module);
		exe.root_module.addImport("mods", module);
	}
	/// Recursively iterate through all directories in the `mods` directory.
	/// For each create a file with same name as the directory which contains imports for all files in that directory.
	/// Each imported file is assigned to a public constant with same name as the file.
	pub fn generateModFeatureFiles(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
		var io = std.Io.Threaded.init(options.gpa, .{});
		defer io.deinit();

		var modDir = try std.Io.Dir.cwd().openDir(io.io(), "mods", .{.iterate = true});
		defer modDir.close(io.io());

		var path: std.ArrayListUnmanaged([]const u8) = .empty;
		defer path.deinit(step.owner.allocator);

		try recurseAndGenerateFiles(step, io.io(), &path, "mods", modDir);
	}

	/// Generate a meta file for given directory, recurse into subdirectories and repeat.
	/// `path` is an array used to track the traversed path as we go deeper into subdirectory structure, to allow generating feature IDs.
	/// `dir` and `name` refer to the directory which is currently being processed.
	fn recurseAndGenerateFiles(step: *std.Build.Step, io: std.Io, path: *std.ArrayListUnmanaged([]const u8), name: []const u8, dir: std.Io.Dir) !void {
		// We are doing a lot of string operations and its impractical to add deinit code for all of them, thus arena to batch dealloc everything.
		var localArena: std.heap.ArenaAllocator = .init(step.owner.allocator);
		defer localArena.deinit();
		const localAllocator = localArena.allocator();

		// Since we want import entries sorted, we can't immediately use u8 arrays.
		var importLines: std.ArrayListUnmanaged([]const u8) = .empty;
		var fileSymbols: std.ArrayListUnmanaged([]const u8) = .empty;
		var directorySymbols: std.ArrayListUnmanaged([]const u8) = .empty;

		var iterator = dir.iterate();
		while (try iterator.next(io)) |entry| {
			if (std.mem.startsWith(u8, entry.name, "_")) continue;

			switch (entry.kind) {
				.file => {
					if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
					const nameWithoutExtension = entry.name[0 .. entry.name.len - 4];

					try fileSymbols.append(localAllocator, try localAllocator.dupe(u8, nameWithoutExtension));
					try importLines.append(localAllocator, try std.fmt.allocPrint(localAllocator,
						\\pub const {s} = @import("{s}");
						\\
					, .{nameWithoutExtension, entry.name}));
				},
				.directory => {
					var subDir = try dir.openDir(io, entry.name, .{.iterate = true});
					defer subDir.close(io);

					try path.append(step.owner.allocator, entry.name);
					defer _ = path.pop();

					try recurseAndGenerateFiles(step, io, path, entry.name, subDir);

					try directorySymbols.append(localAllocator, try localAllocator.dupe(u8, entry.name));
					try importLines.append(localAllocator, try std.fmt.allocPrint(localAllocator,
						\\pub const {s} = @import("{s}/_{s}.zig");
						\\
					, .{entry.name, entry.name, entry.name}));
				},
				else => {},
			}
		}

		const strLessThanFn = struct {
			fn lessThanFn(_: void, lhs: []const u8, rhs: []const u8) bool {
				return std.mem.lessThan(u8, lhs, rhs);
			}
		}.lessThanFn;

		std.mem.sort([]const u8, importLines.items, {}, strLessThanFn);
		std.mem.sort([]const u8, fileSymbols.items, {}, strLessThanFn);
		std.mem.sort([]const u8, directorySymbols.items, {}, strLessThanFn);

		// This is the buffer for constructing content of generated file.
		var fileContent = try std.ArrayListUnmanaged(u8).initCapacity(localAllocator, importLines.items.len*48); // Imports take at least ~28 chars due to how template looks.
		fileContent.appendSlice(localAllocator, "// This file is automatically generated by build.zig. Do not edit manually.\n\n") catch {};
		for (importLines.items) |line| try fileContent.appendSlice(localAllocator, line);

		// Create _ModMeta struct with mod metadata that simplifies iteration and allows to reliably identify things to be recognized as mods and mod features.
		try fileContent.appendSlice(localAllocator,
			\\
			\\pub const _ModMeta = struct {
			\\
		);
		try fileContent.appendSlice(localAllocator, "\tpub const main = @import(\"main\");\n");

		const featurePrefix = matchKnownFeaturePrefix(path.items);
		const strippedPath = stripKnownFeaturePrefix(path.items, featurePrefix);
		{
			const nextLine = if (featurePrefix.len > 0) try std.mem.join(localAllocator, "/", featurePrefix) else "other";
			try fileContent.appendSlice(localAllocator, try std.fmt.allocPrint(localAllocator, "\tpub const feature: main.mods.Feature = .@\"{s}\";\n", .{nextLine}));
		}

		// Provide a fileIterator field.
		{
			const nextLine = try std.fmt.allocPrint(localAllocator, "\tpub const fileIterator: [{}]main.mods.ObjectDescriptor = .{{\n", .{fileSymbols.items.len});
			try fileContent.appendSlice(localAllocator, nextLine);
		}
		for (fileSymbols.items) |symbolName| {
			const mod = getModName(path.items, symbolName);
			const id = try makeFeatureId(localAllocator, mod, strippedPath, symbolName);
			const nextLine = try std.fmt.allocPrint(localAllocator, "\t\t.{{ .mod = \"{s}\", .id = \"{s}\", .object = {s} }},\n", .{mod, id, symbolName});
			try fileContent.appendSlice(localAllocator, nextLine);
		}
		try fileContent.appendSlice(localAllocator, "\t};\n");

		// Provide a directoryIterator field.
		{
			const nextLine = try std.fmt.allocPrint(localAllocator, "\tpub const directoryIterator: [{}]main.mods.ObjectDescriptor = .{{\n", .{directorySymbols.items.len});
			try fileContent.appendSlice(localAllocator, nextLine);
		}
		for (directorySymbols.items) |symbolName| {
			const mod = getModName(path.items, symbolName);
			const id = try makeFeatureId(localAllocator, mod, strippedPath, symbolName);
			const nextLine = try std.fmt.allocPrint(localAllocator, "\t\t.{{ .mod = \"{s}\", .id = \"{s}\", .object = {s} }},\n", .{mod, id, symbolName});
			try fileContent.appendSlice(localAllocator, nextLine);
		}
		try fileContent.appendSlice(localAllocator, "\t};\n");

		// Close ModMeata struct.
		try fileContent.appendSlice(localAllocator, "};\n");

		const file_path = try std.fmt.allocPrint(localAllocator, "_{s}.zig", .{name});
		const file = try dir.createFile(io, file_path, .{});
		defer file.close(io);

		try dir.writeFile(io, .{.data = fileContent.items, .sub_path = file_path});
	}

	fn getModName(path: []const []const u8, symbolName: []const u8) []const u8 {
		if (path.len >= 1) return path[0];
		return symbolName;
	}

	fn matchKnownFeaturePrefix(path: []const []const u8) []const []const u8 {
		if (path.len <= 1) return &.{};

		const skipMod = path[1..];
		// Some features may have partially overlapping prefixes.
		var longestFeaturePrefix: []const []const u8 = &.{};

		for (knownFeatures) |known| failed: {
			if (known.len > skipMod.len) continue;

			for (0..known.len) |i| {
				if (std.mem.eql(u8, known[i], skipMod[i])) continue;
				break :failed;
			}

			if (known.len > longestFeaturePrefix.len) longestFeaturePrefix = known;
		}

		return longestFeaturePrefix;
	}

	fn stripKnownFeaturePrefix(path: []const []const u8, prefix: []const []const u8) []const []const u8 {
		if (prefix.len == 0) {
			if (path.len < 1) return &.{};
			return path[1..];
		}
		if (path.len < 1 + prefix.len) return &.{};
		return path[1 + prefix.len ..];
	}

	/// Construct a feature ID string.
	/// This function is well defined for files, for directories produces stable, but less meaningful results which are not used anywhere in the engine.
	/// `path` has to be stripped of mod name and known feature prefix for the ID to be correct.
	/// `suffix` is the name of the file without extension.
	fn makeFeatureId(allocator: std.mem.Allocator, mod: []const u8, path: []const []const u8, suffix: []const u8) ![]const u8 {
		var totalLen = mod.len + 1 + suffix.len;
		for (path) |segment| totalLen += segment.len + 1;

		var buffer = try std.ArrayListUnmanaged(u8).initCapacity(allocator, totalLen);
		buffer.appendSliceAssumeCapacity(mod);
		buffer.appendSliceAssumeCapacity(":");
		for (path) |segment| {
			buffer.appendSliceAssumeCapacity(segment);
			buffer.appendSliceAssumeCapacity("/");
		}
		buffer.appendSliceAssumeCapacity(suffix);

		return buffer.items;
	}
};

fn createLaunchConfig(b: *std.Build) !void {
	var io = std.Io.Threaded.init(b.allocator, .{});
	defer io.deinit();
	std.Io.Dir.cwd().access(io.io(), "launchConfig.zon", .{}) catch {
		const launchConfig =
			\\.{
			\\    .cubyzDir = "",
			\\    .autoEnterWorld = "",
			\\    .headlessServer = false,
			\\    // .preferredAuthenticationAlgorithm = .ed25519, // Uncomment and change this if you own a server in an outdated game version where the default algorithm got compromised.
			\\}
		;
		try std.Io.Dir.cwd().writeFile(io.io(), .{
			.data = launchConfig,
			.sub_path = "launchConfig.zon",
		});
	};
}

pub fn build(b: *std.Build) !void {
	try createLaunchConfig(b);

	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});

	// Standard release options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
	const optimize = b.standardOptimizeOption(.{});

	const options = b.addOptions();
	const isRelease = b.option(bool, "release", "Removes the -dev flag from the version") orelse false;
	const sanitizeThread = b.option(bool, "sanitizeThread", "enables the builtin thread sanitizer");
	const version = b.fmt("0.4.0{s}", .{if (isRelease) "" else "-dev"});
	if (b.option([]const u8, "version", "used by the CI to check if the git tag and game version match")) |tagVersion| {
		const tagVersionUpperbound: usize = std.mem.indexOfScalar(u8, tagVersion, '-') orelse tagVersion.len;
		const versionUpperbound: usize = std.mem.indexOfScalar(u8, version, '-') orelse version.len;
		const tagParsed = try std.SemanticVersion.parse(tagVersion[0..tagVersionUpperbound]);
		const versionParsed = try std.SemanticVersion.parse(version[0..versionUpperbound]);
		if (std.SemanticVersion.order(tagParsed, versionParsed) != .eq) {
			std.log.err("Provided version {s} does not match version in build.zig: {s}", .{tagVersion, version});
			return error.VersionMismatch;
		}
	}
	options.addOption([]const u8, "version", version);
	options.addOption(bool, "isTaggedRelease", isRelease);

	const useLocalDeps = b.option(bool, "local", "Use local cubyz_deps") orelse false;

	const largeAssets = b.dependency("cubyz_large_assets", .{});
	b.installDirectory(.{
		.source_dir = largeAssets.path("music"),
		.install_subdir = "assets/cubyz/music/",
		.install_dir = .{.custom = ".."},
	});
	b.installDirectory(.{
		.source_dir = largeAssets.path("fonts"),
		.install_subdir = "assets/cubyz/fonts/",
		.install_dir = .{.custom = ".."},
	});

	const mainModule = b.addModule("main", .{
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
		.link_libc = true,
		.link_libcpp = true,
		.sanitize_thread = sanitizeThread,
	});

	const exe = b.addExecutable(.{
		.name = "Cubyz",
		.root_module = mainModule,
		.use_llvm = if (sanitizeThread orelse false) true else null,
	});
	exe.root_module.addOptions("build_options", options);
	exe.root_module.addImport("main", mainModule);
	try ModFeatures.addStep(b, exe);

	if (isRelease and target.result.os.tag == .windows) {
		exe.subsystem = .windows;
	}

	linkLibraries(b, exe, useLocalDeps);

	var exeInstallOptions: std.Build.Step.InstallArtifact.Options = .{};
	if (target.result.os.tag == .macos) {
		exeInstallOptions = .{
			.dest_dir = .{.override = .{.custom = "bin/Cubyz.app/Contents/MacOS"}},
		};

		const plistContents =
			\\<?xml version="1.0" encoding="UTF-8"?>
			\\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
			\\<plist version="1.0">
			\\<dict>
			\\    <key>CFBundleIconFile</key>
			\\    <string>logo</string>
			\\</dict>
			\\</plist>
		;

		const writeFiles = b.addWriteFiles();
		const plistPath = writeFiles.add("Info.plist", plistContents);
		const plistInstall = b.addInstallFile(plistPath, "bin/Cubyz.app/Contents/Info.plist");
		b.getInstallStep().dependOn(&plistInstall.step);
		const iconsInstall = b.addInstallFile(b.path("assets/cubyz/logo.icns"), "bin/Cubyz.app/Contents/Resources/logo.icns");
		b.getInstallStep().dependOn(&iconsInstall.step);

		// NOTE(blackedout): This is to make the Vulkan loader search in (bundle)/Contents/Frameworks to find the libs referenced in the manifest files
		exe.root_module.addRPathSpecial("@loader_path/../Frameworks");
	}

	const installExe = b.addInstallArtifact(exe, exeInstallOptions);
	b.getInstallStep().dependOn(&installExe.step);

	const run_cmd = b.addRunArtifact(exe);
	run_cmd.step.dependOn(b.getInstallStep());
	if (b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);

	const dependencyWithTestRunner = b.lazyDependency("cubyz_test_runner", .{
		.target = target,
		.optimize = optimize,
	}) orelse {
		std.log.info("Downloading cubyz_test_runner dependency.", .{});
		return;
	};
	const exe_tests = b.addTest(.{
		.root_module = mainModule,
		.test_runner = .{.path = dependencyWithTestRunner.path("lib/compiler/test_runner.zig"), .mode = .simple},
	});
	linkLibraries(b, exe_tests, useLocalDeps);
	exe_tests.root_module.addOptions("build_options", options);
	exe_tests.root_module.addImport("main", mainModule);
	try ModFeatures.addStep(b, exe_tests);
	const run_exe_tests = b.addRunArtifact(exe_tests);

	const test_step = b.step("test", "Run unit tests");
	test_step.dependOn(&run_exe_tests.step);
}
