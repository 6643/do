const std = @import("std");
const async_lowering = @import("async_lowering.zig");
const model = @import("model.zig");
const signature = @import("signature.zig");

pub const ModuleArtifact = struct {
    path: []const u8,
    sha256: [std.crypto.hash.sha2.Sha256.digest_length]u8,
};

pub fn render(
    allocator: std.mem.Allocator,
    binding: model.BindingModel,
    module_path: []const u8,
) ![]u8 {
    const module_paths = [_][]const u8{module_path};
    return render_modules(allocator, binding, &module_paths);
}

pub fn render_modules(
    allocator: std.mem.Allocator,
    binding: model.BindingModel,
    module_paths: []const []const u8,
) ![]u8 {
    return render_modules_with_hashes(allocator, binding, module_paths, &.{});
}

pub fn render_modules_with_hashes(
    allocator: std.mem.Allocator,
    binding: model.BindingModel,
    module_paths: []const []const u8,
    module_hashes: []const ModuleArtifact,
) ![]u8 {
    const lowerings = try async_lowering.detect(allocator, binding);
    defer async_lowering.deinit(allocator, lowerings);

    var out = std.ArrayList(u8).empty;
    if (lowerings.len == 0) {
        try out.appendSlice(allocator, "{\"schema\":1,\"package\":\"");
    } else {
        try out.appendSlice(allocator, "{\"schema\":2,\"package\":\"");
    }
    try append_package_locator(&out, allocator, binding.package);
    try out.appendSlice(allocator, "\",\"world\":\"");
    try append_json_text(&out, allocator, binding.world.name);
    try out.appendSlice(allocator, "\",\"modules\":[");
    for (module_paths, 0..) |module_path, index| {
        if (index != 0) try out.append(allocator, ',');
        try out.append(allocator, '"');
        try append_json_text(&out, allocator, module_path);
        try out.append(allocator, '"');
    }
    if (module_hashes.len != 0) {
        try out.appendSlice(allocator, "],\"module_hashes\":[");
        for (module_hashes, 0..) |module_hash, index| {
            if (index != 0) try out.append(allocator, ',');
            try out.appendSlice(allocator, "{\"path\":\"");
            try append_json_text(&out, allocator, module_hash.path);
            try out.appendSlice(allocator, "\",\"sha256\":\"");
            try append_hash(&out, allocator, module_hash.sha256);
            try out.appendSlice(allocator, "\"}");
        }
        try out.appendSlice(allocator, "],\"sha256\":\"");
    } else {
        try out.appendSlice(allocator, "],\"sha256\":\"");
    }
    try append_hash(&out, allocator, binding.content_hash);
    try out.appendSlice(allocator, "\",\"members\":[");

    var first = true;
    for (binding.interfaces) |interface| {
        for (interface.functions) |function| {
            if (!first) try out.append(allocator, ',');
            first = false;
            try out.appendSlice(allocator, "{\"package\":\"");
            try append_package_locator(&out, allocator, interface.package orelse binding.package);
            try out.appendSlice(allocator, "\",\"member\":\"");
            try append_json_text(&out, allocator, interface.name);
            try out.append(allocator, '.');
            try append_json_text(&out, allocator, function.name);
            try out.appendSlice(allocator, "\",\"effect\":\"");
            try out.appendSlice(allocator, if (function.effects.is_async) "async" else "sync");
            try out.appendSlice(allocator, "\",\"async\":");
            try out.appendSlice(allocator, if (function.effects.is_async) "true" else "false");
            try out.appendSlice(allocator, ",\"future\":");
            try out.appendSlice(allocator, if (function.effects.has_future) "true" else "false");
            try out.appendSlice(allocator, ",\"stream\":");
            try out.appendSlice(allocator, if (function.effects.has_stream) "true" else "false");
            try out.appendSlice(allocator, ",\"resource\":");
            try out.appendSlice(allocator, if (function.effects.has_resource) "true" else "false");
            try out.appendSlice(allocator, ",\"signature\":\"");
            const function_signature = try signature.render(allocator, interface.name, function);
            defer allocator.free(function_signature);
            try append_json_text(&out, allocator, function_signature);
            try out.append(allocator, '"');
            try out.append(allocator, '}');
        }
    }
    if (lowerings.len != 0) {
        try out.appendSlice(allocator, "],\"async_lowerings\":[");
        for (lowerings, 0..) |lowering, index| {
            if (index != 0) try out.append(allocator, ',');
            try append_lowering(&out, allocator, lowering);
        }
        try out.append(allocator, ']');
    } else {
        try out.append(allocator, ']');
    }
    try out.append(allocator, '}');
    return out.toOwnedSlice(allocator);
}

fn append_lowering(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    lowering: async_lowering.Capability,
) !void {
    try out.appendSlice(allocator, "{\"capability\":\"");
    try append_json_text(out, allocator, lowering.capability);
    try out.appendSlice(allocator, "\",\"member\":\"");
    try append_json_text(out, allocator, lowering.member);
    try out.appendSlice(allocator, "\",\"source_signature\":\"");
    try append_json_text(out, allocator, lowering.source_signature);
    try out.appendSlice(allocator, "\",\"wit_package\":\"");
    try append_json_text(out, allocator, lowering.wit_package);
    try out.appendSlice(allocator, "\",\"wit_world\":\"");
    try append_json_text(out, allocator, lowering.wit_world);
    try out.appendSlice(allocator, "\",\"wit_interface\":\"");
    try append_json_text(out, allocator, lowering.wit_interface);
    try out.appendSlice(allocator, "\",\"wit_member\":\"");
    try append_json_text(out, allocator, lowering.wit_member);
    try out.appendSlice(allocator, "\",\"async_import_module\":\"");
    try append_json_text(out, allocator, lowering.async_import_module);
    try out.appendSlice(allocator, "\",\"async_import_name\":\"");
    try append_json_text(out, allocator, lowering.async_import_name);
    try out.appendSlice(allocator, "\",\"completion\":\"");
    try append_json_text(out, allocator, lowering.completion);
    try out.appendSlice(allocator, "\",\"wit_sha256\":\"");
    try append_hash(out, allocator, lowering.wit_sha256);
    try out.appendSlice(allocator, "\"}");
}

fn append_package_locator(out: *std.ArrayList(u8), allocator: std.mem.Allocator, package: model.PackageDecl) !void {
    try append_json_text(out, allocator, package.namespace);
    try out.append(allocator, ':');
    try append_json_text(out, allocator, package.name);
    try out.append(allocator, '@');
    try append_fmt(out, allocator, "{d}.{d}.{d}", .{ package.version.major, package.version.minor, package.version.patch });
    if (package.version.prerelease.len != 0) {
        try out.append(allocator, '-');
        try append_json_text(out, allocator, package.version.prerelease);
    }
}

fn append_hash(out: *std.ArrayList(u8), allocator: std.mem.Allocator, hash: [32]u8) !void {
    for (hash) |byte| {
        try append_hex_byte(out, allocator, byte);
    }
}

fn append_hex_byte(out: *std.ArrayList(u8), allocator: std.mem.Allocator, byte: u8) !void {
    const digits = "0123456789abcdef";
    try out.append(allocator, digits[byte >> 4]);
    try out.append(allocator, digits[byte & 0x0f]);
}

fn append_json_text(out: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    for (text) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, ch),
        }
    }
}

fn append_fmt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}
