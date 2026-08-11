const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const sema_tokens = @import("sema_tokens.zig");

const compact_token_range_equals = sema_tokens.compact_token_range_equals;
const find_matching = sema_tokens.find_matching;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

pub const Error = error{UnsupportedP3WasiFilesystemOpenAtComponent};

const locator = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const member = "descriptor.open-at";

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try FilesystemOpenAtPlan.analyze(tokens, registry);
    if (!std.mem.eql(u8, plan.descriptor.canonical.async_import_module, locator) or
        !std.mem.eql(u8, plan.descriptor.canonical.async_import_name, "[async-lower][method]descriptor.open-at") or
        plan.descriptor.canonical.core_params.len != 2 or
        plan.descriptor.canonical.completion_params.len != 2)
        return error.UnsupportedP3WasiFilesystemOpenAtComponent;
    return allocator.dupe(u8, @embedFile("wasi_filesystem_open_at_component_template.wat"));
}

pub fn emit_component_wit(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    _ = try FilesystemOpenAtPlan.analyze(tokens, registry);
    return allocator.dupe(u8, component_wit);
}

pub const FilesystemOpenAtPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    host_name: []const u8,
    root_name: []const u8,
    file_name: []const u8,
    path_flags_name: []const u8,
    path_name: []const u8,
    open_flags_name: []const u8,
    descriptor_flags_name: []const u8,
    pending_name: []const u8,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) Error!FilesystemOpenAtPlan {
        const descriptor = registry.find(locator, member) orelse return error.UnsupportedP3WasiFilesystemOpenAtComponent;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3WasiFilesystemOpenAtComponent) {
            .filesystem_open_at => {},
            else => return error.UnsupportedP3WasiFilesystemOpenAtComponent,
        }

        var host: ?HostBinding = null;
        var host_count: usize = 0;
        var idx: usize = 0;
        while (idx + 3 < tokens.len) : (idx += 1) {
            if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
                (!tok_eq(tokens[idx + 3], "host_async_func") and !tok_eq(tokens[idx + 3], "host_func"))) continue;
            host_count += 1;
            if (!tok_eq(tokens[idx + 3], "host_async_func") or idx + 9 >= tokens.len or
                !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or
                tokens[idx + 7].kind != .string or !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "("))
                return error.UnsupportedP3WasiFilesystemOpenAtComponent;
            const host_locator = string_token_body(tokens[idx + 5].lexeme) orelse return error.UnsupportedP3WasiFilesystemOpenAtComponent;
            const host_member = string_token_body(tokens[idx + 7].lexeme) orelse return error.UnsupportedP3WasiFilesystemOpenAtComponent;
            if (!std.mem.eql(u8, host_locator, locator) or !std.mem.eql(u8, host_member, member) or
                host != null or !signature_matches(tokens, idx + 9))
                return error.UnsupportedP3WasiFilesystemOpenAtComponent;
            host = .{ .name = tokens[idx].lexeme };
        }
        const host_binding = host orelse return error.UnsupportedP3WasiFilesystemOpenAtComponent;
        if (host_count != 1 or !has_exact_resource_decls(tokens) or !has_exact_open_error_decl(tokens))
            return error.UnsupportedP3WasiFilesystemOpenAtComponent;

        const function = find_run_function(tokens, host_binding.name) orelse return error.UnsupportedP3WasiFilesystemOpenAtComponent;
        if (count_function_definitions(tokens) != 2 or !has_empty_start_function(tokens))
            return error.UnsupportedP3WasiFilesystemOpenAtComponent;

        return .{
            .descriptor = descriptor,
            .host_name = host_binding.name,
            .root_name = function.root_name,
            .file_name = function.file_name,
            .path_flags_name = function.path_flags_name,
            .path_name = function.path_name,
            .open_flags_name = function.open_flags_name,
            .descriptor_flags_name = function.descriptor_flags_name,
            .pending_name = function.pending_name,
        };
    }
};

const HostBinding = struct { name: []const u8 };

const RunFunction = struct {
    root_name: []const u8,
    file_name: []const u8,
    path_flags_name: []const u8,
    path_name: []const u8,
    open_flags_name: []const u8,
    descriptor_flags_name: []const u8,
    pending_name: []const u8,
};

fn signature_matches(tokens: []const lexer.Token, signature_start: usize) bool {
    const params_close = find_matching(tokens, signature_start, "(", ")") catch return false;
    if (params_close != signature_start + 10 or
        tokens[signature_start + 1].kind != .ident or !std.mem.eql(u8, tokens[signature_start + 1].lexeme, "Dir") or
        !tok_eq(tokens[signature_start + 2], ",") or tokens[signature_start + 3].kind != .ident or
        !std.mem.eql(u8, tokens[signature_start + 3].lexeme, "u32") or !tok_eq(tokens[signature_start + 4], ",") or
        tokens[signature_start + 5].kind != .ident or !std.mem.eql(u8, tokens[signature_start + 5].lexeme, "text") or
        !tok_eq(tokens[signature_start + 6], ",") or tokens[signature_start + 7].kind != .ident or
        !std.mem.eql(u8, tokens[signature_start + 7].lexeme, "u32") or !tok_eq(tokens[signature_start + 8], ",") or
        tokens[signature_start + 9].kind != .ident or !std.mem.eql(u8, tokens[signature_start + 9].lexeme, "u32") or
        params_close + 3 >= tokens.len or !tok_eq(tokens[params_close + 1], "-") or !tok_eq(tokens[params_close + 2], ">"))
        return false;
    const host_open = signature_start - 5;
    const host_close = find_matching(tokens, host_open, "(", ")") catch return false;
    return host_close > params_close + 3 and
        compact_token_range_equals(tokens, params_close + 3, host_close, "File|OpenError");
}

fn has_exact_resource_decls(tokens: []const lexer.Token) bool {
    if (!has_exact_token_sequence(tokens, "Dir", "Dir=@wasi_resource(\"filesystem/types/descriptor\",{.idi64})") or
        !has_exact_token_sequence(tokens, "File", "File=@wasi_resource(\"filesystem/types/descriptor\",{.idi64})")) return false;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "@") and tok_eq(tokens[idx + 1], "wasi_resource")) count += 1;
    }
    return count == 2;
}

fn has_exact_open_error_decl(tokens: []const lexer.Token) bool {
    return has_exact_token_sequence(tokens, "OpenError", "OpenErrorerror=Io|NoEntry");
}

fn has_exact_token_sequence(tokens: []const lexer.Token, name: []const u8, expected: []const u8) bool {
    var found = false;
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, name)) continue;
        const end = line_end(tokens, idx);
        if (compact_token_range_equals(tokens, idx, end, expected)) {
            if (found) return false;
            found = true;
        }
    }
    return found;
}

fn line_end(tokens: []const lexer.Token, start: usize) usize {
    if (start >= tokens.len) return start;
    const line = tokens[start].line;
    var idx = start;
    while (idx < tokens.len and tokens[idx].line == line) : (idx += 1) {}
    return idx;
}

fn find_run_function(tokens: []const lexer.Token, host_name: []const u8) ?RunFunction {
    var idx: usize = 0;
    while (idx + 3 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, "run") or
            !tok_eq(tokens[idx + 1], "(")) continue;
        if (idx > 0 and tok_eq(tokens[idx - 1], "async")) return null;
        const params_close = find_matching(tokens, idx + 1, "(", ")") catch return null;
        if (params_close != idx + 16 or tokens[idx + 2].kind != .ident or tokens[idx + 3].kind != .ident or
            !std.mem.eql(u8, tokens[idx + 3].lexeme, "Dir") or !tok_eq(tokens[idx + 4], ",") or
            tokens[idx + 5].kind != .ident or tokens[idx + 6].kind != .ident or !std.mem.eql(u8, tokens[idx + 6].lexeme, "u32") or
            !tok_eq(tokens[idx + 7], ",") or tokens[idx + 8].kind != .ident or tokens[idx + 9].kind != .ident or
            !std.mem.eql(u8, tokens[idx + 9].lexeme, "text") or !tok_eq(tokens[idx + 10], ",") or
            tokens[idx + 11].kind != .ident or tokens[idx + 12].kind != .ident or !std.mem.eql(u8, tokens[idx + 12].lexeme, "u32") or
            !tok_eq(tokens[idx + 13], ",") or tokens[idx + 14].kind != .ident or tokens[idx + 15].kind != .ident or
            !std.mem.eql(u8, tokens[idx + 15].lexeme, "u32") or !tok_eq(tokens[params_close + 1], "-") or
            !tok_eq(tokens[params_close + 2], ">")) continue;
        if (params_close + 6 >= tokens.len or !tok_eq(tokens[params_close + 3], "File") or
            !tok_eq(tokens[params_close + 4], "|") or !tok_eq(tokens[params_close + 5], "OpenError") or
            !tok_eq(tokens[params_close + 6], "{")) continue;
        const body_close = find_matching(tokens, params_close + 6, "{", "}") catch return null;
        const pending_name = body_matches(
            tokens,
            params_close + 7,
            body_close,
            host_name,
            tokens[idx + 2].lexeme,
            tokens[idx + 5].lexeme,
            tokens[idx + 8].lexeme,
            tokens[idx + 11].lexeme,
            tokens[idx + 14].lexeme,
        ) orelse return null;
        return .{
            .root_name = tokens[idx].lexeme,
            .file_name = tokens[idx + 2].lexeme,
            .path_flags_name = tokens[idx + 5].lexeme,
            .path_name = tokens[idx + 8].lexeme,
            .open_flags_name = tokens[idx + 11].lexeme,
            .descriptor_flags_name = tokens[idx + 14].lexeme,
            .pending_name = pending_name,
        };
    }
    return null;
}

fn body_matches(
    tokens: []const lexer.Token,
    start: usize,
    end: usize,
    host_name: []const u8,
    root_name: []const u8,
    path_flags_name: []const u8,
    path_name: []const u8,
    open_flags_name: []const u8,
    descriptor_flags_name: []const u8,
) ?[]const u8 {
    if (start >= end or tokens[start].kind != .ident) return null;
    const pending_name = tokens[start].lexeme;
    var idx = start + 1;
    const fixed = [_][]const u8{ "Future", "<", "File", "|", "OpenError", ">", "=" };
    for (fixed) |expected| {
        if (idx >= end or !tok_eq(tokens[idx], expected)) return null;
        idx += 1;
    }
    if (idx >= end or !std.mem.eql(u8, tokens[idx].lexeme, host_name)) return null;
    idx += 1;
    if (idx >= end or !tok_eq(tokens[idx], "(")) return null;
    idx += 1;
    const args = [_][]const u8{ root_name, path_flags_name, path_name, open_flags_name, descriptor_flags_name };
    for (args, 0..) |arg, arg_idx| {
        if (idx >= end or !std.mem.eql(u8, tokens[idx].lexeme, arg)) return null;
        idx += 1;
        if (arg_idx + 1 < args.len) {
            if (idx >= end or !tok_eq(tokens[idx], ",")) return null;
            idx += 1;
        }
    }
    const await_prefix = [_][]const u8{ ")", "return", "@", "await", "(" };
    for (await_prefix) |expected| {
        if (idx >= end or !tok_eq(tokens[idx], expected)) return null;
        idx += 1;
    }
    if (idx >= end or !std.mem.eql(u8, tokens[idx].lexeme, pending_name)) return null;
    idx += 1;
    if (idx >= end or !tok_eq(tokens[idx], ")")) return null;
    idx += 1;
    return if (idx == end) pending_name else null;
}

fn count_function_definitions(tokens: []const lexer.Token) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 3 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "(")) continue;
        const params_close = find_matching(tokens, idx + 1, "(", ")") catch continue;
        if (params_close + 1 >= tokens.len or (!tok_eq(tokens[params_close + 1], "-") and !tok_eq(tokens[params_close + 1], "{"))) continue;
        if (tok_eq(tokens[params_close + 1], "{")) {
            count += 1;
            idx = find_matching(tokens, params_close + 1, "{", "}") catch idx;
        } else if (params_close + 2 < tokens.len and tok_eq(tokens[params_close + 2], ">")) {
            var body_open = params_close + 3;
            while (body_open < tokens.len and !tok_eq(tokens[body_open], "{")) : (body_open += 1) {}
            if (body_open < tokens.len) {
                count += 1;
                idx = find_matching(tokens, body_open, "{", "}") catch idx;
            }
        }
    }
    return count;
}

fn has_empty_start_function(tokens: []const lexer.Token) bool {
    var idx: usize = 0;
    while (idx + 3 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, "start") or
            !tok_eq(tokens[idx + 1], "(")) continue;
        const close = find_matching(tokens, idx + 1, "(", ")") catch return false;
        if (close + 1 < tokens.len and tok_eq(tokens[close + 1], "{")) {
            const body_close = find_matching(tokens, close + 1, "{", "}") catch return false;
            return body_close == close + 2;
        }
    }
    return false;
}

const component_wit =
    "package wasi:filesystem@0.3.0-rc-2025-09-16;\n\n" ++
    "interface types {\n" ++
    "  flags path-flags { symlink-follow }\n" ++
    "  flags open-flags { create, directory, exclusive, truncate }\n" ++
    "  flags descriptor-flags { read, write, file-integrity-sync, data-integrity-sync, requested-write-sync, mutate-directory }\n" ++
    "  enum error-code { access, already, bad-descriptor, busy, deadlock, quota, exist, file-too-large, illegal-byte-sequence, in-progress, interrupted, invalid, io, is-directory, loop, too-many-links, message-size, name-too-long, no-device, no-entry, no-lock, insufficient-memory, insufficient-space, not-directory, not-empty, not-recoverable, unsupported, no-tty, no-such-device, overflow, not-permitted, pipe, read-only, invalid-seek, text-file-busy, cross-device }\n" ++
    "  resource descriptor { open-at: async func(path-flags: path-flags, path: string, open-flags: open-flags, descriptor-flags: descriptor-flags) -> result<descriptor, error-code>; }\n" ++
    "}\n\n" ++
    "interface probe {\n" ++
    "  use types.{descriptor, error-code, path-flags, open-flags, descriptor-flags};\n" ++
    "  run: async func(root: own<descriptor>, path-flags: path-flags, path: string, open-flags: open-flags, descriptor-flags: descriptor-flags) -> result<own<descriptor>, error-code>;\n" ++
    "}\n\n" ++
    "world open-at-probe {\n" ++
    "  import types;\n" ++
    "  export probe;\n" ++
    "}\n";

test "open-at planner captures the fixed source shape" {
    const source = @embedFile("test/compile_ok/540_wasi_filesystem_open_at_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try FilesystemOpenAtPlan.analyze(tokens, registry);
    try std.testing.expectEqualStrings("open_at_descriptor", plan.host_name);
    try std.testing.expectEqualStrings("run", plan.root_name);
    try std.testing.expectEqualStrings("path_flags", plan.path_flags_name);
    try std.testing.expectEqualStrings("path", plan.path_name);
    try std.testing.expectEqualStrings("open_flags", plan.open_flags_name);
    try std.testing.expectEqualStrings("descriptor_flags", plan.descriptor_flags_name);
    try std.testing.expectEqualStrings("pending", plan.pending_name);
}

test "open-at emitter emits the pinned WIT and Core markers" {
    const source = @embedFile("test/compile_ok/540_wasi_filesystem_open_at_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "open-at: async func(path-flags: path-flags, path: string") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "result<own<descriptor>, error-code>") != null);

    const wat = try emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(wat);
    for ([_][]const u8{
        "[async-lower][method]descriptor.open-at",
        "[resource-drop]descriptor",
        "[open-at-call]",
        "[open-at-result-area]",
        "[open-at-path-copy]",
        "[open-at-ready]",
        "[open-at-error]",
        "[open-at-pending]",
    }) |marker| try std.testing.expect(std.mem.indexOf(u8, wat, marker) != null);
}

test "open-at planner rejects non-linear and ownership-drifted sources" {
    const cases = [_][]const u8{
        @embedFile("test/compile_err/542_wasi_filesystem_open_at_wrong_path_flags.do"),
        @embedFile("test/compile_err/543_wasi_filesystem_open_at_wrong_open_flags.do"),
        @embedFile("test/compile_err/544_wasi_filesystem_open_at_wrong_descriptor_flags.do"),
        @embedFile("test/compile_err/545_wasi_filesystem_open_at_wrong_result_resource.do"),
        @embedFile("test/compile_err/546_wasi_filesystem_open_at_borrowed_result.do"),
        @embedFile("test/compile_err/547_wasi_filesystem_open_at_second_await.do"),
        @embedFile("test/compile_err/548_wasi_filesystem_open_at_branch.do"),
        @embedFile("test/compile_err/549_wasi_filesystem_open_at_loop.do"),
        @embedFile("test/compile_err/550_wasi_filesystem_open_at_extra_host.do"),
        @embedFile("test/compile_err/551_wasi_filesystem_open_at_async_root.do"),
    };
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    for (cases) |source| {
        const tokens = try lexer.tokenize(std.testing.allocator, source);
        defer std.testing.allocator.free(tokens);
        try std.testing.expectError(
            error.UnsupportedP3WasiFilesystemOpenAtComponent,
            FilesystemOpenAtPlan.analyze(tokens, registry),
        );
    }
}
