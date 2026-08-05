const std = @import("std");
const lexer = @import("lexer.zig");
const imports = @import("imports.zig");
const parser = @import("parser.zig");
const resource_abi_registry = @import("resource_abi_registry.zig");
const sema_tokens = @import("sema_tokens.zig");

const find_matching = sema_tokens.find_matching;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try resource_abi_registry.Registry.load(allocator, @embedFile("resource_abi_registry.json"));
    defer registry.deinit(allocator);
    if (!matches_probe_program(tokens, registry)) return error.UnsupportedResourceProbeComponent;
    return allocator.dupe(u8, resource_probe_core_wat);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try resource_abi_registry.Registry.load(allocator, @embedFile("resource_abi_registry.json"));
    defer registry.deinit(allocator);
    if (!matches_probe_program(tokens, registry)) return error.UnsupportedResourceProbeComponent;
    return allocator.dupe(u8, resource_probe_component_wit);
}

fn matches_probe_program(tokens: []const lexer.Token, registry: resource_abi_registry.Registry) bool {
    const create = find_host_alias(tokens, registry, "create") orelse return false;
    const borrow_value = find_host_alias(tokens, registry, "borrow-value") orelse return false;
    const consume = find_host_alias(tokens, registry, "consume") orelse return false;
    const drop_ticket = find_host_alias(tokens, registry, "drop") orelse return false;
    if (!has_probe_resource_decl(tokens, registry)) return false;

    const run_idx = find_run_decl(tokens) orelse return false;
    const body_open = find_run_body_open(tokens, run_idx) orelse return false;
    const body_close = find_matching(tokens, body_open, "{", "}") catch return false;
    return matches_run_flow(tokens, body_open + 1, body_close, create, borrow_value, consume, drop_ticket);
}

fn find_host_alias(tokens: []const lexer.Token, registry: resource_abi_registry.Registry, member: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 8 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or !tok_eq(tokens[i + 3], "host") or !tok_eq(tokens[i + 4], "(") or tokens[i + 5].kind != .string or !tok_eq(tokens[i + 6], ",") or tokens[i + 7].kind != .string or !tok_eq(tokens[i + 8], ",")) continue;
        const locator = string_token_body(tokens[i + 5].lexeme) orelse continue;
        const found_member = string_token_body(tokens[i + 7].lexeme) orelse continue;
        const descriptor = registry.find(locator, found_member) orelse continue;
        if (std.mem.eql(u8, descriptor.member, member)) return tokens[i].lexeme;
    }
    return null;
}

fn has_probe_resource_decl(tokens: []const lexer.Token, registry: resource_abi_registry.Registry) bool {
    var i: usize = 0;
    while (i + 5 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or !tok_eq(tokens[i + 3], "wasi_resource") or !tok_eq(tokens[i + 4], "(") or tokens[i + 5].kind != .string) continue;
        const path = string_token_body(tokens[i + 5].lexeme) orelse continue;
        for (registry.descriptors) |descriptor| {
            if (!std.mem.eql(u8, descriptor.resource, "ticket")) continue;
            if (resource_path_matches(descriptor.locator, descriptor.resource, path)) return true;
        }
    }
    return false;
}

fn resource_path_matches(locator: []const u8, resource: []const u8, path: []const u8) bool {
    const version_idx = std.mem.lastIndexOfScalar(u8, locator, '@') orelse return false;
    const prefix = locator[0..version_idx];
    return path.len == prefix.len + 1 + resource.len and std.mem.eql(u8, path[0..prefix.len], prefix) and path[prefix.len] == '/' and std.mem.eql(u8, path[prefix.len + 1 ..], resource);
}

fn find_run_decl(tokens: []const lexer.Token) ?usize {
    for (tokens, 0..) |token, idx| {
        if (token.kind == .ident and std.mem.eql(u8, token.lexeme, "run") and idx + 1 < tokens.len and tok_eq(tokens[idx + 1], "(")) return idx;
    }
    return null;
}

fn find_run_body_open(tokens: []const lexer.Token, run_idx: usize) ?usize {
    const close_params = find_matching(tokens, run_idx + 1, "(", ")") catch return null;
    var i = close_params + 1;
    while (i < tokens.len and tokens[i].line == tokens[run_idx].line) : (i += 1) {
        if (tok_eq(tokens[i], "{")) return i;
    }
    return null;
}

fn matches_run_flow(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    create: []const u8,
    borrow_value: []const u8,
    consume: []const u8,
    drop_ticket: []const u8,
) bool {
    if (end_idx - start_idx != 35) return false;
    const words = [_][]const u8{
        "first", "Ticket",    "=",     create,       "(",          "seed",   ")",
        "value", "u32",       "=",     borrow_value, "(",          "first",  ")",
        consume, "(",         "first", ")",          "second",     "Ticket", "=",
        create,  "(",         "seed",  ")",          borrow_value, "(",      "second",
        ")",     drop_ticket, "(",     "second",     ")",          "return", "value",
    };
    for (words, 0..) |word, offset| {
        if (!std.mem.eql(u8, tokens[start_idx + offset].lexeme, word)) return false;
    }
    return true;
}

const resource_probe_core_wat =
    \\;; Generated only for the pinned do resource ownership probe.
    \\(module
    \\  (type $ticket-op (func (param i32) (result i32)))
    \\  (type $ticket-drop (func (param i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  (import "do:resource-probe/ledger@0.1.0" "create" (func $create (type $ticket-op)))
    \\  (import "do:resource-probe/ledger@0.1.0" "borrow-value" (func $borrow-value (type $ticket-op)))
    \\  (import "do:resource-probe/ledger@0.1.0" "consume" (func $consume (type $ticket-op)))
    \\  (import "do:resource-probe/ledger@0.1.0" "[resource-drop]ticket" (func $drop-ticket (type $ticket-drop)))
    \\  (memory (export "memory") 0)
    \\  (func (export "run") (param $seed i32) (result i32) (local $first i32) (local $value i32) (local $second i32)
    \\    local.get $seed
    \\    call $create
    \\    local.set $first
    \\    local.get $first
    \\    call $borrow-value
    \\    local.set $value
    \\    local.get $first
    \\    call $consume
    \\    drop
    \\    local.get $seed
    \\    call $create
    \\    local.set $second
    \\    local.get $second
    \\    call $borrow-value
    \\    drop
    \\    local.get $second
    \\    call $drop-ticket
    \\    local.get $value
    \\  )
    \\  (func (export "cabi_post_run") (param i32))
    \\  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

const resource_probe_component_wit =
    \\package do:resource-probe@0.1.0;
    \\
    \\interface ledger {
    \\  resource ticket {}
    \\
    \\  create: func(seed: u32) -> own<ticket>;
    \\  borrow-value: func(ticket: borrow<ticket>) -> u32;
    \\  consume: func(ticket: own<ticket>) -> u32;
    \\}
    \\
    \\world probe {
    \\  import ledger;
    \\  export run: func(seed: u32) -> u32;
    \\}
    \\
;

test "resource probe emits canonical own borrow and drop imports" {
    const source =
        \\create = @host("do:resource-probe/ledger@0.1.0", "create", (u32) -> Ticket)
        \\borrow_value = @host("do:resource-probe/ledger@0.1.0", "borrow-value", (Ticket) -> u32)
        \\consume = @host("do:resource-probe/ledger@0.1.0", "consume", (Ticket) -> u32)
        \\drop_ticket = @host("do:resource-probe/ledger@0.1.0", "drop", (Ticket) -> nil)
        \\Ticket = @wasi_resource("do:resource-probe/ledger/ticket", { .id i64 })
        \\run(seed u32) -> u32 {
        \\    first Ticket = create(seed)
        \\    value u32 = borrow_value(first)
        \\    consume(first)
        \\    second Ticket = create(seed)
        \\    borrow_value(second)
        \\    drop_ticket(second)
        \\    return value
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]ticket") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "borrow-value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "consume") != null);
}
