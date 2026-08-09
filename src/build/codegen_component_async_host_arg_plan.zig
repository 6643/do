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

pub const RejectReason = enum {
    unknown_host_descriptor,
    marker_mismatch,
    type_unsupported,
    arity_unsupported,
    dynamic_root,
    helper_payload,
    nested_helper,
    multiple_children,
    payload_unsupported,
    legacy_async_decl,
    source_topology,

    pub fn identifier(self: RejectReason) []const u8 {
        return switch (self) {
            .unknown_host_descriptor => "UnknownP3AsyncHostDescriptor",
            .marker_mismatch => "P3AsyncHostArgMarkerMismatch",
            .type_unsupported => "P3AsyncHostArgTypeUnsupported",
            .arity_unsupported => "P3AsyncHostArgArityUnsupported",
            .dynamic_root => "P3AsyncHostArgDynamicRoot",
            .helper_payload => "P3AsyncHostArgHelperPayload",
            .nested_helper => "P3AsyncHostArgNestedHelper",
            .multiple_children => "P3AsyncHostArgMultipleChildren",
            .payload_unsupported => "P3AsyncHostArgPayloadUnsupported",
            .legacy_async_decl => "P3AsyncHostArgLegacyAsyncDecl",
            .source_topology => "UnsupportedP3AsyncHostArgSourceTopology",
        };
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

const SourceFacts = struct {
    host: HostBinding,
    helper: FunctionDecl,
    root: FunctionDecl,
    argument_name: []const u8,
    argument_value: u32,
};

const Inspection = union(enum) {
    accepted: SourceFacts,
    rejected: RejectReason,
};

pub fn analyze(allocator: std.mem.Allocator, tokens: []const lexer.Token) !AsyncHostScalarArgPlan {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);

    const facts = switch (inspect_source(tokens, registry)) {
        .accepted => |value| value,
        .rejected => return error.UnsupportedP3AsyncHostArgComponent,
    };

    const root_name = try allocator.dupe(u8, facts.root.name);
    errdefer allocator.free(root_name);
    const helper_name = try allocator.dupe(u8, facts.helper.name);
    errdefer allocator.free(helper_name);
    const host_name = try allocator.dupe(u8, facts.host.name);
    errdefer allocator.free(host_name);
    const host_locator = try allocator.dupe(u8, facts.host.locator);
    errdefer allocator.free(host_locator);
    const host_member = try allocator.dupe(u8, facts.host.member);
    errdefer allocator.free(host_member);
    const async_import_module = try allocator.dupe(u8, facts.host.descriptor.canonical.async_import_module);
    errdefer allocator.free(async_import_module);
    const async_import_name = try allocator.dupe(u8, facts.host.descriptor.canonical.async_import_name);
    errdefer allocator.free(async_import_name);
    const owned_argument_name = try allocator.dupe(u8, facts.argument_name);
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
        .argument_value = facts.argument_value,
    };
}

pub fn rejection_reason(allocator: std.mem.Allocator, tokens: []const lexer.Token) !?RejectReason {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    return switch (inspect_source(tokens, registry)) {
        .accepted => null,
        .rejected => |reason| reason,
    };
}

fn inspect_source(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) Inspection {
    if (classify_host_binding(tokens, registry)) |reason| return .{ .rejected = reason };
    const host = find_host_binding(tokens, registry) orelse return .{ .rejected = .unknown_host_descriptor };
    const helper = find_function(tokens, "helper") orelse return .{ .rejected = .source_topology };
    const root = find_function(tokens, "run") orelse return .{ .rejected = .source_topology };
    const argument_name = helper_argument_name(tokens, helper) orelse {
        if (!std.mem.eql(u8, helper.result_type, "nil")) return .{ .rejected = .helper_payload };
        return .{ .rejected = .type_unsupported };
    };
    const argument_value = root_argument_value(tokens, root) orelse return .{ .rejected = .dynamic_root };

    if (helper.is_async or root.is_async) return .{ .rejected = .legacy_async_decl };
    if (argument_value != 7) return .{ .rejected = .dynamic_root };
    if (!signature_is_unit(root)) return .{ .rejected = .source_topology };
    if (helper_future_payload(tokens, helper)) |payload| {
        if (!std.mem.eql(u8, payload, "nil")) return .{ .rejected = .payload_unsupported };
    }
    if (!helper_body_is_exact(tokens, helper, host.name, argument_name)) {
        if (count_ident_in_range(tokens, helper.body_open + 1, helper.body_close, host.name) > 1 or
            count_token_pair_range(tokens, helper.body_open + 1, helper.body_close, "@", "async") > 0 or
            count_token_pair_range(tokens, helper.body_open + 1, helper.body_close, "@", "await") > 1)
        {
            return .{ .rejected = .multiple_children };
        }
        if (count_call_heads(tokens[helper.body_open + 1 .. helper.body_close]) > 2) {
            return .{ .rejected = .nested_helper };
        }
        return .{ .rejected = .source_topology };
    }
    if (!root_body_is_exact(tokens, root, argument_value)) {
        if (count_token_pair(tokens, "@", "async") > 1 or count_token_pair(tokens, "@", "await") > 2) {
            return .{ .rejected = .multiple_children };
        }
        return .{ .rejected = .source_topology };
    }
    if (top_level_token_count(tokens, "=") != 1 or
        top_level_function_count(tokens) != 2 or
        count_top_level_functions(tokens, "helper") != 1 or
        count_top_level_functions(tokens, "run") != 1 or
        count_token_pair(tokens, "@", "host_async_func") != 1 or
        count_token_pair(tokens, "@", "async") != 1 or
        count_token_pair(tokens, "@", "await") != 2 or
        count_token_pair(tokens, "@", "cancel") != 0)
    {
        return .{ .rejected = .source_topology };
    }
    return .{ .accepted = .{
        .host = host,
        .helper = helper,
        .root = root,
        .argument_name = argument_name,
        .argument_value = argument_value,
    } };
}

fn classify_host_binding(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?RejectReason {
    const async_count = count_token_pair(tokens, "@", "host_async_func");
    if (async_count == 0) {
        if (count_token_pair(tokens, "@", "host_func") != 0 or count_token_pair(tokens, "@", "host") != 0) return .marker_mismatch;
        return .unknown_host_descriptor;
    }
    if (async_count != 1) return .multiple_children;

    var marker_idx: ?usize = null;
    for (tokens, 0..) |token, idx| {
        if (sema_tokens.tok_eq(token, "@") and idx + 1 < tokens.len and sema_tokens.tok_eq(tokens[idx + 1], "host_async_func")) {
            marker_idx = idx;
            break;
        }
    }
    const base = marker_idx orelse return .unknown_host_descriptor;
    if (base + 7 >= tokens.len or !sema_tokens.tok_eq(tokens[base + 2], "(") or
        tokens[base + 3].kind != .string or !sema_tokens.tok_eq(tokens[base + 4], ",") or
        tokens[base + 5].kind != .string or !sema_tokens.tok_eq(tokens[base + 6], ",") or
        !sema_tokens.tok_eq(tokens[base + 7], "(")) return .source_topology;
    const locator = sema_tokens.string_token_body(tokens[base + 3].lexeme) orelse return .unknown_host_descriptor;
    const member = sema_tokens.string_token_body(tokens[base + 5].lexeme) orelse return .unknown_host_descriptor;
    if (registry.find(locator, member) == null) return .unknown_host_descriptor;
    const params_close = sema_tokens.find_matching(tokens, base + 7, "(", ")") catch return .source_topology;
    const param_count = count_signature_arguments(tokens, base + 7, params_close);
    if (param_count != 1) return .arity_unsupported;
    if (params_close != base + 9 or tokens[base + 8].kind != .ident or !sema_tokens.tok_eq(tokens[base + 8], "u32")) return .type_unsupported;
    if (params_close + 3 >= tokens.len or !sema_tokens.tok_eq(tokens[params_close + 1], "-") or
        !sema_tokens.tok_eq(tokens[params_close + 2], ">") or tokens[params_close + 3].kind != .ident) return .source_topology;
    if (!sema_tokens.tok_eq(tokens[params_close + 3], "nil")) return .payload_unsupported;
    return null;
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

fn count_token_pair_range(tokens: []const lexer.Token, start: usize, end: usize, first: []const u8, second: []const u8) usize {
    var count: usize = 0;
    var idx = start;
    while (idx < end) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], first) and idx + 1 < end and sema_tokens.tok_eq(tokens[idx + 1], second)) count += 1;
    }
    return count;
}

fn count_ident_in_range(tokens: []const lexer.Token, start: usize, end: usize, expected: []const u8) usize {
    var count: usize = 0;
    var idx = start;
    while (idx < end) : (idx += 1) {
        if (ident_eq(tokens[idx], expected)) count += 1;
    }
    return count;
}

fn count_signature_arguments(tokens: []const lexer.Token, open: usize, close: usize) usize {
    if (close <= open + 1) return 0;
    var count: usize = 1;
    var depth: usize = 0;
    var idx = open + 1;
    while (idx < close) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "(") or sema_tokens.tok_eq(tokens[idx], "<")) {
            depth += 1;
        } else if (sema_tokens.tok_eq(tokens[idx], ")") or sema_tokens.tok_eq(tokens[idx], ">")) {
            if (depth > 0) depth -= 1;
        } else if (depth == 0 and sema_tokens.tok_eq(tokens[idx], ",")) {
            count += 1;
        }
    }
    return count;
}

fn count_call_heads(tokens: []const lexer.Token) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (token.kind == .ident and idx + 1 < tokens.len and sema_tokens.tok_eq(tokens[idx + 1], "(")) count += 1;
    }
    return count;
}

fn helper_future_payload(tokens: []const lexer.Token, function: FunctionDecl) ?[]const u8 {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len < 4 or !ident_eq(body[1], "Future") or !sema_tokens.tok_eq(body[2], "<")) return null;
    return body[3].lexeme;
}

fn top_level_token_count(tokens: []const lexer.Token, expected: []const u8) usize {
    var depth: usize = 0;
    var count: usize = 0;
    for (tokens) |token| {
        if (sema_tokens.tok_eq(token, "{")) {
            depth += 1;
        } else if (sema_tokens.tok_eq(token, "}")) {
            if (depth > 0) depth -= 1;
        } else if (depth == 0 and sema_tokens.tok_eq(token, expected)) {
            count += 1;
        }
    }
    return count;
}

fn ident_eq(token: lexer.Token, expected: []const u8) bool {
    return token.kind == .ident and std.mem.eql(u8, token.lexeme, expected);
}
