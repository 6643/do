const std = @import("std");
const lexer = @import("lexer.zig");
const sema_tokens = @import("sema_tokens.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

pub const ChildState = enum {
    host_pending,
};

pub const ParentResumeState = enum {
    child_complete,
};

pub const GuestAsyncCallPlan = struct {
    root_name: []const u8,
    helper_name: []const u8,
    host_name: []const u8,
    host_locator: []const u8,
    host_member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
    argument_name: []const u8,
    argument_value: ?u32,
    child_state: ChildState,
    parent_resume_state: ParentResumeState,

    pub fn deinit(self: *GuestAsyncCallPlan, allocator: std.mem.Allocator) void {
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

/// Admit the first root-owned local-frame async-call shape only.
///
/// The parser is intentionally token-exact. It does not infer async behavior
/// from a function name, and it requires the registered private host
/// descriptor before producing a plan.
pub fn analyze(allocator: std.mem.Allocator, tokens: []const lexer.Token) !GuestAsyncCallPlan {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);

    const host = find_host_binding(tokens, registry) orelse return error.UnsupportedP3AsyncCallComponent;
    const helper = find_function(tokens, "helper") orelse return error.UnsupportedP3AsyncCallComponent;
    const root = find_function(tokens, "run") orelse return error.UnsupportedP3AsyncCallComponent;
    const scalar_argument = find_scalar_argument(tokens, helper);
    const helper_is_unit = signature_is_unit(helper);
    const helper_is_scalar = scalar_argument != null;
    const scalar_value = if (helper_is_scalar) scalar_root_value(tokens, root) else null;
    const root_body_valid = if (helper_is_scalar)
        scalar_value != null
    else
        root_body_is_exact(tokens, root);

    if (helper.is_async or root.is_async or
        (!helper_is_unit and !helper_is_scalar) or !signature_is_unit(root) or
        !helper_body_is_exact(tokens, helper, host.name) or
        !root_body_valid or
        count_top_level_functions(tokens, "helper") != 1 or
        count_top_level_functions(tokens, "run") != 1 or
        count_token_pair(tokens, "@", "host_async_func") != 1 or
        count_token_pair(tokens, "@", "async") != 1 or
        count_token_pair(tokens, "@", "await") != 2 or
        count_token_pair(tokens, "@", "cancel") != 0)
    {
        return error.UnsupportedP3AsyncCallComponent;
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
    const argument_name = try allocator.dupe(u8, if (scalar_argument) |argument| argument.name else "");
    errdefer allocator.free(argument_name);

    return .{
        .root_name = root_name,
        .helper_name = helper_name,
        .host_name = host_name,
        .host_locator = host_locator,
        .host_member = host_member,
        .async_import_module = async_import_module,
        .async_import_name = async_import_name,
        .argument_name = argument_name,
        .argument_value = scalar_value,
        .child_state = .host_pending,
        .parent_resume_state = .child_complete,
    };
}

fn find_host_binding(
    tokens: []const lexer.Token,
    registry: p3_async_manifest.Registry,
) ?HostBinding {
    var found: ?HostBinding = null;
    var idx: usize = 0;
    while (idx + 14 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 1], "=") or
            !sema_tokens.tok_eq(tokens[idx + 2], "@") or !sema_tokens.tok_eq(tokens[idx + 3], "host_async_func") or
            !sema_tokens.tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !sema_tokens.tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !sema_tokens.tok_eq(tokens[idx + 8], ",") or !sema_tokens.tok_eq(tokens[idx + 9], "(") or
            !sema_tokens.tok_eq(tokens[idx + 10], ")") or !sema_tokens.tok_eq(tokens[idx + 11], "-") or
            !sema_tokens.tok_eq(tokens[idx + 12], ">") or !sema_tokens.tok_eq(tokens[idx + 13], "nil") or
            !sema_tokens.tok_eq(tokens[idx + 14], ")")) continue;

        const locator = sema_tokens.string_token_body(tokens[idx + 5].lexeme) orelse continue;
        const member = sema_tokens.string_token_body(tokens[idx + 7].lexeme) orelse continue;
        const descriptor = registry.find(locator, member) orelse continue;
        if (!valid_host_descriptor(descriptor)) continue;
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

fn valid_host_descriptor(descriptor: p3_async_manifest.Descriptor) bool {
    return std.mem.eql(u8, descriptor.locator, "do:generic-async-call-probe/host@0.1.0") and
        std.mem.eql(u8, descriptor.member, "work") and
        std.mem.eql(u8, descriptor.effect, "async") and
        descriptor.params.len == 0 and
        std.mem.eql(u8, descriptor.result, "nil") and
        descriptor.resource == null and
        descriptor.canonical.core_params.len == 0 and
        descriptor.canonical.core_results.len == 0 and
        descriptor.canonical.completion_params.len == 0 and
        std.mem.eql(u8, descriptor.canonical.completion, "task-return") and
        std.mem.eql(u8, descriptor.canonical.async_import_module, descriptor.locator) and
        std.mem.eql(u8, descriptor.canonical.async_import_name, "[async-lower]work");
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
        if (params_close + 3 >= tokens.len or
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

fn signature_is_unit(function: FunctionDecl) bool {
    return function.params_close == function.params_open + 1 and
        std.mem.eql(u8, function.result_type, "nil");
}

const ScalarArgument = struct {
    name: []const u8,
};

fn find_scalar_argument(tokens: []const lexer.Token, function: FunctionDecl) ?ScalarArgument {
    if (function.params_close != function.params_open + 3 or
        tokens[function.params_open + 1].kind != .ident or
        tokens[function.params_open + 2].kind != .ident or
        !std.mem.eql(u8, tokens[function.params_open + 2].lexeme, "u32") or
        !std.mem.eql(u8, function.result_type, "nil")) return null;

    return .{
        .name = tokens[function.params_open + 1].lexeme,
    };
}

fn scalar_root_value(tokens: []const lexer.Token, function: FunctionDecl) ?u32 {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len != 19 or
        !ident_eq(body[0], "child") or !ident_eq(body[1], "Future") or
        !sema_tokens.tok_eq(body[2], "<") or !ident_eq(body[3], "nil") or
        !sema_tokens.tok_eq(body[4], ">") or !sema_tokens.tok_eq(body[5], "=") or
        !sema_tokens.tok_eq(body[6], "@") or !ident_eq(body[7], "async") or
        !sema_tokens.tok_eq(body[8], "(") or !ident_eq(body[9], "helper") or
        !sema_tokens.tok_eq(body[10], "(") or body[11].kind != .number or
        !sema_tokens.tok_eq(body[12], ")") or !sema_tokens.tok_eq(body[13], ")") or
        !sema_tokens.tok_eq(body[14], "@") or !ident_eq(body[15], "await") or
        !sema_tokens.tok_eq(body[16], "(") or !ident_eq(body[17], "child") or
        !sema_tokens.tok_eq(body[18], ")")) return null;

    return std.fmt.parseInt(u32, body[11].lexeme, 10) catch null;
}

fn helper_body_is_exact(tokens: []const lexer.Token, function: FunctionDecl, host_name: []const u8) bool {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len != 14) return false;
    return ident_eq(body[0], "pending") and ident_eq(body[1], "Future") and
        sema_tokens.tok_eq(body[2], "<") and ident_eq(body[3], "nil") and
        sema_tokens.tok_eq(body[4], ">") and sema_tokens.tok_eq(body[5], "=") and
        ident_eq(body[6], host_name) and sema_tokens.tok_eq(body[7], "(") and
        sema_tokens.tok_eq(body[8], ")") and sema_tokens.tok_eq(body[9], "@") and
        ident_eq(body[10], "await") and sema_tokens.tok_eq(body[11], "(") and
        ident_eq(body[12], "pending") and sema_tokens.tok_eq(body[13], ")");
}

fn root_body_is_exact(tokens: []const lexer.Token, function: FunctionDecl) bool {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len != 18) return false;
    return ident_eq(body[0], "child") and ident_eq(body[1], "Future") and
        sema_tokens.tok_eq(body[2], "<") and ident_eq(body[3], "nil") and
        sema_tokens.tok_eq(body[4], ">") and sema_tokens.tok_eq(body[5], "=") and
        sema_tokens.tok_eq(body[6], "@") and ident_eq(body[7], "async") and
        sema_tokens.tok_eq(body[8], "(") and ident_eq(body[9], "helper") and
        sema_tokens.tok_eq(body[10], "(") and sema_tokens.tok_eq(body[11], ")") and
        sema_tokens.tok_eq(body[12], ")") and sema_tokens.tok_eq(body[13], "@") and
        ident_eq(body[14], "await") and sema_tokens.tok_eq(body[15], "(") and
        ident_eq(body[16], "child") and sema_tokens.tok_eq(body[17], ")");
}

fn ident_eq(token: lexer.Token, expected: []const u8) bool {
    return token.kind == .ident and std.mem.eql(u8, token.lexeme, expected);
}

fn count_top_level_functions(tokens: []const lexer.Token, name: []const u8) usize {
    var depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (sema_tokens.tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or idx + 1 >= tokens.len or tokens[idx].kind != .ident or
            !std.mem.eql(u8, tokens[idx].lexeme, name) or !sema_tokens.tok_eq(tokens[idx + 1], "(")) continue;
        count += 1;
    }
    return count;
}

fn count_token_pair(tokens: []const lexer.Token, first: []const u8, second: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (sema_tokens.tok_eq(token, first) and idx + 1 < tokens.len and sema_tokens.tok_eq(tokens[idx + 1], second)) {
            count += 1;
        }
    }
    return count;
}
