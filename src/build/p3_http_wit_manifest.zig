const std = @import("std");

pub const source_commit = "7c678c4c10238a4bf4db91a0e27023d680ff65fe";
pub const source_path = "src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16";
pub const worlds_sha256 = "4f4bcdd89c8fd3de2fd171d600255b1b4d8157c4c142e8eb4d2e0270f5510670";
pub const types_sha256 = "37477eca8b4a2cdc158e09ca3ddc33b8dfceb752b09e44e4f6e8842e6f6d2a38";
pub const deps_toml_sha256 = "015d83a96632832298592bd70a7018802b04d39b34e11ed43e7428837b9fa25b";
pub const deps_lock_sha256 = "49de23a7d70a6744d7505b4c59d0a6aa99f979fea651ef9a93224c78f88d6862";

pub const HttpResourceOperation = struct {
    name: []const u8,
    receiver: ?[]const u8,
    params: []const []const u8,
    result: []const u8,
    moves_receiver: bool,
    canonical_module: []const u8 = "",
    canonical_name: []const u8 = "",
    core_params: []const []const u8 = &.{},
    core_results: []const []const u8 = &.{},
    receiver_ownership: []const u8 = "none",
};

pub const HttpResourceGraph = struct {
    pub const fields_path = "http/types/fields";
    pub const headers_path = fields_path;
    pub const request_options_path = "http/types/request-options";
    pub const request_path = "http/types/request";
    pub const response_path = "http/types/response";

    const request_new_params = [_][]const u8{
        "headers",
        "option<stream<u8>>",
        "future<result<option<trailers>, error-code>>",
        "option<request-options>",
    };
    const consume_body_params = [_][]const u8{
        "resource",
        "future<result<_, error-code>>",
    };
    const request_new_core_params = [_][]const u8{
        "i32",
        "i32",
        "i32",
        "i32",
        "i32",
        "i32",
        "i32",
    };

    pub const request_new = HttpResourceOperation{
        .name = "new",
        .receiver = null,
        .params = &request_new_params,
        .result = "tuple<request,future<result<_,error-code>>>",
        .moves_receiver = false,
        .canonical_module = "wasi:http/types@0.3.0-rc-2025-09-16",
        .canonical_name = "[static]request.new",
        .core_params = &request_new_core_params,
        .core_results = &.{},
    };
    pub const request_consume_body = HttpResourceOperation{
        .name = "consume-body",
        .receiver = "request",
        .params = &consume_body_params,
        .result = "tuple<stream<u8>,future<result<option<trailers>,error-code>>>",
        .moves_receiver = true,
    };
    pub const response_consume_body = HttpResourceOperation{
        .name = "consume-body",
        .receiver = "response",
        .params = &consume_body_params,
        .result = "tuple<stream<u8>,future<result<option<trailers>,error-code>>>",
        .moves_receiver = true,
    };
    pub const response_get_status_code = HttpResourceOperation{
        .name = "get-status-code",
        .receiver = "response",
        .params = &.{},
        .result = "status-code",
        .moves_receiver = false,
        .canonical_module = "wasi:http/types@0.3.0-rc-2025-09-16",
        .canonical_name = "[method]response.get-status-code",
        .core_params = &.{"i32"},
        .core_results = &.{"i32"},
        .receiver_ownership = "borrow",
    };
};

const PackageFile = struct {
    path: []const u8,
    data: []const u8,
};

const package_files = [_]PackageFile{
    .{ .path = "worlds.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/worlds.wit") },
    .{ .path = "types.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/types.wit") },
    .{ .path = "deps.toml", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps.toml") },
    .{ .path = "deps.lock", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps.lock") },
    .{ .path = "deps/cli/command.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/cli/command.wit") },
    .{ .path = "deps/cli/environment.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/cli/environment.wit") },
    .{ .path = "deps/cli/exit.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/cli/exit.wit") },
    .{ .path = "deps/cli/imports.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/cli/imports.wit") },
    .{ .path = "deps/cli/run.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/cli/run.wit") },
    .{ .path = "deps/cli/stdio.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/cli/stdio.wit") },
    .{ .path = "deps/cli/terminal.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/cli/terminal.wit") },
    .{ .path = "deps/clocks/monotonic-clock.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/clocks/monotonic-clock.wit") },
    .{ .path = "deps/clocks/timezone.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/clocks/timezone.wit") },
    .{ .path = "deps/clocks/types.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/clocks/types.wit") },
    .{ .path = "deps/clocks/wall-clock.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/clocks/wall-clock.wit") },
    .{ .path = "deps/clocks/world.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/clocks/world.wit") },
    .{ .path = "deps/filesystem/preopens.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/preopens.wit") },
    .{ .path = "deps/filesystem/types.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit") },
    .{ .path = "deps/filesystem/world.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/world.wit") },
    .{ .path = "deps/random/insecure-seed.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/random/insecure-seed.wit") },
    .{ .path = "deps/random/insecure.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/random/insecure.wit") },
    .{ .path = "deps/random/random.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/random/random.wit") },
    .{ .path = "deps/random/world.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/random/world.wit") },
    .{ .path = "deps/sockets/ip-name-lookup.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/sockets/ip-name-lookup.wit") },
    .{ .path = "deps/sockets/types.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/sockets/types.wit") },
    .{ .path = "deps/sockets/world.wit", .data = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/sockets/world.wit") },
};

pub fn write_package(dir: std.Io.Dir, io: std.Io) !void {
    for (package_files) |file| {
        if (std.fs.path.dirname(file.path)) |parent| try dir.createDirPath(io, parent);
        if (std.mem.eql(u8, file.path, "types.wit")) {
            const allocator = std.heap.page_allocator;
            const types = try append_async_payload_alias(allocator, file.data);
            defer allocator.free(types);
            try dir.writeFile(io, .{ .sub_path = file.path, .data = types });
        } else {
            try dir.writeFile(io, .{ .sub_path = file.path, .data = file.data });
        }
    }
}

fn append_async_payload_alias(allocator: std.mem.Allocator, types: []const u8) ![]u8 {
    const close = std.mem.lastIndexOf(u8, types, "\n}\n") orelse return error.InvalidPinnedHttpResourceGraph;
    const alias =
        "\n  /// Internal payload alias used only to resolve async intrinsic payload types.\n" ++
        "  consume-body-payload: func(\n" ++
        "    this: response,\n" ++
        "    res: future<result<_, error-code>>,\n" ++
        "  ) -> tuple<stream<u8>, future<result<option<trailers>, error-code>>>;\n" ++
        "  request-new-payload: func(\n" ++
        "    headers: headers,\n" ++
        "    contents: option<stream<u8>>,\n" ++
        "    trailers: future<result<option<trailers>, error-code>>,\n" ++
        "    options: option<request-options>,\n" ++
        "  ) -> tuple<request, future<result<_, error-code>>>;\n";

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, types[0..close]);
    try out.appendSlice(allocator, alias);
    try out.appendSlice(allocator, types[close..]);
    return out.toOwnedSlice(allocator);
}

pub fn validate() !void {
    try verify_sha256(@embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/worlds.wit"), worlds_sha256);
    try verify_sha256(@embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/types.wit"), types_sha256);
    try verify_sha256(@embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps.toml"), deps_toml_sha256);
    try verify_sha256(@embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps.lock"), deps_lock_sha256);
}

pub fn validate_resource_graph() !void {
    try validate();

    const types = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/types.wit");
    const worlds = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/worlds.wit");
    const required_types = [_][]const u8{
        "resource fields {",
        "resource request {",
        "resource request-options {",
        "resource response {",
        "new: static func(",
        "headers: headers,",
        "contents: option<stream<u8>>",
        "trailers: future<result<option<trailers>, error-code>>",
        "options: option<request-options>",
        "consume-body: static func(this: request",
        "consume-body: static func(this: response",
        "get-status-code: func() -> status-code",
    };
    for (required_types) |needle| {
        if (std.mem.indexOf(u8, types, needle) == null) return error.InvalidPinnedHttpResourceGraph;
    }

    const required_worlds = [_][]const u8{
        "interface client {",
        "send: async func(",
        "request: request,",
        ") -> result<response, error-code>;",
    };
    for (required_worlds) |needle| {
        if (std.mem.indexOf(u8, worlds, needle) == null) return error.InvalidPinnedHttpResourceGraph;
    }
}

fn verify_sha256(bytes: []const u8, expected: []const u8) !void {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});

    var actual: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 = undefined;
    for (digest, 0..) |byte, index| {
        actual[index * 2] = hex_digit(byte >> 4);
        actual[index * 2 + 1] = hex_digit(byte & 0x0f);
    }
    if (!std.mem.eql(u8, &actual, expected)) return error.InvalidPinnedHttpWit;
}

fn hex_digit(value: u8) u8 {
    return if (value < 10) '0' + value else 'a' + (value - 10);
}

test "HTTP WIT package writer preserves the pinned service package" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try write_package(tmp.dir, std.testing.io);
    const worlds = try tmp.dir.readFileAlloc(std.testing.io, "worlds.wit", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(worlds);
    const client = try tmp.dir.readFileAlloc(std.testing.io, "deps/cli/stdio.wit", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(client);
    const types = try tmp.dir.readFileAlloc(std.testing.io, "types.wit", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(types);

    try std.testing.expect(std.mem.indexOf(u8, worlds, "world service") != null);
    try std.testing.expect(std.mem.indexOf(u8, worlds, "import client") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "interface stdout") != null);
    try std.testing.expect(std.mem.indexOf(u8, types, "consume-body-payload: func(") != null);
    try std.testing.expect(std.mem.indexOf(u8, types, "request-new-payload: func(") != null);
}

test "pinned HTTP resource graph preserves request and response construction facts" {
    try validate_resource_graph();
    try std.testing.expectEqualStrings("http/types/fields", HttpResourceGraph.headers_path);
    try std.testing.expectEqualStrings("http/types/request-options", HttpResourceGraph.request_options_path);
    try std.testing.expectEqualStrings("http/types/request", HttpResourceGraph.request_path);
    try std.testing.expectEqualStrings("http/types/response", HttpResourceGraph.response_path);
}

test "HTTP operation facts preserve resource moves and stream results" {
    const request_new = HttpResourceGraph.request_new;
    try std.testing.expectEqualStrings("new", request_new.name);
    try std.testing.expect(request_new.receiver == null);
    try std.testing.expect(!request_new.moves_receiver);
    try std.testing.expectEqual(@as(usize, 4), request_new.params.len);
    try std.testing.expectEqualStrings("headers", request_new.params[0]);
    try std.testing.expectEqualStrings("option<stream<u8>>", request_new.params[1]);
    try std.testing.expectEqualStrings("future<result<option<trailers>, error-code>>", request_new.params[2]);
    try std.testing.expectEqualStrings("option<request-options>", request_new.params[3]);
    try std.testing.expectEqualStrings("tuple<request,future<result<_,error-code>>>", request_new.result);

    const request_body = HttpResourceGraph.request_consume_body;
    try std.testing.expectEqualStrings("request", request_body.receiver.?);
    try std.testing.expect(request_body.moves_receiver);
    try std.testing.expectEqualStrings("tuple<stream<u8>,future<result<option<trailers>,error-code>>>", request_body.result);

    const response_body = HttpResourceGraph.response_consume_body;
    try std.testing.expectEqualStrings("response", response_body.receiver.?);
    try std.testing.expect(response_body.moves_receiver);
    try std.testing.expectEqualStrings(request_body.result, response_body.result);
}

test "pinned request.new carries its canonical constructor ABI" {
    const operation = HttpResourceGraph.request_new;
    try std.testing.expectEqualStrings("wasi:http/types@0.3.0-rc-2025-09-16", operation.canonical_module);
    try std.testing.expectEqualStrings("[static]request.new", operation.canonical_name);
    try std.testing.expectEqual(@as(usize, 7), operation.core_params.len);
    for (operation.core_params) |param| try std.testing.expectEqualStrings("i32", param);
    try std.testing.expectEqual(@as(usize, 0), operation.core_results.len);
}

test "HTTP response status operation preserves a borrowed receiver ABI" {
    const operation = HttpResourceGraph.response_get_status_code;
    try std.testing.expectEqualStrings("get-status-code", operation.name);
    try std.testing.expectEqualStrings("response", operation.receiver.?);
    try std.testing.expect(!operation.moves_receiver);
    try std.testing.expectEqualStrings("status-code", operation.result);
    try std.testing.expectEqualStrings("wasi:http/types@0.3.0-rc-2025-09-16", operation.canonical_module);
    try std.testing.expectEqualStrings("[method]response.get-status-code", operation.canonical_name);
    try std.testing.expectEqual(@as(usize, 1), operation.core_params.len);
    try std.testing.expectEqualStrings("i32", operation.core_params[0]);
    try std.testing.expectEqual(@as(usize, 1), operation.core_results.len);
    try std.testing.expectEqualStrings("i32", operation.core_results[0]);
    try std.testing.expectEqualStrings("borrow", operation.receiver_ownership);
}
