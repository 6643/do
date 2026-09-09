const std = @import("std");
const lexer = @import("lexer.zig");
const sema_tokens = @import("sema_tokens.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

/// Source facts for the single measured async `HashMap<u32, u32>` route.
/// The fields are copied from token lexemes so the manifest registry can be
/// released before the plan is consumed by the emitter.
pub const AsyncMapPlan = struct {
    root_name: []const u8,
    helper_name: []const u8,
    host_name: []const u8,
    hash_map_name: []const u8,
    empty_hash_map_name: []const u8,
    hash_put_name: []const u8,
    helper_argument_name: []const u8,
    values_name: []const u8,
    child_name: []const u8,
    shape: p3_async_manifest.AsyncMapShape,

    pub fn deinit(self: *AsyncMapPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        allocator.free(self.helper_name);
        allocator.free(self.host_name);
        allocator.free(self.hash_map_name);
        allocator.free(self.empty_hash_map_name);
        allocator.free(self.hash_put_name);
        allocator.free(self.helper_argument_name);
        allocator.free(self.values_name);
        allocator.free(self.child_name);
        self.* = undefined;
    }
};

pub const RejectReason = enum {
    unknown_host_descriptor,
    marker_mismatch,
    type_unsupported,
    arity_unsupported,
    dynamic_map,
    extra_pair,
    multiple_children,
    legacy_async_decl,
    source_topology,

    pub fn identifier(self: RejectReason) []const u8 {
        return switch (self) {
            .unknown_host_descriptor => "UnknownP3AsyncHostDescriptor",
            .marker_mismatch => "P3AsyncMapMarkerMismatch",
            .type_unsupported => "P3AsyncMapTypeUnsupported",
            .arity_unsupported => "P3AsyncMapArityUnsupported",
            .dynamic_map => "P3AsyncMapDynamicConstruction",
            .extra_pair => "P3AsyncMapExtraPair",
            .multiple_children => "P3AsyncMapMultipleChildren",
            .legacy_async_decl => "P3AsyncMapLegacyAsyncDecl",
            .source_topology => "UnsupportedP3AsyncMapSourceTopology",
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
    descriptor: p3_async_manifest.Descriptor,
};

const SourceFacts = struct {
    host: HostBinding,
    helper: FunctionDecl,
    root: FunctionDecl,
    hash_map_name: []const u8,
    empty_hash_map_name: []const u8,
    hash_put_name: []const u8,
    helper_argument_name: []const u8,
    values_name: []const u8,
    child_name: []const u8,
};

const Inspection = union(enum) {
    accepted: SourceFacts,
    rejected: RejectReason,
};

pub fn analyze(allocator: std.mem.Allocator, tokens: []const lexer.Token) !AsyncMapPlan {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);

    const facts = switch (inspect_source(tokens, registry)) {
        .accepted => |value| value,
        .rejected => return error.UnsupportedP3AsyncMapComponent,
    };
    _ = switch (p3_async_manifest.lowering_shape(facts.host.descriptor) orelse
        return error.UnsupportedP3AsyncMapComponent)
    {
        .async_map_u32_u32 => |value| value,
        else => return error.UnsupportedP3AsyncMapComponent,
    };

    const root_name = try allocator.dupe(u8, facts.root.name);
    errdefer allocator.free(root_name);
    const helper_name = try allocator.dupe(u8, facts.helper.name);
    errdefer allocator.free(helper_name);
    const host_name = try allocator.dupe(u8, facts.host.name);
    errdefer allocator.free(host_name);
    const hash_map_name = try allocator.dupe(u8, facts.hash_map_name);
    errdefer allocator.free(hash_map_name);
    const empty_hash_map_name = try allocator.dupe(u8, facts.empty_hash_map_name);
    errdefer allocator.free(empty_hash_map_name);
    const hash_put_name = try allocator.dupe(u8, facts.hash_put_name);
    errdefer allocator.free(hash_put_name);
    const helper_argument_name = try allocator.dupe(u8, facts.helper_argument_name);
    errdefer allocator.free(helper_argument_name);
    const values_name = try allocator.dupe(u8, facts.values_name);
    errdefer allocator.free(values_name);
    const child_name = try allocator.dupe(u8, facts.child_name);
    errdefer allocator.free(child_name);

    return .{
        .root_name = root_name,
        .helper_name = helper_name,
        .host_name = host_name,
        .hash_map_name = hash_map_name,
        .empty_hash_map_name = empty_hash_map_name,
        .hash_put_name = hash_put_name,
        .helper_argument_name = helper_argument_name,
        .values_name = values_name,
        .child_name = child_name,
        .shape = .{
            .source_param = "HashMap<u32, u32>",
            .source_result = "u32",
        },
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
    const names = find_library_bindings(tokens) orelse return .{ .rejected = .source_topology };
    const host = switch (classify_host_binding(tokens, registry)) {
        .accepted => |value| value,
        .rejected => |reason| return .{ .rejected = reason },
    };
    const helper = find_function(tokens, "helper") orelse return .{ .rejected = .source_topology };
    const root = find_function(tokens, "run") orelse return .{ .rejected = .source_topology };

    if (helper.is_async or root.is_async) return .{ .rejected = .legacy_async_decl };
    if (!helper_signature_is_exact(tokens, helper, names.hash_map_name)) {
        return .{ .rejected = .type_unsupported };
    }
    if (!root_signature_is_exact(root)) return .{ .rejected = .source_topology };
    const helper_argument_name = tokens[helper.params_open + 1].lexeme;
    const values_name = root_values_name(tokens, root, names, helper_argument_name) orelse {
        return .{ .rejected = .dynamic_map };
    };
    const child_name = root_child_name(tokens, root) orelse return .{ .rejected = .source_topology };
    if (!helper_body_is_exact(tokens, helper, host.name, helper_argument_name)) {
        return .{ .rejected = .source_topology };
    }
    if (!root_body_is_exact(tokens, root, names, helper.name, values_name, child_name)) {
        const pair_count = count_call(tokens, names.hash_put_name);
        if (pair_count > 2) return .{ .rejected = .extra_pair };
        if (count_token_pair(tokens, "@", "async") > 1 or count_token_pair(tokens, "@", "await") > 2) {
            return .{ .rejected = .multiple_children };
        }
        return .{ .rejected = .source_topology };
    }

    if (top_level_token_count(tokens, "=") != 4 or
        top_level_function_count(tokens) != 2 or
        count_top_level_functions(tokens, "helper") != 1 or
        count_top_level_functions(tokens, "run") != 1 or
        count_token_pair(tokens, "@", "lib") != 3 or
        count_token_pair(tokens, "@", "host_async_func") != 1 or
        count_token_pair(tokens, "@", "host_func") != 0 or
        count_token_pair(tokens, "@", "host") != 0 or
        count_token_pair(tokens, "@", "await") != 2 or
        count_token_pair(tokens, "@", "async") != 1 or
        count_token_pair(tokens, "@", "cancel") != 0 or
        count_call(tokens, names.hash_put_name) != 2)
    {
        return .{ .rejected = .source_topology };
    }

    return .{ .accepted = .{
        .host = host,
        .helper = helper,
        .root = root,
        .hash_map_name = names.hash_map_name,
        .empty_hash_map_name = names.empty_hash_map_name,
        .hash_put_name = names.hash_put_name,
        .helper_argument_name = helper_argument_name,
        .values_name = values_name,
        .child_name = child_name,
    } };
}

const LibraryNames = struct {
    hash_map_name: []const u8,
    empty_hash_map_name: []const u8,
    hash_put_name: []const u8,
};

fn find_library_bindings(tokens: []const lexer.Token) ?LibraryNames {
    if (!has_exact_lib_binding(tokens, "HashMap", "HashMap") or
        !has_exact_lib_binding(tokens, "empty_hash_map", "empty_hash_map") or
        !has_exact_lib_binding(tokens, "hash_put", "hash_put")) return null;
    if (count_top_level_lib_bindings(tokens) != 3) return null;
    return .{
        .hash_map_name = "HashMap",
        .empty_hash_map_name = "empty_hash_map",
        .hash_put_name = "hash_put",
    };
}

fn has_exact_lib_binding(tokens: []const lexer.Token, alias: []const u8, imported: []const u8) bool {
    var found: usize = 0;
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx + 9 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or !ident_eq(tokens[idx], alias) or !tok_eq(tokens[idx + 1], "=") or
            !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "lib") or
            !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !tok_eq(tokens[idx + 6], ",") or !ident_eq(tokens[idx + 7], imported) or
            !tok_eq(tokens[idx + 8], ")")) continue;
        const path = sema_tokens.string_token_body(tokens[idx + 5].lexeme) orelse return false;
        if (!std.mem.eql(u8, path, "hash_map.do")) return false;
        found += 1;
    }
    return found == 1;
}

fn count_top_level_lib_bindings(tokens: []const lexer.Token) usize {
    var depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 4 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and tok_eq(tokens[idx], "@") and idx + 1 < tokens.len and
            tok_eq(tokens[idx + 1], "lib")) count += 1;
    }
    return count;
}

const HostInspection = union(enum) {
    accepted: HostBinding,
    rejected: RejectReason,
};

fn classify_host_binding(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) HostInspection {
    const async_count = count_token_pair(tokens, "@", "host_async_func");
    if (async_count == 0) {
        if (count_token_pair(tokens, "@", "host_func") != 0 or count_token_pair(tokens, "@", "host") != 0) {
            return .{ .rejected = .marker_mismatch };
        }
        return .{ .rejected = .unknown_host_descriptor };
    }
    if (async_count != 1) return .{ .rejected = .multiple_children };

    var idx: usize = 0;
    while (idx + 20 < tokens.len) : (idx += 1) {
        if (!ident_eq(tokens[idx], "submit") or !tok_eq(tokens[idx + 1], "=") or
            !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host_async_func") or
            !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(")) continue;
        const locator = sema_tokens.string_token_body(tokens[idx + 5].lexeme) orelse {
            return .{ .rejected = .unknown_host_descriptor };
        };
        const member = sema_tokens.string_token_body(tokens[idx + 7].lexeme) orelse {
            return .{ .rejected = .unknown_host_descriptor };
        };
        const descriptor = registry.find(locator, member) orelse {
            return .{ .rejected = .unknown_host_descriptor };
        };
        const signature_close = sema_tokens.find_matching(tokens, idx + 9, "(", ")") catch {
            return .{ .rejected = .source_topology };
        };
        if (signature_close != idx + 16 or
            !ident_eq(tokens[idx + 10], "HashMap") or !tok_eq(tokens[idx + 11], "<") or
            !ident_eq(tokens[idx + 12], "u32") or !tok_eq(tokens[idx + 13], ",") or
            !ident_eq(tokens[idx + 14], "u32") or !tok_eq(tokens[idx + 15], ">") or
            !tok_eq(tokens[idx + 17], "-") or !tok_eq(tokens[idx + 18], ">") or
            !ident_eq(tokens[idx + 19], "u32") or !tok_eq(tokens[idx + 20], ")")) {
            return .{ .rejected = .type_unsupported };
        }
        switch (p3_async_manifest.lowering_shape(descriptor) orelse return .{ .rejected = .unknown_host_descriptor }) {
            .async_map_u32_u32 => {},
            else => return .{ .rejected = .unknown_host_descriptor },
        }
        return .{ .accepted = .{ .name = "submit", .descriptor = descriptor } };
    }
    return .{ .rejected = .source_topology };
}

fn find_function(tokens: []const lexer.Token, name: []const u8) ?FunctionDecl {
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx + 6 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or !ident_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "(")) continue;
        const params_close = sema_tokens.find_matching(tokens, idx + 1, "(", ")") catch return null;
        if (params_close + 4 >= tokens.len or !tok_eq(tokens[params_close + 1], "-") or
            !tok_eq(tokens[params_close + 2], ">") or tokens[params_close + 3].kind != .ident or
            !tok_eq(tokens[params_close + 4], "{")) continue;
        const body_close = sema_tokens.find_matching(tokens, params_close + 4, "{", "}") catch return null;
        return .{
            .name = tokens[idx].lexeme,
            .params_open = idx + 1,
            .params_close = params_close,
            .body_open = params_close + 4,
            .body_close = body_close,
            .result_type = tokens[params_close + 3].lexeme,
            .is_async = idx > 0 and ident_eq(tokens[idx - 1], "async"),
        };
    }
    return null;
}

fn helper_signature_is_exact(tokens: []const lexer.Token, function: FunctionDecl, hash_map_name: []const u8) bool {
    return function.params_close == function.params_open + 8 and
        ident_eq(tokens[function.params_open + 1], "values") and
        ident_eq(tokens[function.params_open + 2], hash_map_name) and
        tok_eq(tokens[function.params_open + 3], "<") and ident_eq(tokens[function.params_open + 4], "u32") and
        tok_eq(tokens[function.params_open + 5], ",") and ident_eq(tokens[function.params_open + 6], "u32") and
        tok_eq(tokens[function.params_open + 7], ">") and std.mem.eql(u8, function.result_type, "u32");
}

fn root_signature_is_exact(function: FunctionDecl) bool {
    return function.params_close == function.params_open + 1 and std.mem.eql(u8, function.result_type, "u32");
}

fn helper_body_is_exact(tokens: []const lexer.Token, function: FunctionDecl, host_name: []const u8, argument_name: []const u8) bool {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len != 16) return false;
    return ident_eq(body[0], "pending") and ident_eq(body[1], "Future") and tok_eq(body[2], "<") and
        ident_eq(body[3], "u32") and tok_eq(body[4], ">") and tok_eq(body[5], "=") and
        ident_eq(body[6], host_name) and tok_eq(body[7], "(") and ident_eq(body[8], argument_name) and
        tok_eq(body[9], ")") and tok_eq(body[10], "return") and tok_eq(body[11], "@") and
        ident_eq(body[12], "await") and tok_eq(body[13], "(") and ident_eq(body[14], "pending") and
        tok_eq(body[15], ")");
}

fn root_values_name(
    tokens: []const lexer.Token,
    function: FunctionDecl,
    names: LibraryNames,
    helper_argument_name: []const u8,
) ?[]const u8 {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len < 22 or !ident_eq(body[0], "key") or !ident_eq(body[1], "u32") or !tok_eq(body[2], "=") or
        !number_eq(body[3], "0") or !ident_eq(body[4], "value") or !ident_eq(body[5], "u32") or
        !tok_eq(body[6], "=") or !number_eq(body[7], "0") or !ident_eq(body[8], "values") or
        !ident_eq(body[9], names.hash_map_name) or !tok_eq(body[10], "<") or !ident_eq(body[11], "u32") or
        !tok_eq(body[12], ",") or !ident_eq(body[13], "u32") or !tok_eq(body[14], ">") or
        !tok_eq(body[15], "=") or !ident_eq(body[16], names.empty_hash_map_name) or !tok_eq(body[17], "(") or
        !ident_eq(body[18], "key") or !tok_eq(body[19], ",") or !ident_eq(body[20], "value") or
        !tok_eq(body[21], ")") or !std.mem.eql(u8, helper_argument_name, "values")) return null;
    return body[8].lexeme;
}

fn root_child_name(tokens: []const lexer.Token, function: FunctionDecl) ?[]const u8 {
    const body = tokens[function.body_open + 1 .. function.body_close];
    var index: usize = 0;
    while (index + 4 < body.len) : (index += 1) {
        if (ident_eq(body[index], "child") and ident_eq(body[index + 1], "Future") and
            tok_eq(body[index + 2], "<") and ident_eq(body[index + 3], "u32") and tok_eq(body[index + 4], ">")) {
            return body[index].lexeme;
        }
    }
    return null;
}

fn root_body_is_exact(
    tokens: []const lexer.Token,
    function: FunctionDecl,
    names: LibraryNames,
    helper_name: []const u8,
    values_name: []const u8,
    child_name: []const u8,
) bool {
    const body = tokens[function.body_open + 1 .. function.body_close];
    if (body.len != 62) return false;
    if (!ident_eq(body[8], values_name) or !ident_eq(body[16], names.empty_hash_map_name) or
        !ident_eq(body[24], names.hash_put_name) or !ident_eq(body[34], names.hash_put_name) or
        !ident_eq(body[42], child_name)) return false;
    return ident_eq(body[0], "key") and ident_eq(body[1], "u32") and tok_eq(body[2], "=") and number_eq(body[3], "0") and
        ident_eq(body[4], "value") and ident_eq(body[5], "u32") and tok_eq(body[6], "=") and number_eq(body[7], "0") and
        ident_eq(body[9], names.hash_map_name) and tok_eq(body[10], "<") and ident_eq(body[11], "u32") and
        tok_eq(body[12], ",") and ident_eq(body[13], "u32") and tok_eq(body[14], ">") and tok_eq(body[15], "=") and
        tok_eq(body[17], "(") and ident_eq(body[18], "key") and tok_eq(body[19], ",") and ident_eq(body[20], "value") and
        tok_eq(body[21], ")") and ident_eq(body[22], values_name) and tok_eq(body[23], "=") and
        ident_eq(body[24], names.hash_put_name) and tok_eq(body[25], "(") and ident_eq(body[26], values_name) and
        tok_eq(body[27], ",") and number_eq(body[28], "7") and tok_eq(body[29], ",") and number_eq(body[30], "70") and
        tok_eq(body[31], ")") and ident_eq(body[32], values_name) and tok_eq(body[33], "=") and
        ident_eq(body[34], names.hash_put_name) and tok_eq(body[35], "(") and ident_eq(body[36], values_name) and
        tok_eq(body[37], ",") and number_eq(body[38], "9") and tok_eq(body[39], ",") and number_eq(body[40], "90") and
        tok_eq(body[41], ")") and ident_eq(body[42], child_name) and ident_eq(body[43], "Future") and tok_eq(body[44], "<") and
        ident_eq(body[45], "u32") and tok_eq(body[46], ">") and tok_eq(body[47], "=") and tok_eq(body[48], "@") and
        ident_eq(body[49], "async") and tok_eq(body[50], "(") and ident_eq(body[51], helper_name) and
        tok_eq(body[52], "(") and ident_eq(body[53], values_name) and tok_eq(body[54], ")") and tok_eq(body[55], ")") and
        tok_eq(body[56], "return") and tok_eq(body[57], "@") and ident_eq(body[58], "await") and tok_eq(body[59], "(") and
        ident_eq(body[60], child_name) and tok_eq(body[61], ")");
}

fn top_level_function_count(tokens: []const lexer.Token) usize {
    var depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and tokens[idx].kind == .ident and tok_eq(tokens[idx + 1], "(") and
            (idx == 0 or !tok_eq(tokens[idx - 1], "@"))) count += 1;
    }
    return count;
}

fn count_top_level_functions(tokens: []const lexer.Token, name: []const u8) usize {
    var depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and ident_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "(")) count += 1;
    }
    return count;
}

fn top_level_token_count(tokens: []const lexer.Token, expected: []const u8) usize {
    var depth: usize = 0;
    var count: usize = 0;
    for (tokens) |token| {
        if (tok_eq(token, "{")) {
            depth += 1;
        } else if (tok_eq(token, "}")) {
            if (depth > 0) depth -= 1;
        } else if (depth == 0 and tok_eq(token, expected)) {
            count += 1;
        }
    }
    return count;
}

fn count_token_pair(tokens: []const lexer.Token, first: []const u8, second: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, first) and idx + 1 < tokens.len and tok_eq(tokens[idx + 1], second)) count += 1;
    }
    return count;
}

fn count_call(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (ident_eq(token, name) and idx + 1 < tokens.len and tok_eq(tokens[idx + 1], "(")) count += 1;
    }
    return count;
}

fn number_eq(token: lexer.Token, expected: []const u8) bool {
    return token.kind == .number and std.mem.eql(u8, token.lexeme, expected);
}

fn tok_eq(token: lexer.Token, expected: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, expected);
}

fn ident_eq(token: lexer.Token, expected: []const u8) bool {
    return token.kind == .ident and std.mem.eql(u8, token.lexeme, expected);
}
