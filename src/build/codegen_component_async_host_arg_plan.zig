const std = @import("std");
const lexer = @import("lexer.zig");
const sema_tokens = @import("sema_tokens.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

pub const AsyncHostScalarArgPlan = struct {
    root_name: []const u8,
    helper_name: []const u8,
    host_name: []const u8,
    host_locator: []const u8,
    host_member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
    argument_name: []const u8,
    argument_value: u32,

    pub fn deinit(self: *AsyncHostScalarArgPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        allocator.free(self.helper_name);
        allocator.free(self.host_name);
        allocator.free(self.host_locator);
        allocator.free(self.host_member);
        allocator.free(self.async_import_module);
        allocator.free(self.async_import_name);
        allocator.free(self.argument_name);
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

pub fn analyze(allocator: std.mem.Allocator, tokens: []const lexer.Token) !AsyncHostScalarArgPlan {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);

    const host = find_host_binding(tokens, registry) orelse return error.UnsupportedP3AsyncHostArgComponent;
    const helper = find_function(tokens, "helper") orelse return error.UnsupportedP3AsyncHostArgComponent;
    const root = find_function(tokens, "run") orelse return error.UnsupportedP3AsyncHostArgComponent;
    const argument_name = helper_argument_name(tokens, helper) orelse return error.UnsupportedP3AsyncHostArgComponent;
    const argument_value = root_argument_value(tokens, root) orelse return error.UnsupportedP3AsyncHostArgComponent;

    if (helper.is_async or root.is_async or
        !signature_is_unit(root) or
        !helper_signature_is_scalar_unit(tokens, helper) or
        !helper_body_is_exact(tokens, helper, host.name, argument_name) or
        !root_body_is_exact(tokens, root, argument_value) or
        top_level_function_count(tokens) != 2 or
        count_top_level_functions(tokens, "helper") != 1 or
        count_top_level_functions(tokens, "run") != 1 or
        count_token_pair(tokens, "@", "host_func") != 0 or
        count_token_pair(tokens, "@", "host") != 0 or
        count_token_pair(tokens, "@", "host_async_func") != 1 or
        count_token_pair(tokens, "@", "async") != 1 or
        count_token_pair(tokens, "@", "await") != 2 or
        count_token_pair(tokens, "@", "cancel") != 0)
    {
        return error.UnsupportedP3AsyncHostArgComponent;
    }

    const root_name = try allocator.dupe(u8, root.name);
    errdefer allocator.free(root_name);
    const helper_name = try allocator.dupe(u8, helper.name);
    errdefer allocator.free(helper_name);
    const host_name = try allocator.dupe(u8, host.name);
    errdefer allocator.free(host_name);
    const host_locator = try allocator.dupe(u8, host.locator);
    errdefer allocator.free(host_locator);
    const host_member = try allocator.dupe(u8, host.member);
    errdefer allocator.free(host_member);
    const async_import_module = try allocator.dupe(u8, host.descriptor.canonical.async_import_module);
    errdefer allocator.free(async_import_module);
    const async_import_name = try allocator.dupe(u8, host.descriptor.canonical.async_import_name);
    errdefer allocator.free(async_import_name);
    const owned_argument_name = try allocator.dupe(u8, argument_name);
    errdefer allocator.free(owned_argument_name);

    return .{
        .root_name = root_name,
        .helper_name = helper_name,
        .host_name = host_name,
        .host_locator = host_locator,
        .host_member = host_member,
        .async_import_module = async_import_module,
        .async_import_name = async_import_name,
        .argument_name = owned_argument_name,
        .argument_value = argument_value,
    };
}

fn find_host_binding(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?HostBinding {
    var found: ?HostBinding = null;
    var idx: usize = 0;
    while (idx + 16 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 1], "=") or
            !sema_tokens.tok_eq(tokens[idx + 2], "@") or !sema_tokens.tok_eq(tokens[idx + 3], "host_async_func") or
            !sema_tokens.tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !sema_tokens.tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !sema_tokens.tok_eq(tokens[idx + 8], ",") or !sema_tokens.tok_eq(tokens[idx + 9], "(") or
            tokens[idx + 10].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 10], "u32") or !sema_tokens.tok_eq(tokens[idx + 11], ")") or
            !sema_tokens.tok_eq(tokens[idx + 12], "-") or !sema_tokens.tok_eq(tokens[idx + 13], ">") or
            !sema_tokens.tok_eq(tokens[idx + 14], "nil") or !sema_tokens.tok_eq(tokens[idx + 15], ")")) continue;

        const locator = sema_tokens.string_token_body(tokens[idx + 5].lexeme) orelse continue;
        const member = sema_tokens.string_token_body(tokens[idx + 7].lexeme) orelse continue;
        const descriptor = registry.find(locator, member) orelse continue;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse continue) {
            .async_host_scalar_argument => {},
            else => continue,
        }
        if (found != null) return null;
        found = .{ .name = tokens[idx].lexeme, .locator = locator, .member = member, .descriptor = descriptor };
    }
    return found;
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
        if (params_close + 4 >= tokens.len or !sema_tokens.tok_eq(tokens[params_close + 1], "-") or
            !sema_tokens.tok_eq(tokens[params_close + 2], ">") or tokens[params_close + 3].kind != .ident or
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

fn helper_signature_is_scalar_unit(tokens: []const lexer.Token, function: FunctionDecl) bool {
    return function.params_close == function.params_open + 3 and tokens[function.params_open + 1].kind == .ident and
        tokens[function.params_open + 2].kind == .ident and std.mem.eql(u8, tokens[function.params_open + 2].lexeme, "u32") and
        std.mem.eql(u8, function.result_type, "nil");
}

fn helper_argument_name(tokens: []const lexer.Token, function: FunctionDecl) ?[]const u8 {
    if (!helper_signature_is_scalar_unit(tokens, function)) return null;
    return tokens[function.params_open + 1].lexeme;
}

fn signature_is_unit(function: FunctionDecl) bool {
    return function.params_close == function.params_open + 1 and std.mem.eql(u8, function.result_type, "nil");
}

fn helper_body_is_exact(tokens: []const lexer.Token, function: FunctionDecl, host_name: []const u8, argument_name: []const u8) bool {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len != 15) return false;
    return ident_eq(body[0], "pending") and ident_eq(body[1], "Future") and sema_tokens.tok_eq(body[2], "<") and
        ident_eq(body[3], "nil") and sema_tokens.tok_eq(body[4], ">") and sema_tokens.tok_eq(body[5], "=") and
        ident_eq(body[6], host_name) and sema_tokens.tok_eq(body[7], "(") and ident_eq(body[8], argument_name) and
        sema_tokens.tok_eq(body[9], ")") and sema_tokens.tok_eq(body[10], "@") and ident_eq(body[11], "await") and
        sema_tokens.tok_eq(body[12], "(") and ident_eq(body[13], "pending") and sema_tokens.tok_eq(body[14], ")");
}

fn root_body_is_exact(tokens: []const lexer.Token, function: FunctionDecl, argument_value: u32) bool {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len != 19 or !ident_eq(body[0], "child") or !ident_eq(body[1], "Future") or
        !sema_tokens.tok_eq(body[2], "<") or !ident_eq(body[3], "nil") or !sema_tokens.tok_eq(body[4], ">") or
        !sema_tokens.tok_eq(body[5], "=") or !sema_tokens.tok_eq(body[6], "@") or !ident_eq(body[7], "async") or
        !sema_tokens.tok_eq(body[8], "(") or !ident_eq(body[9], "helper") or !sema_tokens.tok_eq(body[10], "(") or
        body[11].kind != .number or !sema_tokens.tok_eq(body[12], ")") or !sema_tokens.tok_eq(body[13], ")") or
        !sema_tokens.tok_eq(body[14], "@") or !ident_eq(body[15], "await") or !sema_tokens.tok_eq(body[16], "(") or
        !ident_eq(body[17], "child") or !sema_tokens.tok_eq(body[18], ")")) return false;
    return parse_u32_literal(body[11]) == argument_value;
}

fn root_argument_value(tokens: []const lexer.Token, function: FunctionDecl) ?u32 {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len < 13 or body[11].kind != .number) return null;
    return parse_u32_literal(body[11]);
}

fn parse_u32_literal(token: lexer.Token) ?u32 {
    if (token.kind != .number) return null;
    return std.fmt.parseInt(u32, token.lexeme, 10) catch null;
}

fn top_level_function_count(tokens: []const lexer.Token) usize {
    var depth: usize = 0;
    var count: usize = 0;
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
        if (depth == 0 and tokens[idx].kind == .ident and sema_tokens.tok_eq(tokens[idx + 1], "(") and
            (idx == 0 or !sema_tokens.tok_eq(tokens[idx - 1], "@"))) count += 1;
    }
    return count;
}

fn count_top_level_functions(tokens: []const lexer.Token, name: []const u8) usize {
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
            sema_tokens.tok_eq(tokens[idx + 1], "(")) count += 1;
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

fn ident_eq(token: lexer.Token, expected: []const u8) bool {
    return token.kind == .ident and std.mem.eql(u8, token.lexeme, expected);
}
