const std = @import("std");

const mods = @import("mods");
const features = @import("features.zig");

pub const Feature = features.Feature;

const featureTables: [@typeInfo(Feature).@"enum".fields.len]std.StaticStringMap(ObjectDescriptor) = getFeatureTables: {
	@setEvalBranchQuota(1_000_000);
	const featureCount = @typeInfo(Feature).@"enum".fields.len;

	const countFeatures = struct {
		fn countEntries(comptime this: type) [featureCount]usize {
			if (!@hasDecl(this, "_ModMeta")) return;

			var entryCount: [featureCount]usize = @splat(0);
			entryCount[@intFromEnum(this._ModMeta.feature)] += this._ModMeta.files.len;

			inline for (this._ModMeta.directories) |descriptor| {
				const result = countEntries(descriptor.object);
				inline for (0..featureCount) |i| entryCount[i] += result[i];
			}
			return entryCount;
		}
	}.countEntries;

	const Entry = struct { []const u8, ObjectDescriptor };

	const expectedEntryCount: [featureCount]usize = countFeatures(mods);
	const featureTableFieldTypes: [featureCount]type = blk: {
		var types: [featureCount]type = undefined;
		for (0..featureCount) |i| types[i] = [expectedEntryCount[i]]Entry;
		break :blk types;
	};

	const Collector = struct {
		const FeatureTable = @Struct(.auto, null, std.meta.fieldNames(Feature), &featureTableFieldTypes, &@splat(.{}));

		fn collect() FeatureTable {
			return comptime blk: {
				var index: [featureCount]usize = @splat(0);
				var entries: FeatureTable = undefined;

				_collect(mods, &index, &entries);
				break :blk entries;
			};
		}
		fn _collect(comptime this: type, index: *[featureCount]usize, entries: *FeatureTable) void {
			if (!@hasDecl(this, "_ModMeta")) return;

			inline for (this._ModMeta.files) |descriptor| {
				const feature = this._ModMeta.feature;
				@field(entries, @tagName(feature))[index[@intFromEnum(feature)]] = .{descriptor.id, descriptor};
				index[@intFromEnum(feature)] += 1;
			}
			inline for (this._ModMeta.directories) |descriptor| {
				_collect(descriptor.object, index, entries);
			}
		}
	};

	const entries: Collector.FeatureTable = Collector.collect();

	var tmpFeatureTables: [featureCount]std.StaticStringMap(ObjectDescriptor) = undefined;

	for (@typeInfo(Feature).@"enum".fields) |field| {
		tmpFeatureTables[@intFromEnum(@field(Feature, field.name))] = .initComptime(@field(entries, field.name));
	}
	break :getFeatureTables tmpFeatureTables;
};

pub const ObjectDescriptor = struct {
	mod: []const u8,
	id: []const u8,
	object: type,
};

const Mod = struct {
	init: fn (mod: Mod) void,
	register: fn (mod: Mod) void,
	deinit: fn (mod: Mod) void,
};

pub fn init() void {
	for (@typeInfo(mods).@"struct".decls) |decl| {
		@field(mods, decl.name).init(@field(mods, decl.name));
	}
}

inline fn walkThisContext(
	comptime this: type,
	filter: fn (modMeta: type) bool,
	comptime Context: type,
	context: Context,
	callback: fn (context: Context, feature: ObjectDescriptor) void,
) void {
	if (!@hasDecl(this, "_ModMeta")) return;

	if (comptime filter(this._ModMeta)) {
		inline for (this._ModMeta.files) |descriptor| {
			callback(context, descriptor);
		}
	}
	inline for (this._ModMeta.directories) |descriptor| {
		walkThisContext(descriptor.object, filter, Context, context, callback);
	}
}

fn FeatureTypeFilter(comptime feature: Feature) fn (modMeta: type) bool {
	return struct {
		fn filter(descriptor: type) bool {
			return descriptor.feature == feature;
		}
	}.filter;
}

pub inline fn walkFeatureContext(
	comptime feature: Feature,
	comptime Context: type,
	context: Context,
	callback: fn (context: Context, descriptor: ObjectDescriptor) void,
) void {
	const table = featureTables[@intFromEnum(feature)];
	const values = comptime table.kvs.values[0..table.kvs.len];
	inline for (values) |value| {
		callback(context, value);
	}
}

pub fn getFeatures(feature: Feature) []const ObjectDescriptor {
	return featureTables[@intFromEnum(feature)].values();
}

pub fn getFeatureCount(feature: Feature) usize {
	return featureTables[@intFromEnum(feature)].kvs.len;
}

pub fn getFeature(feature: Feature, id: []const u8) ObjectDescriptor {
	return featureTables[@intFromEnum(feature)].get(id);
}
