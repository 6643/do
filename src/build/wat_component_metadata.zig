const std = @import("std");

pub const WasiLowering = struct {
    module: []const u8,
    name: []const u8,
    param: ?[]const u8 = null,
    result: ?[]const u8 = null,
    result_record: ?[]const u8 = null,
    result_storage_elem: ?[]const u8 = null,
    result_unit_error: bool = false,
    result_link_at_error: bool = false,
    result_filesize_error: bool = false,
    result_descriptor_error: bool = false,
    result_u64_stream_error: bool = false,
    result_read_error: bool = false,
    result_list_u8_error: bool = false,
    /// list<tuple<descriptor,string>> → do [Tuple<Dir, text>] (G6.1 / P3 Dir shell pack).
    result_list_preopen: bool = false,
    resource_drop: bool = false,
};

pub fn emitWasiBindings(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wasi_imports: anytype,
) !void {
    for (wasi_imports) |import| {
        try appendFmt(allocator, out, "  ;; wasi-bind source=\"{s}\" alias=\"{s}\" target=\"{s}\" params=\"", .{
            import.source,
            import.alias,
            import.target,
        });
        try appendDoSignatureAsWit(allocator, out, import.params);
        try out.appendSlice(allocator, "\" result=\"");
        try appendDoSignatureAsWit(allocator, out, import.result);
        try out.appendSlice(allocator, "\"\n");
    }
}

pub fn emitWasiCoreImports(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wasi_imports: anytype,
) !void {
    var seen = std.ArrayList([]const u8).empty;
    defer seen.deinit(allocator);

    for (wasi_imports) |import| {
        const lowering = wasiLowering(import) orelse continue;
        if (hasString(seen.items, import.target)) continue;
        try seen.append(allocator, import.target);

        try appendFmt(allocator, out, "  (import \"{s}\" \"{s}\" (func $", .{
            lowering.module,
            lowering.name,
        });
        try appendWasiImportSymbol(allocator, out, import.target);
        if (lowering.param != null) {
            try appendFmt(allocator, out, " (param {s})", .{lowering.param.?});
        }
        if (lowering.result != null) {
            try appendFmt(allocator, out, " (result {s})", .{lowering.result.?});
        }
        try out.appendSlice(allocator, "))\n");
    }
}

pub fn emitHostImports(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    host_imports: anytype,
) !void {
    for (host_imports) |host_import| {
        try appendFmt(allocator, out, "  (import \"env\" \"{s}\" (func ${s}", .{ host_import.field, host_import.alias });
        if (host_import.params.len != 0) {
            try out.appendSlice(allocator, " (param");
            for (host_import.params) |param| {
                try appendFmt(allocator, out, " {s}", .{wasmType(param)});
            }
            try out.appendSlice(allocator, ")");
        }
        if (host_import.result) |result| {
            try appendFmt(allocator, out, " (result {s})", .{wasmType(result)});
        }
        try out.appendSlice(allocator, "))\n");
    }
}

pub fn wasiLowering(import: anytype) ?WasiLowering {
    if (std.mem.eql(u8, import.target, "clocks/system-clock/now") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "Datetime"))
    {
        return .{
            .module = "cm32p2|wasi:clocks/system-clock",
            .name = "now",
            .param = "i32",
            .result_record = "Datetime",
        };
    }
    if (std.mem.eql(u8, import.target, "clocks/system-clock/get-resolution") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "u64"))
    {
        return .{ .module = "cm32p2|wasi:clocks/system-clock", .name = "get-resolution", .result = "i64" };
    }
    if (std.mem.eql(u8, import.target, "clocks/monotonic-clock/now") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "u64"))
    {
        return .{ .module = "cm32p2|wasi:clocks/monotonic-clock", .name = "now", .result = "i64" };
    }
    if (std.mem.eql(u8, import.target, "clocks/monotonic-clock/get-resolution") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "u64"))
    {
        return .{ .module = "cm32p2|wasi:clocks/monotonic-clock", .name = "get-resolution", .result = "i64" };
    }
    if (std.mem.eql(u8, import.target, "random/random/get-random-u64") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "u64"))
    {
        return .{ .module = "cm32p2|wasi:random/random", .name = "get-random-u64", .result = "i64" };
    }
    if (std.mem.eql(u8, import.target, "random/random/get-random-bytes") and
        std.mem.eql(u8, import.params, "u64") and
        std.mem.eql(u8, import.result, "list<u8>"))
    {
        return .{ .module = "cm32p2|wasi:random/random", .name = "get-random-bytes", .param = "i64 i32", .result_storage_elem = "u8" };
    }
    // G6.1 A: preopens list-of-tuple resource; core import writes list{ptr,len} into result area.
    if (std.mem.eql(u8, import.target, "filesystem/preopens/get-directories") and
        std.mem.eql(u8, import.params, "") and
        (std.mem.eql(u8, import.result, "list<tuple<descriptor,text>>") or
            std.mem.eql(u8, import.result, "list<tuple<descriptor,string>>")))
    {
        return .{
            .module = "cm32p2|wasi:filesystem/preopens",
            .name = "get-directories",
            .param = "i32",
            .result_list_preopen = true,
        };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.sync") and
        std.mem.eql(u8, import.params, "descriptor") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.sync", .param = "i32 i32", .result_unit_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.link-at") and
        std.mem.eql(u8, import.params, "descriptor,path-flags,text,borrow<descriptor>,text") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{
            .module = "cm32p2|wasi:filesystem/types",
            .name = "[method]descriptor.link-at",
            .param = "i32 i32 i32 i32 i32 i32 i32 i32",
            .result_unit_error = true,
            .result_link_at_error = true,
        };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.create-directory-at") and
        std.mem.eql(u8, import.params, "descriptor,text") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.create-directory-at", .param = "i32 i32 i32 i32", .result_unit_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.remove-directory-at") and
        std.mem.eql(u8, import.params, "descriptor,text") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.remove-directory-at", .param = "i32 i32 i32 i32", .result_unit_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.write") and
        std.mem.eql(u8, import.params, "descriptor,list<u8>,filesize") and
        std.mem.eql(u8, import.result, "result<filesize,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.write", .param = "i32 i32 i32 i64 i32", .result_filesize_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.read") and
        std.mem.eql(u8, import.params, "descriptor,filesize,filesize") and
        std.mem.eql(u8, import.result, "result<tuple<list<u8>,bool>,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.read", .param = "i32 i64 i64 i32", .result_read_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.open-at") and
        std.mem.eql(u8, import.params, "descriptor,path-flags,text,open-flags,descriptor-flags") and
        std.mem.eql(u8, import.result, "result<descriptor,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.open-at", .param = "i32 i32 i32 i32 i32 i32 i32", .result_descriptor_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.drop") and
        std.mem.eql(u8, import.params, "descriptor") and
        std.mem.eql(u8, import.result, "nil"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[resource-drop]descriptor", .param = "i32", .resource_drop = true };
    }
    if (std.mem.eql(u8, import.target, "io/streams/input-stream.read") and
        std.mem.eql(u8, import.params, "input-stream,u64") and
        std.mem.eql(u8, import.result, "result<list<u8>,stream-error>"))
    {
        return .{ .module = "cm32p2|wasi:io/streams", .name = "[method]input-stream.read", .param = "i32 i64 i32", .result_list_u8_error = true };
    }
    if (std.mem.eql(u8, import.target, "io/streams/output-stream.check-write") and
        std.mem.eql(u8, import.params, "output-stream") and
        std.mem.eql(u8, import.result, "result<u64,stream-error>"))
    {
        return .{ .module = "cm32p2|wasi:io/streams", .name = "[method]output-stream.check-write", .param = "i32 i32", .result_u64_stream_error = true };
    }
    if (std.mem.eql(u8, import.target, "io/streams/output-stream.write") and
        std.mem.eql(u8, import.params, "output-stream,list<u8>") and
        std.mem.eql(u8, import.result, "result<_,stream-error>"))
    {
        return .{ .module = "cm32p2|wasi:io/streams", .name = "[method]output-stream.write", .param = "i32 i32 i32 i32", .result_unit_error = true };
    }
    if (std.mem.eql(u8, import.target, "io/streams/output-stream.flush") and
        std.mem.eql(u8, import.params, "output-stream") and
        std.mem.eql(u8, import.result, "result<_,stream-error>"))
    {
        return .{ .module = "cm32p2|wasi:io/streams", .name = "[method]output-stream.flush", .param = "i32 i32", .result_unit_error = true };
    }
    // G6.3 scheme B: tcp/udp-socket create/bind/drop (resource + family/address variant).
    if (std.mem.eql(u8, import.target, "sockets/types/tcp-socket.create") and
        std.mem.eql(u8, import.params, "ip-address-family") and
        std.mem.eql(u8, import.result, "result<tcp-socket,error-code>"))
    {
        return .{
            .module = "cm32p2|wasi:sockets/types",
            .name = "[static]tcp-socket.create",
            .param = "i32 i32",
            .result_descriptor_error = true,
        };
    }
    if (std.mem.eql(u8, import.target, "sockets/types/udp-socket.create") and
        std.mem.eql(u8, import.params, "ip-address-family") and
        std.mem.eql(u8, import.result, "result<udp-socket,error-code>"))
    {
        return .{
            .module = "cm32p2|wasi:sockets/types",
            .name = "[static]udp-socket.create",
            .param = "i32 i32",
            .result_descriptor_error = true,
        };
    }
    if (std.mem.eql(u8, import.target, "sockets/types/tcp-socket.bind") and
        std.mem.eql(u8, import.params, "tcp-socket,ip-socket-address") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{
            .module = "cm32p2|wasi:sockets/types",
            .name = "[method]tcp-socket.bind",
            .param = "i32 i32 i32",
            .result_unit_error = true,
        };
    }
    if (std.mem.eql(u8, import.target, "sockets/types/udp-socket.bind") and
        std.mem.eql(u8, import.params, "udp-socket,ip-socket-address") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{
            .module = "cm32p2|wasi:sockets/types",
            .name = "[method]udp-socket.bind",
            .param = "i32 i32 i32",
            .result_unit_error = true,
        };
    }
    if (std.mem.eql(u8, import.target, "sockets/types/tcp-socket.drop") and
        std.mem.eql(u8, import.params, "tcp-socket") and
        std.mem.eql(u8, import.result, "nil"))
    {
        return .{
            .module = "cm32p2|wasi:sockets/types",
            .name = "[resource-drop]tcp-socket",
            .param = "i32",
            .resource_drop = true,
        };
    }
    if (std.mem.eql(u8, import.target, "sockets/types/udp-socket.drop") and
        std.mem.eql(u8, import.params, "udp-socket") and
        std.mem.eql(u8, import.result, "nil"))
    {
        return .{
            .module = "cm32p2|wasi:sockets/types",
            .name = "[resource-drop]udp-socket",
            .param = "i32",
            .resource_drop = true,
        };
    }
    return null;
}

pub fn appendWasiImportSymbol(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    target: []const u8,
) !void {
    try out.appendSlice(allocator, "__wasi_import_");
    for (target) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '_') {
            try out.append(allocator, ch);
        } else {
            try out.append(allocator, '_');
        }
    }
}

fn appendDoSignatureAsWit(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    signature: []const u8,
) !void {
    var i: usize = 0;
    while (i < signature.len) {
        if (isWitIdentChar(signature[i])) {
            const start = i;
            while (i < signature.len and isWitIdentChar(signature[i])) : (i += 1) {}
            const ident = signature[start..i];
            if (std.mem.eql(u8, ident, "text")) {
                try out.appendSlice(allocator, "string");
            } else {
                try out.appendSlice(allocator, ident);
            }
            continue;
        }
        try out.append(allocator, signature[i]);
        i += 1;
    }
}

fn isWitIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-';
}

fn wasmType(ty: []const u8) []const u8 {
    if (std.mem.eql(u8, ty, "bool")) return "i32";
    if (std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8")) return "i32";
    if (std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16")) return "i32";
    if (std.mem.eql(u8, ty, "i32") or std.mem.eql(u8, ty, "u32")) return "i32";
    if (std.mem.eql(u8, ty, "isize") or std.mem.eql(u8, ty, "usize")) return "i32";
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) return "i64";
    if (std.mem.eql(u8, ty, "f32")) return "f32";
    if (std.mem.eql(u8, ty, "f64")) return "f64";
    return "i32";
}

fn hasString(items: []const []const u8, target: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, target)) return true;
    }
    return false;
}

fn appendFmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

test "component metadata writer emits wasi bind manifest comments" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const imports = [_]struct {
        source: []const u8,
        alias: []const u8,
        target: []const u8,
        params: []const u8,
        result: []const u8,
    }{
        .{
            .source = "entry",
            .alias = "host_now",
            .target = "clocks/system-clock/now",
            .params = "",
            .result = "Datetime",
        },
        .{
            .source = "lib/io.do",
            .alias = "host_read_text",
            .target = "io/streams/input-stream.read",
            .params = "input-stream,text",
            .result = "result<list<u8>,stream-error>",
        },
    };

    try emitWasiBindings(allocator, &out, imports[0..]);

    try std.testing.expectEqualStrings(
        \\  ;; wasi-bind source="entry" alias="host_now" target="clocks/system-clock/now" params="" result="Datetime"
        \\  ;; wasi-bind source="lib/io.do" alias="host_read_text" target="io/streams/input-stream.read" params="input-stream,string" result="result<list<u8>,stream-error>"
        \\
    , out.items);
}

test "component metadata writer emits deduplicated wasi core imports" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const imports = [_]struct {
        source: []const u8,
        alias: []const u8,
        target: []const u8,
        params: []const u8,
        result: []const u8,
    }{
        .{
            .source = "entry",
            .alias = "host_now",
            .target = "clocks/system-clock/now",
            .params = "",
            .result = "Datetime",
        },
        .{
            .source = "lib/time.do",
            .alias = "clock_now",
            .target = "clocks/system-clock/now",
            .params = "",
            .result = "Datetime",
        },
        .{
            .source = "entry",
            .alias = "host_resolution",
            .target = "clocks/system-clock/get-resolution",
            .params = "",
            .result = "u64",
        },
    };

    try emitWasiCoreImports(allocator, &out, imports[0..]);

    try std.testing.expectEqualStrings(
        \\  (import "cm32p2|wasi:clocks/system-clock" "now" (func $__wasi_import_clocks_system_clock_now (param i32)))
        \\  (import "cm32p2|wasi:clocks/system-clock" "get-resolution" (func $__wasi_import_clocks_system_clock_get_resolution (result i64)))
        \\
    , out.items);
}

test "component metadata writer emits env host imports" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const imports = [_]struct {
        alias: []const u8,
        field: []const u8,
        params: []const []const u8,
        result: ?[]const u8,
    }{
        .{
            .alias = "host_log",
            .field = "log",
            .params = &[_][]const u8{ "text", "i32" },
            .result = null,
        },
        .{
            .alias = "host_i64",
            .field = "read_i64",
            .params = &[_][]const u8{"u64"},
            .result = "i64",
        },
    };

    try emitHostImports(allocator, &out, imports[0..]);

    try std.testing.expectEqualStrings(
        \\  (import "env" "log" (func $host_log (param i32 i32)))
        \\  (import "env" "read_i64" (func $host_i64 (param i64) (result i64)))
        \\
    , out.items);
}

test "component metadata writer exposes wasi import symbol escaping" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try appendWasiImportSymbol(allocator, &out, "filesystem/types/descriptor.link-at");

    try std.testing.expectEqualStrings("__wasi_import_filesystem_types_descriptor_link_at", out.items);
}
