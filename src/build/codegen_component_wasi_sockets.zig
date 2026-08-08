const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_tokens = @import("sema_tokens.zig");
const socket_manifest = @import("p3_sockets_wit_manifest.zig");

const find_matching = sema_tokens.find_matching;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

pub const Protocol = enum { tcp, udp };

pub fn analyze(tokens: []const lexer.Token) !Protocol {
    if (has_async(tokens) or has_unadmitted_socket_host(tokens)) {
        return error.UnsupportedP3WasiSocketsCreateBindDropComponent;
    }

    const tcp = has_protocol(tokens, .tcp);
    const udp = has_protocol(tokens, .udp);
    if (tcp == udp) return error.UnsupportedP3WasiSocketsCreateBindDropComponent;

    const protocol: Protocol = if (tcp) .tcp else .udp;
    const run = find_run(tokens) orelse return error.UnsupportedP3WasiSocketsCreateBindDropComponent;
    const body = find_body(tokens, run) orelse return error.UnsupportedP3WasiSocketsCreateBindDropComponent;
    const end = find_matching(tokens, body, "{", "}") catch return error.UnsupportedP3WasiSocketsCreateBindDropComponent;
    if (!body_has_required_flow(tokens[body + 1 .. end], protocol)) {
        return error.UnsupportedP3WasiSocketsCreateBindDropComponent;
    }
    return protocol;
}

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    _ = program;
    _ = module_graph;
    try socket_manifest.validate();
    const protocol = try analyze(tokens);
    const wat = if (protocol == .tcp)
        @embedFile("wasi_sockets_tcp_create_bind_drop.core.wat")
    else
        @embedFile("wasi_sockets_udp_create_bind_drop.core.wat");
    return allocator.dupe(u8, wat);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    try socket_manifest.validate();
    _ = try analyze(tokens);
    return allocator.dupe(u8, @embedFile("wasi_sockets_create_bind_drop.wit"));
}

fn has_protocol(tokens: []const lexer.Token, protocol: Protocol) bool {
    return switch (protocol) {
        .tcp => has_host(tokens, "wasi:sockets/types@0.3.0", "tcp-socket.create") and
            has_host(tokens, "wasi:sockets/types@0.3.0", "tcp-socket.bind") and
            has_host(tokens, "wasi:sockets/types@0.3.0", "tcp-socket.drop") and
            has_resource(tokens, "sockets/types/tcp-socket") and
            has_lexeme(tokens, "TcpSocket") and has_lexeme(tokens, "IpSocketAddress"),
        .udp => has_host(tokens, "wasi:sockets/types@0.3.0", "udp-socket.create") and
            has_host(tokens, "wasi:sockets/types@0.3.0", "udp-socket.bind") and
            has_host(tokens, "wasi:sockets/types@0.3.0", "udp-socket.drop") and
            has_resource(tokens, "sockets/types/udp-socket") and
            has_lexeme(tokens, "UdpSocket") and has_lexeme(tokens, "IpSocketAddress"),
    };
}

fn body_has_required_flow(tokens: []const lexer.Token, protocol: Protocol) bool {
    return switch (protocol) {
        .tcp => has_lexeme(tokens, "host_tcp_create") and has_lexeme(tokens, "host_tcp_bind") and has_lexeme(tokens, "host_tcp_drop") and
            has_lexeme(tokens, "V4") and has_lexeme(tokens, "return"),
        .udp => has_lexeme(tokens, "host_udp_create") and has_lexeme(tokens, "host_udp_bind") and has_lexeme(tokens, "host_udp_drop") and
            has_lexeme(tokens, "V4") and has_lexeme(tokens, "return"),
    };
}

fn has_unadmitted_socket_host(tokens: []const lexer.Token) bool {
    var i: usize = 0;
    while (i + 7 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or
            !tok_eq(tokens[i + 3], "host_func") or !tok_eq(tokens[i + 4], "(") or
            tokens[i + 5].kind != .string or tokens[i + 7].kind != .string) continue;
        const locator = string_token_body(tokens[i + 5].lexeme) orelse continue;
        if (!std.mem.eql(u8, locator, "wasi:sockets/types@0.3.0")) continue;
        const member = string_token_body(tokens[i + 7].lexeme) orelse continue;
        if (!is_admitted_member(member)) return true;
    }
    return false;
}

fn is_admitted_member(member: []const u8) bool {
    return std.mem.eql(u8, member, "tcp-socket.create") or
        std.mem.eql(u8, member, "tcp-socket.bind") or
        std.mem.eql(u8, member, "tcp-socket.drop") or
        std.mem.eql(u8, member, "udp-socket.create") or
        std.mem.eql(u8, member, "udp-socket.bind") or
        std.mem.eql(u8, member, "udp-socket.drop");
}

fn has_host(tokens: []const lexer.Token, locator: []const u8, member: []const u8) bool {
    var i: usize = 0;
    while (i + 7 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or
            !tok_eq(tokens[i + 3], "host_func") or !tok_eq(tokens[i + 4], "(") or
            tokens[i + 5].kind != .string or tokens[i + 7].kind != .string) continue;
        const found_locator = string_token_body(tokens[i + 5].lexeme) orelse continue;
        const found_member = string_token_body(tokens[i + 7].lexeme) orelse continue;
        if (std.mem.eql(u8, found_locator, locator) and std.mem.eql(u8, found_member, member)) return true;
    }
    return false;
}

fn has_resource(tokens: []const lexer.Token, path: []const u8) bool {
    var i: usize = 0;
    while (i + 5 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or
            !tok_eq(tokens[i + 3], "wasi_resource") or !tok_eq(tokens[i + 4], "(") or
            tokens[i + 5].kind != .string) continue;
        const found_path = string_token_body(tokens[i + 5].lexeme) orelse continue;
        if (std.mem.eql(u8, found_path, path)) return true;
    }
    return false;
}

fn has_lexeme(tokens: []const lexer.Token, lexeme: []const u8) bool {
    for (tokens) |token| if (std.mem.eql(u8, token.lexeme, lexeme)) return true;
    return false;
}

fn has_async(tokens: []const lexer.Token) bool {
    return has_lexeme(tokens, "async") or has_lexeme(tokens, "await");
}

fn find_run(tokens: []const lexer.Token) ?usize {
    for (tokens, 0..) |token, idx| {
        if (std.mem.eql(u8, token.lexeme, "run") and idx + 1 < tokens.len and tok_eq(tokens[idx + 1], "(")) return idx;
    }
    return null;
}

fn find_body(tokens: []const lexer.Token, run: usize) ?usize {
    const close = find_matching(tokens, run + 1, "(", ")") catch return null;
    var i = close + 1;
    while (i < tokens.len and tokens[i].line == tokens[run].line) : (i += 1) {
        if (tok_eq(tokens[i], "->")) continue;
        if (tok_eq(tokens[i], "{")) return i;
    }
    return null;
}

test "socket emitter keeps protocol-specific imports and cleanup" {
    const source = @embedFile("wasi_sockets_tcp_fixture.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[static]tcp-socket.create") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[method]tcp-socket.bind") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]tcp-socket") != null);
}

test "socket create passes family before result area pointer" {
    const source = @embedFile("wasi_sockets_tcp_fixture.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat,
        "    i32.const 0\n    global.get $__wasi_result_area_base\n    call $tcp-create") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat,
        "    i32.load\n    i32.eqz\n    if (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat,
        "      global.get $__wasi_result_area_base\n      call $tcp-bind") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat,
        "      local.get $socket\n" ++
            "      i32.const 0\n" ++
            "      i32.const 0\n" ++
            "      i32.const 127\n" ++
            "      i32.const 0\n" ++
            "      i32.const 0\n" ++
            "      i32.const 1\n" ++
            "      i32.const 0\n" ++
            "      i32.const 0\n" ++
            "      i32.const 0\n" ++
            "      i32.const 0\n" ++
            "      i32.const 0\n" ++
            "      i32.const 0\n" ++
            "      global.get $__wasi_result_area_base\n" ++
            "      call $tcp-bind") != null);
}
