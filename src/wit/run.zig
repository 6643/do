const std = @import("std");
const cli = @import("cli.zig");
const emit_do = @import("emit_do.zig");
const manifest = @import("manifest.zig");
const model = @import("model.zig");
const resolve = @import("resolve.zig");

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const parsed = cli.parse(if (args.len > 0) args[1..] else args) catch |err| {
        try print_error(init.io, err);
        std.process.exit(1);
    };
    if (parsed.action == .help) {
        try print_usage(init.io);
        return;
    }

    var binding = resolve.resolve_input(init.io, init.gpa, parsed.input_path.?, parsed.world) catch |err| {
        try print_error(init.io, err);
        std.process.exit(1);
    };
    defer binding.deinit();

    if (parsed.manifest_path) |manifest_path| {
        const manifest_source = std.Io.Dir.cwd().readFileAlloc(init.io, manifest_path, init.gpa, .limited(16 * 1024 * 1024)) catch |err| {
            try print_error(init.io, err);
            std.process.exit(1);
        };
        defer init.gpa.free(manifest_source);
        var parsed_manifest = manifest.parse(init.gpa, manifest_source) catch |err| {
            try print_error(init.io, err);
            std.process.exit(1);
        };
        defer parsed_manifest.deinit(init.gpa);
        manifest.validate_binding(init.gpa, &parsed_manifest, binding) catch |err| {
            try print_error(init.io, err);
            std.process.exit(1);
        };
        manifest.validate_generated_modules(init.io, init.gpa, &parsed_manifest, manifest_path) catch |err| {
            try print_error(init.io, err);
            std.process.exit(1);
        };
    }

    if (parsed.action == .check) {
        try print_check_result(init.io, binding);
        return;
    }

    emit_do.emit_all(init.io, init.gpa, binding, parsed.output_path.?) catch |err| {
        try print_error(init.io, err);
        std.process.exit(1);
    };
    try print_bind_result(init.io, parsed.output_path.?);
}

fn print_usage(io: std.Io) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.print(
        \\do wit
        \\usage:
        \\  do wit check <wit-input> [--world <world>] [--manifest <manifest.json>]
        \\  do wit bind <wit-input> --world <world> --out <directory>
        \\
    , .{});
    try writer.interface.flush();
}

fn print_error(io: std.Io, err: anyerror) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    try writer.interface.print("error[{s}]: do wit command failed\n", .{@errorName(err)});
    try writer.interface.flush();
}

fn print_check_result(io: std.Io, binding: model.BindingModel) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.print("ok: {s}:{s} world={s} sha256=", .{ binding.package.namespace, binding.package.name, binding.world.name });
    try write_hash(&writer.interface, binding.content_hash);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();
}

fn print_bind_result(io: std.Io, output_path: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.print("generated: {s}\n", .{output_path});
    try writer.interface.flush();
}

fn write_hash(writer: *std.Io.Writer, hash: [32]u8) !void {
    const digits = "0123456789abcdef";
    for (hash) |byte| {
        try writer.writeByte(digits[byte >> 4]);
        try writer.writeByte(digits[byte & 0x0f]);
    }
}
