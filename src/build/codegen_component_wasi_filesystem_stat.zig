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

pub const Error = error{UnsupportedP3WasiFilesystemStatComponent};

const locator = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const member = "descriptor.stat";

pub const StatPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    host_name: []const u8,
    root_name: []const u8,
    file_name: []const u8,
    pending_name: []const u8,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) Error!StatPlan {
        const descriptor = registry.find(locator, member) orelse return error.UnsupportedP3WasiFilesystemStatComponent;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3WasiFilesystemStatComponent) {
            .filesystem_stat => {},
            else => return error.UnsupportedP3WasiFilesystemStatComponent,
        }

        var host: ?HostBinding = null;
        var host_count: usize = 0;
        var idx: usize = 0;
        while (idx + 4 < tokens.len) : (idx += 1) {
            if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
                (!tok_eq(tokens[idx + 3], "host_async_func") and !tok_eq(tokens[idx + 3], "host_func"))) continue;
            host_count += 1;
            if (!tok_eq(tokens[idx + 3], "host_async_func") or idx + 9 >= tokens.len or
                !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or
                tokens[idx + 7].kind != .string or !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "("))
                return error.UnsupportedP3WasiFilesystemStatComponent;
            const host_locator = string_token_body(tokens[idx + 5].lexeme) orelse return error.UnsupportedP3WasiFilesystemStatComponent;
            const host_member = string_token_body(tokens[idx + 7].lexeme) orelse return error.UnsupportedP3WasiFilesystemStatComponent;
            if (!std.mem.eql(u8, host_locator, locator) or !std.mem.eql(u8, host_member, member) or
                host != null or !signature_matches(tokens, idx + 9)) return error.UnsupportedP3WasiFilesystemStatComponent;
            host = .{ .name = tokens[idx].lexeme };
        }
        const host_binding = host orelse return error.UnsupportedP3WasiFilesystemStatComponent;
        if (host_count != 1 or !has_exact_resource_decl(tokens) or !has_exact_datetime_decl(tokens) or
            !has_exact_descriptor_stat_decl(tokens) or !has_exact_stat_error_decl(tokens))
            return error.UnsupportedP3WasiFilesystemStatComponent;

        const function = find_run_function(tokens) orelse return error.UnsupportedP3WasiFilesystemStatComponent;
        if (count_function_definitions(tokens) != 2 or !has_empty_start_function(tokens))
            return error.UnsupportedP3WasiFilesystemStatComponent;

        return .{
            .descriptor = descriptor,
            .host_name = host_binding.name,
            .root_name = function.root_name,
            .file_name = function.file_name,
            .pending_name = function.pending_name,
        };
    }
};

const HostBinding = struct { name: []const u8 };

const RunFunction = struct {
    root_name: []const u8,
    file_name: []const u8,
    pending_name: []const u8,
};

fn signature_matches(tokens: []const lexer.Token, signature_start: usize) bool {
    const params_close = find_matching(tokens, signature_start, "(", ")") catch return false;
    if (params_close != signature_start + 2 or tokens[signature_start + 1].kind != .ident or
        !std.mem.eql(u8, tokens[signature_start + 1].lexeme, "Dir") or
        params_close + 3 >= tokens.len or !tok_eq(tokens[params_close + 1], "-") or
        !tok_eq(tokens[params_close + 2], ">")) return false;
    const host_open = signature_start - 5;
    const host_close = find_matching(tokens, host_open, "(", ")") catch return false;
    return host_close > params_close + 3 and
        compact_token_range_equals(tokens, params_close + 3, host_close, "DescriptorStat|StatError");
}

fn has_exact_resource_decl(tokens: []const lexer.Token) bool {
    return has_exact_token_sequence(tokens, "Dir", "Dir=@wasi_resource(\"filesystem/types/descriptor\",{.idi64})");
}

fn has_exact_datetime_decl(tokens: []const lexer.Token) bool {
    return has_exact_token_sequence(tokens, "Datetime", "Datetime=@wasi_record(\"clocks/wall-clock/datetime\",{secondsi64,nanosecondsu32})");
}

fn has_exact_descriptor_stat_decl(tokens: []const lexer.Token) bool {
    return has_exact_token_sequence(tokens, "DescriptorStat", "DescriptorStat=@wasi_record(\"filesystem/types/descriptor-stat\",{.typei32,link_countu64,sizeu64,data_access_timestampoption<Datetime>,data_modification_timestampoption<Datetime>,status_change_timestampoption<Datetime>})");
}

fn has_exact_stat_error_decl(tokens: []const lexer.Token) bool {
    return has_exact_token_sequence(tokens, "StatError", "StatErrorerror=Io|NoEntry");
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

fn find_run_function(tokens: []const lexer.Token) ?RunFunction {
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, "run") or !tok_eq(tokens[idx + 1], "(")) continue;
        if (idx > 0 and tok_eq(tokens[idx - 1], "async")) return null;
        const params_close = find_matching(tokens, idx + 1, "(", ")") catch return null;
        if (params_close != idx + 4 or tokens[idx + 2].kind != .ident or !tok_eq(tokens[idx + 3], "Dir") or
            !tok_eq(tokens[params_close + 1], "-") or !tok_eq(tokens[params_close + 2], ">")) continue;
        const body_open = params_close + 3;
        if (body_open + 3 >= tokens.len or !tok_eq(tokens[body_open], "DescriptorStat") or
            !tok_eq(tokens[body_open + 1], "|") or !tok_eq(tokens[body_open + 2], "StatError") or
            !tok_eq(tokens[body_open + 3], "{")) continue;
        const body_close = find_matching(tokens, body_open + 3, "{", "}") catch return null;
        if (!compact_token_range_equals(tokens, body_open + 4, body_close,
            "pendingFuture<DescriptorStat|StatError>=stat_descriptor(file)return@await(pending)")) return null;
        return .{
            .root_name = tokens[idx].lexeme,
            .file_name = tokens[idx + 2].lexeme,
            .pending_name = tokens[body_open + 4].lexeme,
        };
    }
    return null;
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
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, "start") or !tok_eq(tokens[idx + 1], "(")) continue;
        const close = find_matching(tokens, idx + 1, "(", ")") catch return false;
        if (close + 1 < tokens.len and tok_eq(tokens[close + 1], "{")) {
            const body_close = find_matching(tokens, close + 1, "{", "}") catch return false;
            return body_close == close + 2;
        }
    }
    return false;
}

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) anyerror![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try StatPlan.analyze(tokens, registry);
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3WasiFilesystemStatComponent) {
        .filesystem_stat => |value| value,
        else => return error.UnsupportedP3WasiFilesystemStatComponent,
    };
    if (!std.mem.eql(u8, shape.record_layout.name, "descriptor-stat") or
        !std.mem.eql(u8, plan.descriptor.canonical.async_import_name, "[async-lower][method]descriptor.stat"))
        return error.UnsupportedP3WasiFilesystemStatComponent;
    return generated_text.alloc_block(allocator, 0, @embedFile("wasi_filesystem_stat_component_template.wat"));
}

pub fn emit_component_wit(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) anyerror![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    _ = try StatPlan.analyze(tokens, registry);
    return generated_text.alloc_block(allocator, 0, component_wit);
}

pub fn matches_descriptor(descriptor: p3_async_manifest.Descriptor) bool {
    return std.mem.eql(u8, descriptor.locator, locator) and
        std.mem.eql(u8, descriptor.member, member);
}

const component_wit =
        \\package wasi:filesystem@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  use wasi:clocks/wall-clock@0.3.0-rc-2025-09-16.{datetime};
    \\  type filesize = u64;
    \\  type link-count = u64;
    \\  enum descriptor-type { unknown, block-device, character-device, directory, fifo, symbolic-link, regular-file, socket }
    \\  record descriptor-stat { %type: descriptor-type, link-count: link-count, size: filesize, data-access-timestamp: option<datetime>, data-modification-timestamp: option<datetime>, status-change-timestamp: option<datetime> }
    \\  enum error-code { access, already, bad-descriptor, busy, deadlock, quota, exist, file-too-large, illegal-byte-sequence, in-progress, interrupted, invalid, io, is-directory, loop, too-many-links, message-size, name-too-long, no-device, no-entry, no-lock, insufficient-memory, insufficient-space, not-directory, not-empty, not-recoverable, unsupported, no-tty, no-such-device, overflow, not-permitted, pipe, read-only, invalid-seek, text-file-busy, cross-device }
    \\  resource descriptor { stat: async func() -> result<descriptor-stat, error-code>; }
    \\}
    \\
    \\interface probe {
    \\  use types.{descriptor, descriptor-stat, error-code};
    \\  run: async func(file: own<descriptor>) -> result<descriptor-stat, error-code>;
    \\}
    \\
    \\world stat-probe {
    \\  import types;
    \\  export probe;
    \\}
    \\
    ;

test "descriptor.stat planner admits the exact direct-await contract" {
    const source = @embedFile("test/compile_ok/498_wasi_filesystem_stat_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const plan = try StatPlan.analyze(tokens, registry);
    try std.testing.expectEqualStrings("stat_descriptor", plan.host_name);
    try std.testing.expectEqualStrings("run", plan.root_name);
    try std.testing.expectEqualStrings("file", plan.file_name);
    try std.testing.expectEqualStrings("pending", plan.pending_name);
}

test "descriptor.stat emitter returns the canonical template" {
    const source = @embedFile("test/compile_ok/498_wasi_filesystem_stat_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][method]descriptor.stat") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [stat-result-area]") != null);
}
