const std = @import("std");
const lexer = @import("lexer.zig");
const sema_tokens = @import("sema_tokens.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

pub const FutureOwnedPlan = struct {
    registry: p3_async_manifest.Registry,
    descriptor: p3_async_manifest.Descriptor,
    root_name: []const u8,
    mode_name: []const u8,
    host_name: []const u8,
    ticket_type_name: []const u8,
    future_name: []const u8,
    await_name: []const u8,
    host_locator: []const u8,
    host_member: []const u8,
    resource_path: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
    drop_import: []const u8,
    payload_offset: u32,
    resource_offset: u32,
    presence_offset: u32,

    pub fn deinit(self: *FutureOwnedPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        allocator.free(self.mode_name);
        allocator.free(self.host_name);
        allocator.free(self.ticket_type_name);
        allocator.free(self.future_name);
        allocator.free(self.await_name);
        allocator.free(self.host_locator);
        allocator.free(self.host_member);
        allocator.free(self.resource_path);
        allocator.free(self.async_import_module);
        allocator.free(self.async_import_name);
        allocator.free(self.drop_import);
        self.registry.deinit(allocator);
        self.* = undefined;
    }
};

const FunctionDecl = struct {
    name: []const u8,
    params_open: usize,
    params_close: usize,
    body_open: usize,
    body_close: usize,
    result_type: []const u8,
    is_async: bool,
};

const HostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
    descriptor: p3_async_manifest.Descriptor,
};

const ResourceDecl = struct {
    type_name: []const u8,
    path: []const u8,
};

pub fn analyze(allocator: std.mem.Allocator, tokens: []const lexer.Token) !FutureOwnedPlan {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    errdefer registry.deinit(allocator);

    const host = find_host_binding(tokens, registry) orelse return error.UnsupportedP3OwnedFutureComponent;
    const resource = find_resource_decl(tokens) orelse return error.UnsupportedP3OwnedFutureComponent;
    const root = find_function(tokens, "run") orelse return error.UnsupportedP3OwnedFutureComponent;
    const start = find_empty_start(tokens) orelse return error.UnsupportedP3OwnedFutureComponent;
    _ = start;

    const owned = switch (p3_async_manifest.lowering_shape(host.descriptor) orelse return error.UnsupportedP3OwnedFutureComponent) {
        .future_owned_resource => |value| value,
        else => return error.UnsupportedP3OwnedFutureComponent,
    };

    if (root.is_async or
        !root_signature_is_exact(tokens, root) or
        !resource_is_exact(resource) or
        !root_body_is_exact(tokens, root, host.name) or
        count_top_level_functions(tokens) != 2 or
        count_named_top_level_functions(tokens, "run") != 1 or
        count_named_top_level_functions(tokens, "start") != 1 or
        count_token_pair(tokens, "@", "host_func") != 1 or
        count_token_pair(tokens, "@", "wasi_resource") != 1 or
        count_token_pair(tokens, "@", "await") != 1 or
        count_token_pair(tokens, "@", "cancel") != 0 or
        count_token_pair(tokens, "@", "async") != 0)
    {
        return error.UnsupportedP3OwnedFutureComponent;
    }

    const root_name = try allocator.dupe(u8, root.name);
    errdefer allocator.free(root_name);
    const mode_name = try allocator.dupe(u8, root_param_name(tokens, root) orelse return error.UnsupportedP3OwnedFutureComponent);
    errdefer allocator.free(mode_name);
    const host_name = try allocator.dupe(u8, host.name);
    errdefer allocator.free(host_name);
    const ticket_type_name = try allocator.dupe(u8, resource.type_name);
    errdefer allocator.free(ticket_type_name);
    const body = tokens[root.body_open + 1 .. root.body_close];
    const future_name = try allocator.dupe(u8, body[0].lexeme);
    errdefer allocator.free(future_name);
    const await_name = try allocator.dupe(u8, body[9].lexeme);
    errdefer allocator.free(await_name);
    const host_locator = try allocator.dupe(u8, host.locator);
    errdefer allocator.free(host_locator);
    const host_member = try allocator.dupe(u8, host.member);
    errdefer allocator.free(host_member);
    const resource_path = try allocator.dupe(u8, resource.path);
    errdefer allocator.free(resource_path);
    const async_import_module = try allocator.dupe(u8, host.descriptor.canonical.async_import_module);
    errdefer allocator.free(async_import_module);
    const async_import_name = try allocator.dupe(u8, host.descriptor.canonical.async_import_name);
    errdefer allocator.free(async_import_name);
    const drop_import = try allocator.dupe(u8, owned.drop_import);
    errdefer allocator.free(drop_import);

    return .{
        .registry = registry,
        .descriptor = host.descriptor,
        .root_name = root_name,
        .mode_name = mode_name,
        .host_name = host_name,
        .ticket_type_name = ticket_type_name,
        .future_name = future_name,
        .await_name = await_name,
        .host_locator = host_locator,
        .host_member = host_member,
        .resource_path = resource_path,
        .async_import_module = async_import_module,
        .async_import_name = async_import_name,
        .drop_import = drop_import,
        .payload_offset = owned.payload_offset,
        .resource_offset = owned.resource_offset,
        .presence_offset = owned.presence_offset,
    };
}

fn find_host_binding(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?HostBinding {
    var found: ?HostBinding = null;
    var idx: usize = 0;
    while (idx + 17 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 1], "=") or
            !sema_tokens.tok_eq(tokens[idx + 2], "@") or !sema_tokens.tok_eq(tokens[idx + 3], "host_func") or
            !sema_tokens.tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !sema_tokens.tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !sema_tokens.tok_eq(tokens[idx + 8], ",") or !sema_tokens.tok_eq(tokens[idx + 9], "(") or
            !sema_tokens.tok_eq(tokens[idx + 10], ")") or !sema_tokens.tok_eq(tokens[idx + 11], "-") or
            !sema_tokens.tok_eq(tokens[idx + 12], ">") or !sema_tokens.tok_eq(tokens[idx + 13], "Future") or
            !sema_tokens.tok_eq(tokens[idx + 14], "<") or tokens[idx + 15].kind != .ident or
            !sema_tokens.tok_eq(tokens[idx + 16], ">") or !sema_tokens.tok_eq(tokens[idx + 17], ")")) continue;

        const locator = sema_tokens.string_token_body(tokens[idx + 5].lexeme) orelse continue;
        const member = sema_tokens.string_token_body(tokens[idx + 7].lexeme) orelse continue;
        const descriptor = registry.find(locator, member) orelse continue;
        if (found != null) return null;
        found = .{
            .name = tokens[idx].lexeme,
            .locator = locator,
            .member = member,
            .descriptor = descriptor,
        };
    }
    return found;
}

fn find_resource_decl(tokens: []const lexer.Token) ?ResourceDecl {
    var found: ?ResourceDecl = null;
    var idx: usize = 0;
    while (idx + 5 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 1], "=") or
            !sema_tokens.tok_eq(tokens[idx + 2], "@") or !sema_tokens.tok_eq(tokens[idx + 3], "wasi_resource") or
            !sema_tokens.tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string) continue;
        const close = sema_tokens.find_matching(tokens, idx + 4, "(", ")") catch continue;
        if (close <= idx + 5) continue;
        const path = sema_tokens.string_token_body(tokens[idx + 5].lexeme) orelse continue;
        if (found != null) return null;
        found = .{ .type_name = tokens[idx].lexeme, .path = path };
        idx = close;
    }
    return found;
}

fn resource_is_exact(resource: ResourceDecl) bool {
    return std.mem.eql(u8, resource.type_name, "Ticket") and
        std.mem.eql(u8, resource.path, "do:future-owned-canonical/source/ticket");
}

fn find_function(tokens: []const lexer.Token, name: []const u8) ?FunctionDecl {
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx + 6 < tokens.len) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (sema_tokens.tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, name) or
            !sema_tokens.tok_eq(tokens[idx + 1], "(")) continue;

        const params_close = sema_tokens.find_matching(tokens, idx + 1, "(", ")") catch return null;
        if (params_close + 4 >= tokens.len or
            !sema_tokens.tok_eq(tokens[params_close + 1], "-") or
            !sema_tokens.tok_eq(tokens[params_close + 2], ">") or
            tokens[params_close + 3].kind != .ident or
            !sema_tokens.tok_eq(tokens[params_close + 4], "{")) continue;
        const body_close = sema_tokens.find_matching(tokens, params_close + 4, "{", "}") catch return null;
        return .{
            .name = tokens[idx].lexeme,
            .params_open = idx + 1,
            .params_close = params_close,
            .body_open = params_close + 4,
            .body_close = body_close,
            .result_type = tokens[params_close + 3].lexeme,
            .is_async = idx > 0 and sema_tokens.tok_eq(tokens[idx - 1], "async"),
        };
    }
    return null;
}

fn find_empty_start(tokens: []const lexer.Token) ?usize {
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx + 4 < tokens.len) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (sema_tokens.tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and tokens[idx].kind == .ident and std.mem.eql(u8, tokens[idx].lexeme, "start") and
            sema_tokens.tok_eq(tokens[idx + 1], "(") and sema_tokens.tok_eq(tokens[idx + 2], ")") and
            sema_tokens.tok_eq(tokens[idx + 3], "{") and sema_tokens.tok_eq(tokens[idx + 4], "}")) return idx;
    }
    return null;
}

fn root_signature_is_exact(tokens: []const lexer.Token, function: FunctionDecl) bool {
    return function.params_close == function.params_open + 3 and
        ident_eq(tokens[function.params_open + 1], "mode") and
        ident_eq(tokens[function.params_open + 2], "u32") and
        std.mem.eql(u8, function.result_type, "nil");
}

fn root_param_name(tokens: []const lexer.Token, function: FunctionDecl) ?[]const u8 {
    if (!root_signature_is_exact(tokens, function)) return null;
    return tokens[function.params_open + 1].lexeme;
}

fn root_body_is_exact(tokens: []const lexer.Token, function: FunctionDecl, host_name: []const u8) bool {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len != 17) return false;
    return ident_eq(body[0], "pending") and ident_eq(body[1], "Future") and
        sema_tokens.tok_eq(body[2], "<") and ident_eq(body[3], "Ticket") and
        sema_tokens.tok_eq(body[4], ">") and sema_tokens.tok_eq(body[5], "=") and
        ident_eq(body[6], host_name) and sema_tokens.tok_eq(body[7], "(") and
        sema_tokens.tok_eq(body[8], ")") and ident_eq(body[9], "ticket") and
        ident_eq(body[10], "Ticket") and sema_tokens.tok_eq(body[11], "=") and
        sema_tokens.tok_eq(body[12], "@") and ident_eq(body[13], "await") and
        sema_tokens.tok_eq(body[14], "(") and ident_eq(body[15], "pending") and
        sema_tokens.tok_eq(body[16], ")");
}

fn ident_eq(token: lexer.Token, expected: []const u8) bool {
    return token.kind == .ident and std.mem.eql(u8, token.lexeme, expected);
}

fn count_top_level_functions(tokens: []const lexer.Token) usize {
    var depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (sema_tokens.tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and tokens[idx].kind == .ident and sema_tokens.tok_eq(tokens[idx + 1], "(") and
            (idx == 0 or !sema_tokens.tok_eq(tokens[idx - 1], "@"))) count += 1;
    }
    return count;
}

fn count_named_top_level_functions(tokens: []const lexer.Token, name: []const u8) usize {
    var depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (sema_tokens.tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and tokens[idx].kind == .ident and std.mem.eql(u8, tokens[idx].lexeme, name) and
            sema_tokens.tok_eq(tokens[idx + 1], "(") and (idx == 0 or !sema_tokens.tok_eq(tokens[idx - 1], "@"))) count += 1;
    }
    return count;
}

fn count_token_pair(tokens: []const lexer.Token, first: []const u8, second: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (sema_tokens.tok_eq(token, first) and idx + 1 < tokens.len and sema_tokens.tok_eq(tokens[idx + 1], second)) count += 1;
    }
    return count;
}
