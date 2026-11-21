const std = @import("std");
const generated_text = @import("codegen_text.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const sema_tokens = @import("sema_tokens.zig");

const compact_token_range_equals = sema_tokens.compact_token_range_equals;
const find_matching = sema_tokens.find_matching;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

pub const Error = error{UnsupportedP3WasiFilesystemAdviseComponent};
const locator = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const member = "descriptor.advise";

pub fn emit_component_wat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try FilesystemAdvisePlan.analyze(tokens, registry);
    if (!std.mem.eql(u8, plan.descriptor.canonical.async_import_name, "[async-lower][method]descriptor.advise")) return error.UnsupportedP3WasiFilesystemAdviseComponent;
    return generated_text.alloc_block(allocator, 0, @embedFile("wasi_filesystem_advise_component_template.wat"));
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    _ = try FilesystemAdvisePlan.analyze(tokens, registry);
    return generated_text.alloc_block(allocator, 0, component_wit);
}

pub const FilesystemAdvisePlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    host_name: []const u8,
    root_name: []const u8,
    file_name: []const u8,
    offset_name: []const u8,
    length_name: []const u8,
    advice_name: []const u8,
    pending_name: []const u8,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) Error!FilesystemAdvisePlan {
        const descriptor = registry.find(locator, member) orelse return error.UnsupportedP3WasiFilesystemAdviseComponent;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3WasiFilesystemAdviseComponent) {
            .filesystem_advise => {},
            else => return error.UnsupportedP3WasiFilesystemAdviseComponent,
        }
        var host: ?[]const u8 = null;
        var host_count: usize = 0;
        var idx: usize = 0;
        while (idx + 9 < tokens.len) : (idx += 1) {
            if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host_async_func") or !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(")) continue;
            host_count += 1;
            const host_locator = string_token_body(tokens[idx + 5].lexeme) orelse continue;
            const host_member = string_token_body(tokens[idx + 7].lexeme) orelse continue;
            if (!std.mem.eql(u8, host_locator, locator) or !std.mem.eql(u8, host_member, member)) continue;
            if (host != null or !signature_matches(tokens, idx + 9)) return error.UnsupportedP3WasiFilesystemAdviseComponent;
            host = tokens[idx].lexeme;
        }
        const host_name = host orelse return error.UnsupportedP3WasiFilesystemAdviseComponent;
        if (host_count != 1 or !has_exact_token_sequence(tokens, "File", "File=@wasi_resource(\"filesystem/types/descriptor\",{.idi64})") or !has_exact_token_sequence(tokens, "Advice", "Adviceu32=Normal(0)|Sequential(1)|Random(2)|WillNeed(3)|DontNeed(4)|NoReuse(5)") or !has_exact_token_sequence(tokens, "AdviseError", "AdviseErrorerror=Io|Invalid|BadDescriptor")) return error.UnsupportedP3WasiFilesystemAdviseComponent;
        const function = find_run_function(tokens, host_name) orelse return error.UnsupportedP3WasiFilesystemAdviseComponent;
        if (!has_empty_start_function(tokens)) return error.UnsupportedP3WasiFilesystemAdviseComponent;
        return .{ .descriptor = descriptor, .host_name = host_name, .root_name = function.root_name, .file_name = function.file_name, .offset_name = function.offset_name, .length_name = function.length_name, .advice_name = function.advice_name, .pending_name = function.pending_name };
    }
};

const RunFunction = struct { root_name: []const u8, file_name: []const u8, offset_name: []const u8, length_name: []const u8, advice_name: []const u8, pending_name: []const u8 };

fn signature_matches(tokens: []const lexer.Token, start: usize) bool {
    const close = find_matching(tokens, start, "(", ")") catch return false;
    if (close != start + 8 or !tok_eq(tokens[start + 1], "File") or !tok_eq(tokens[start + 2], ",") or !tok_eq(tokens[start + 3], "u64") or !tok_eq(tokens[start + 4], ",") or !tok_eq(tokens[start + 5], "u64") or !tok_eq(tokens[start + 6], ",") or !tok_eq(tokens[start + 7], "Advice") or !tok_eq(tokens[close + 1], "-") or !tok_eq(tokens[close + 2], ">")) return false;
    const host_close = find_matching(tokens, start - 5, "(", ")") catch return false;
    return compact_token_range_equals(tokens, close + 3, host_close, "nil|AdviseError");
}

fn has_exact_token_sequence(tokens: []const lexer.Token, name: []const u8, expected: []const u8) bool {
    var found = false;
    for (tokens, 0..) |token, idx| {
        if (token.kind != .ident or !std.mem.eql(u8, token.lexeme, name)) continue;
        if (compact_token_range_equals(tokens, idx, line_end(tokens, idx), expected)) {
            if (found) return false;
            found = true;
        }
    }
    return found;
}

fn line_end(tokens: []const lexer.Token, start: usize) usize {
    if (start >= tokens.len) return start;
    var idx = start;
    while (idx < tokens.len and tokens[idx].line == tokens[start].line) : (idx += 1) {}
    return idx;
}

fn find_run_function(tokens: []const lexer.Token, host_name: []const u8) ?RunFunction {
    var idx: usize = 0;
    while (idx + 13 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx], "run") or !tok_eq(tokens[idx + 1], "(")) continue;
        if (idx > 0 and tok_eq(tokens[idx - 1], "async")) return null;
        const close = find_matching(tokens, idx + 1, "(", ")") catch return null;
        if (close != idx + 13 or !tok_eq(tokens[idx + 3], "File") or !tok_eq(tokens[idx + 6], "u64") or !tok_eq(tokens[idx + 9], "u64") or !tok_eq(tokens[idx + 12], "Advice") or !tok_eq(tokens[close + 1], "-") or !tok_eq(tokens[close + 2], ">")) continue;
        const body = close + 3;
        if (!tok_eq(tokens[body], "nil") or !tok_eq(tokens[body + 1], "|") or !tok_eq(tokens[body + 2], "AdviseError") or !tok_eq(tokens[body + 3], "{")) continue;
        const body_close = find_matching(tokens, body + 3, "{", "}") catch return null;
        const pending = tokens[body + 4].lexeme;
        if (!compact_token_range_equals(tokens, body + 4, body_close, "pendingFuture<nil|AdviseError>=advise_descriptor(file,offset,length,advice)return@await(pending)")) continue;
        _ = host_name;
        return .{ .root_name = tokens[idx].lexeme, .file_name = tokens[idx + 2].lexeme, .offset_name = tokens[idx + 5].lexeme, .length_name = tokens[idx + 8].lexeme, .advice_name = tokens[idx + 11].lexeme, .pending_name = pending };
    }
    return null;
}

fn count_function_definitions(tokens: []const lexer.Token) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 3 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "(")) continue;
        const close = find_matching(tokens, idx + 1, "(", ")") catch continue;
        if (close + 1 >= tokens.len or (!tok_eq(tokens[close + 1], "-") and !tok_eq(tokens[close + 1], "{"))) continue;
        var open = close + 1;
        if (tok_eq(tokens[open], "-")) { if (open + 2 >= tokens.len or !tok_eq(tokens[open + 2], ">")) continue; open += 2; while (open < tokens.len and !tok_eq(tokens[open], "{")) : (open += 1) {} }
        if (open < tokens.len) { count += 1; idx = find_matching(tokens, open, "{", "}") catch idx; }
    }
    return count;
}

fn has_empty_start_function(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, idx| {
        if (token.kind != .ident or !tok_eq(token, "start") or idx + 1 >= tokens.len or !tok_eq(tokens[idx + 1], "(")) continue;
        const close = find_matching(tokens, idx + 1, "(", ")") catch return false;
        if (close + 1 >= tokens.len or !tok_eq(tokens[close + 1], "{")) continue;
        const end = find_matching(tokens, close + 1, "{", "}") catch return false;
        return end == close + 2;
    }
    return false;
}

const component_wit =
    \\package wasi:filesystem@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  type filesize = u64;
    \\  enum advice { normal, sequential, random, will-need, dont-need, no-reuse }
    \\  enum error-code { access, already, bad-descriptor, busy, deadlock, quota, exist, file-too-large, illegal-byte-sequence, in-progress, interrupted, invalid, io, is-directory, loop, too-many-links, message-size, name-too-long, no-device, no-entry, no-lock, insufficient-memory, insufficient-space, not-directory, not-empty, not-recoverable, unsupported, no-tty, no-such-device, overflow, not-permitted, pipe, read-only, invalid-seek, text-file-busy, cross-device }
    \\  resource descriptor { advise: async func(offset: filesize, length: filesize, advice: advice) -> result<_, error-code>; }
    \\}
    \\
    \\interface probe { use types.{descriptor, advice, error-code, filesize}; run: async func(file: own<descriptor>, offset: filesize, length: filesize, advice: advice) -> result<_, error-code>; }
    \\
    \\world advise-probe { import types; export probe; }
    \\
    ;
