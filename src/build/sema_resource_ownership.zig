const std = @import("std");
const lexer = @import("lexer.zig");
const resource_abi_registry = @import("resource_abi_registry.zig");
const sema_tokens = @import("sema_tokens.zig");

const find_matching = sema_tokens.find_matching;
const mark_error_at = sema_tokens.mark_error_at;
const public_func_name = sema_tokens.public_func_name;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

const ResourceType = struct {
    name: []const u8,
    resource: []const u8,
};

const ResourceHostImport = struct {
    alias: []const u8,
    descriptor: resource_abi_registry.Descriptor,
};

const ResourceBinding = struct {
    name: []const u8,
    resource: []const u8,
    decl_idx: usize,
    active: bool = true,
};

const OwnedResultBinding = struct {
    name: []const u8,
    resource: []const u8,
};

const PreopenListBinding = struct {
    name: []const u8,
    resource: []const u8,
};

pub fn check_resource_ownership(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var registry = try resource_abi_registry.Registry.load(allocator, @embedFile("resource_abi_registry.json"));
    defer registry.deinit(allocator);

    try check_resource_ownership_with_registry(allocator, tokens, registry);
}

fn check_resource_ownership_with_registry(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    registry: resource_abi_registry.Registry,
) !void {
    var resource_types = std.ArrayList(ResourceType).empty;
    defer resource_types.deinit(allocator);
    try collect_resource_types(allocator, tokens, registry, &resource_types);
    if (resource_types.items.len == 0) return;

    var host_imports = std.ArrayList(ResourceHostImport).empty;
    defer host_imports.deinit(allocator);
    try collect_resource_host_imports(allocator, tokens, registry, &host_imports);
    if (host_imports.items.len == 0) return;

    try check_function_bodies(allocator, tokens, resource_types.items, host_imports.items);
}

fn collect_resource_types(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    registry: resource_abi_registry.Registry,
    resource_types: *std.ArrayList(ResourceType),
) !void {
    var i: usize = 0;
    while (i + 5 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or !tok_eq(tokens[i + 3], "wasi_resource") or !tok_eq(tokens[i + 4], "(") or tokens[i + 5].kind != .string) continue;
        const resource_path = string_token_body(tokens[i + 5].lexeme) orelse continue;
        const resource = find_resource_for_path(registry, resource_path) orelse continue;
        try resource_types.append(allocator, .{ .name = tokens[i].lexeme, .resource = resource });
    }
}

fn collect_resource_host_imports(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    registry: resource_abi_registry.Registry,
    host_imports: *std.ArrayList(ResourceHostImport),
) !void {
    var i: usize = 0;
    while (i + 8 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or (!tok_eq(tokens[i + 3], "host") and !tok_eq(tokens[i + 3], "host_func")) or !tok_eq(tokens[i + 4], "(") or tokens[i + 5].kind != .string or !tok_eq(tokens[i + 6], ",") or tokens[i + 7].kind != .string or !tok_eq(tokens[i + 8], ",")) continue;
        const locator = string_token_body(tokens[i + 5].lexeme) orelse continue;
        const member = string_token_body(tokens[i + 7].lexeme) orelse continue;
        const descriptor = registry.find(locator, member) orelse continue;
        try host_imports.append(allocator, .{ .alias = public_func_name(tokens[i].lexeme), .descriptor = descriptor });
    }
}

fn find_resource_for_path(registry: resource_abi_registry.Registry, resource_path: []const u8) ?[]const u8 {
    for (registry.descriptors) |descriptor| {
        if (std.mem.eql(u8, descriptor.resource_path, resource_path)) return descriptor.resource;
        if (descriptor.result_resource_path) |result_resource_path| {
            if (std.mem.eql(u8, result_resource_path, resource_path)) return descriptor.result_resource;
        }
        if (descriptor.result_error_resource_path) |result_error_resource_path| {
            if (std.mem.eql(u8, result_error_resource_path, resource_path)) return descriptor.result_error_resource;
        }
    }
    return null;
}

fn check_function_bodies(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    resource_types: []const ResourceType,
    host_imports: []const ResourceHostImport,
) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "(")) continue;
        const close_params = find_matching(tokens, i + 1, "(", ")") catch continue;
        const body_open = find_function_body_open(tokens, close_params + 1) orelse continue;
        const body_close = find_matching(tokens, body_open, "{", "}") catch continue;
        const is_async = (i > 0 and tok_eq(tokens[i - 1], "async")) or
            body_contains_async_operation(tokens, body_open + 1, body_close);
        try check_function_body(allocator, tokens, i + 2, close_params, is_async, body_open + 1, body_close, resource_types, host_imports);
        i = body_close;
    }
}

fn body_contains_async_operation(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var idx = start_idx;
    while (idx < end_idx) : (idx += 1) {
        if (tok_eq(tokens[idx], "Future") or tok_eq(tokens[idx], "await") or
            (idx + 1 < end_idx and tok_eq(tokens[idx], "@") and
                (tok_eq(tokens[idx + 1], "async") or tok_eq(tokens[idx + 1], "await") or
                    tok_eq(tokens[idx + 1], "cancel") or tok_eq(tokens[idx + 1], "next")))) return true;
    }
    return false;
}

fn find_function_body_open(tokens: []const lexer.Token, start_idx: usize) ?usize {
    if (start_idx >= tokens.len) return null;
    const line = tokens[start_idx - 1].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {
        if (tok_eq(tokens[i], "{")) return i;
    }
    return null;
}

fn check_function_body(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    params_start: usize,
    params_end: usize,
    is_async: bool,
    start_idx: usize,
    end_idx: usize,
    resource_types: []const ResourceType,
    host_imports: []const ResourceHostImport,
) !void {
    var bindings = std.ArrayList(ResourceBinding).empty;
    defer bindings.deinit(allocator);
    var preopen_lists = std.ArrayList(PreopenListBinding).empty;
    defer preopen_lists.deinit(allocator);
    var owned_results = std.ArrayList(OwnedResultBinding).empty;
    defer owned_results.deinit(allocator);

    if (is_async) try collect_resource_param_bindings(&bindings, allocator, tokens, params_start, params_end, resource_types);

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (preopen_list_initialization(tokens, i, end_idx, host_imports)) |initialization| {
            try preopen_lists.append(allocator, initialization);
            continue;
        }
        if (owned_result_initialization(tokens, i, end_idx, resource_types, host_imports)) |initialization| {
            try owned_results.append(allocator, initialization);
            continue;
        }
        if (resource_local_initialization(tokens, i, end_idx, resource_types)) |initialization| {
            try initialize_resource_binding(&bindings, allocator, tokens, initialization, host_imports, preopen_lists.items, owned_results.items);
            continue;
        }
        if (tokens[i].kind != .ident or i + 1 >= end_idx or !tok_eq(tokens[i + 1], "(")) continue;
        const descriptor = find_resource_host_import(host_imports, tokens[i].lexeme) orelse continue;
        const close_idx = find_matching(tokens, i + 1, "(", ")") catch continue;
        if (close_idx >= end_idx) continue;
        try check_resource_call(&bindings, tokens, i, close_idx, descriptor);
        i = close_idx;
    }

    for (bindings.items) |binding| {
        if (binding.active) return mark_error_at(tokens, binding.decl_idx, error.ResourceDropped);
    }
}

fn collect_resource_param_bindings(
    bindings: *std.ArrayList(ResourceBinding),
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    resource_types: []const ResourceType,
) !void {
    var i = start_idx;
    while (i + 1 < end_idx) {
        if (tokens[i].kind != .ident or tokens[i + 1].kind != .ident) return;
        const resource = find_resource_type(resource_types, tokens[i + 1].lexeme) orelse {
            i += 2;
            if (i < end_idx and tok_eq(tokens[i], ",")) i += 1;
            continue;
        };
        try bindings.append(allocator, .{
            .name = tokens[i].lexeme,
            .resource = resource,
            .decl_idx = i,
        });
        i += 2;
        if (i < end_idx and tok_eq(tokens[i], ",")) i += 1;
    }
}

fn owned_result_initialization(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    resource_types: []const ResourceType,
    host_imports: []const ResourceHostImport,
) ?OwnedResultBinding {
    if (idx + 9 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Result") or !tok_eq(tokens[idx + 2], "<") or tokens[idx + 3].kind != .ident or !tok_eq(tokens[idx + 4], ",")) return null;
    const resource = find_resource_type(resource_types, tokens[idx + 3].lexeme) orelse return null;
    const close_angle = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (close_angle + 3 >= end_idx or !tok_eq(tokens[close_angle + 1], "=") or tokens[close_angle + 2].kind != .ident or !tok_eq(tokens[close_angle + 3], "(")) return null;
    const host_import = find_resource_host_import(host_imports, tokens[close_angle + 2].lexeme) orelse return null;
    if (host_import.descriptor.result.ownership != .own or !owned_result_matches_resource(host_import.descriptor, resource)) return null;
    return .{ .name = tokens[idx].lexeme, .resource = resource };
}

const ResourceInitialization = struct {
    target_idx: usize,
    resource: []const u8,
    value_idx: usize,
};

fn resource_local_initialization(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    resource_types: []const ResourceType,
) ?ResourceInitialization {
    if (idx + 3 >= end_idx or tokens[idx].kind != .ident or tokens[idx + 1].kind != .ident or !tok_eq(tokens[idx + 2], "=")) return null;
    const resource = find_resource_type(resource_types, tokens[idx + 1].lexeme) orelse return null;
    return .{ .target_idx = idx, .resource = resource, .value_idx = idx + 3 };
}

fn initialize_resource_binding(
    bindings: *std.ArrayList(ResourceBinding),
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    initialization: ResourceInitialization,
    host_imports: []const ResourceHostImport,
    preopen_lists: []const PreopenListBinding,
    owned_results: []const OwnedResultBinding,
) !void {
    if (preopen_descriptor_get(tokens, initialization.value_idx, preopen_lists, initialization.resource)) |source_name| {
        if (find_resource_binding(bindings.items, source_name) != null) return;
        try bindings.append(allocator, .{
            .name = tokens[initialization.target_idx].lexeme,
            .resource = initialization.resource,
            .decl_idx = initialization.target_idx,
        });
        return;
    }
    if (tokens[initialization.value_idx].kind != .ident) return;
    if (owned_result_ok_payload(tokens, initialization.target_idx, tokens[initialization.value_idx].lexeme, owned_results, initialization.resource)) {
        try bindings.append(allocator, .{
            .name = tokens[initialization.target_idx].lexeme,
            .resource = initialization.resource,
            .decl_idx = initialization.target_idx,
        });
        return;
    }
    if (find_resource_host_import(host_imports, tokens[initialization.value_idx].lexeme)) |host_import| {
        if (host_import.descriptor.result.ownership != .own or !std.mem.eql(u8, host_import.descriptor.result.type_name, initialization.resource)) return;
        try bindings.append(allocator, .{
            .name = tokens[initialization.target_idx].lexeme,
            .resource = initialization.resource,
            .decl_idx = initialization.target_idx,
        });
        return;
    }

    const source_idx = find_resource_binding(bindings.items, tokens[initialization.value_idx].lexeme) orelse return;
    if (!bindings.items[source_idx].active) return mark_error_at(tokens, initialization.value_idx, error.ResourceAlreadyConsumed);
    if (!std.mem.eql(u8, bindings.items[source_idx].resource, initialization.resource)) return;
    bindings.items[source_idx].active = false;
    try bindings.append(allocator, .{
        .name = tokens[initialization.target_idx].lexeme,
        .resource = initialization.resource,
        .decl_idx = initialization.target_idx,
    });
}

fn owned_result_matches_resource(descriptor: resource_abi_registry.Descriptor, resource: []const u8) bool {
    const prefix = "result<";
    const result = descriptor.result.type_name;
    const result_resource = descriptor.result_resource orelse descriptor.resource;
    const error_resource = descriptor.result_error_resource orelse "error-code";
    const suffix = ">";
    return result.len == prefix.len + result_resource.len + 1 + error_resource.len + suffix.len and
        std.mem.eql(u8, result[0..prefix.len], prefix) and
        std.mem.eql(u8, result[prefix.len .. prefix.len + result_resource.len], result_resource) and
        result[prefix.len + result_resource.len] == ',' and
        std.mem.eql(u8, result[prefix.len + result_resource.len + 1 .. prefix.len + result_resource.len + 1 + error_resource.len], error_resource) and
        std.mem.eql(u8, result[result.len - suffix.len ..], suffix) and
        std.mem.eql(u8, result_resource, resource);
}

fn owned_result_ok_payload(
    tokens: []const lexer.Token,
    target_idx: usize,
    source_name: []const u8,
    owned_results: []const OwnedResultBinding,
    resource: []const u8,
) bool {
    for (owned_results) |owned_result| {
        if (!std.mem.eql(u8, owned_result.name, source_name) or !std.mem.eql(u8, owned_result.resource, resource)) continue;
        return inside_direct_ok_narrowing(tokens, target_idx, source_name);
    }
    return false;
}

fn inside_direct_ok_narrowing(tokens: []const lexer.Token, target_idx: usize, source_name: []const u8) bool {
    var idx = target_idx;
    var nested_blocks: usize = 0;
    while (idx > 0) {
        idx -= 1;
        if (tok_eq(tokens[idx], "}")) {
            nested_blocks += 1;
            continue;
        }
        if (!tok_eq(tokens[idx], "{")) continue;
        if (nested_blocks > 0) {
            nested_blocks -= 1;
            continue;
        }
        return idx >= 8 and
            tok_eq(tokens[idx - 8], "if") and
            tok_eq(tokens[idx - 7], "@") and
            tok_eq(tokens[idx - 6], "is") and
            tok_eq(tokens[idx - 5], "(") and
            tokens[idx - 4].kind == .ident and std.mem.eql(u8, tokens[idx - 4].lexeme, source_name) and
            tok_eq(tokens[idx - 3], ",") and
            tok_eq(tokens[idx - 2], "Ok") and
            tok_eq(tokens[idx - 1], ")");
    }
    return false;
}

fn preopen_list_initialization(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    host_imports: []const ResourceHostImport,
) ?PreopenListBinding {
    if (tokens[idx].kind != .ident) return null;
    const line = tokens[idx].line;
    var eq_idx = idx + 1;
    while (eq_idx < end_idx and tokens[eq_idx].line == line and !tok_eq(tokens[eq_idx], "=")) : (eq_idx += 1) {}
    if (eq_idx + 3 >= end_idx or !tok_eq(tokens[eq_idx], "=") or tokens[eq_idx + 1].kind != .ident or !tok_eq(tokens[eq_idx + 2], "(") or !tok_eq(tokens[eq_idx + 3], ")")) return null;
    const host_import = find_resource_host_import(host_imports, tokens[eq_idx + 1].lexeme) orelse return null;
    if (host_import.descriptor.result.ownership != .own or !owned_preopen_result_matches(host_import.descriptor)) return null;
    return .{ .name = tokens[idx].lexeme, .resource = host_import.descriptor.resource };
}

fn owned_preopen_result_matches(descriptor: resource_abi_registry.Descriptor) bool {
    const prefix = "list<tuple<";
    const suffix = ",string>>";
    const result = descriptor.result.type_name;
    return result.len == prefix.len + descriptor.resource.len + suffix.len and
        std.mem.eql(u8, result[0..prefix.len], prefix) and
        std.mem.eql(u8, result[prefix.len .. prefix.len + descriptor.resource.len], descriptor.resource) and
        std.mem.eql(u8, result[prefix.len + descriptor.resource.len ..], suffix);
}

fn preopen_descriptor_get(
    tokens: []const lexer.Token,
    value_idx: usize,
    preopen_lists: []const PreopenListBinding,
    resource: []const u8,
) ?[]const u8 {
    if (value_idx + 9 >= tokens.len or !tok_eq(tokens[value_idx], "@") or !tok_eq(tokens[value_idx + 1], "get") or !tok_eq(tokens[value_idx + 2], "(") or tokens[value_idx + 3].kind != .ident or !tok_eq(tokens[value_idx + 4], ",") or !tok_eq(tokens[value_idx + 5], "0") or !tok_eq(tokens[value_idx + 6], ",") or !tok_eq(tokens[value_idx + 7], "0") or !tok_eq(tokens[value_idx + 8], ")")) return null;
    for (preopen_lists) |preopen_list| {
        if (std.mem.eql(u8, preopen_list.name, tokens[value_idx + 3].lexeme) and std.mem.eql(u8, preopen_list.resource, resource)) return preopen_list.name;
    }
    return null;
}

fn check_resource_call(
    bindings: *std.ArrayList(ResourceBinding),
    tokens: []const lexer.Token,
    call_idx: usize,
    close_idx: usize,
    host_import: ResourceHostImport,
) !void {
    var argument_idx = call_idx + 2;
    for (host_import.descriptor.params) |param| {
        if (argument_idx >= close_idx) return;
        if (param.ownership != .none and tokens[argument_idx].kind == .ident) {
            const binding_idx = find_resource_binding(bindings.items, tokens[argument_idx].lexeme) orelse return;
            if (!bindings.items[binding_idx].active) return mark_error_at(tokens, argument_idx, error.ResourceAlreadyConsumed);
            if (!std.mem.eql(u8, bindings.items[binding_idx].resource, param.type_name)) return;
            if (param.ownership == .own) bindings.items[binding_idx].active = false;
        }
        argument_idx = next_call_argument(tokens, argument_idx, close_idx) orelse return;
    }
}

fn next_call_argument(tokens: []const lexer.Token, argument_idx: usize, close_idx: usize) ?usize {
    if (argument_idx + 1 == close_idx) return close_idx;
    if (argument_idx + 1 >= close_idx or !tok_eq(tokens[argument_idx + 1], ",")) return null;
    return argument_idx + 2;
}

fn find_resource_type(resource_types: []const ResourceType, name: []const u8) ?[]const u8 {
    for (resource_types) |resource_type| {
        if (std.mem.eql(u8, resource_type.name, name)) return resource_type.resource;
    }
    return null;
}

fn find_resource_host_import(host_imports: []const ResourceHostImport, alias: []const u8) ?ResourceHostImport {
    for (host_imports) |host_import| {
        if (std.mem.eql(u8, host_import.alias, alias)) return host_import;
    }
    return null;
}

fn find_resource_binding(bindings: []const ResourceBinding, name: []const u8) ?usize {
    var idx = bindings.len;
    while (idx > 0) {
        idx -= 1;
        if (std.mem.eql(u8, bindings[idx].name, name)) return idx;
    }
    return null;
}

test "resource own call consumes its local binding" {
    const source =
        \\create = @host("do:resource-probe/ledger@0.1.0", "create", (u32) -> Ticket)
        \\consume = @host("do:resource-probe/ledger@0.1.0", "consume", (Ticket) -> u32)
        \\borrow_value = @host("do:resource-probe/ledger@0.1.0", "borrow-value", (Ticket) -> u32)
        \\Ticket = @wasi_resource("do:resource-probe/ledger/ticket", { .id i64 })
        \\start() {
        \\    ticket Ticket = create(7)
        \\    consume(ticket)
        \\    borrow_value(ticket)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.ResourceAlreadyConsumed, check_resource_ownership(std.testing.allocator, tokens));
}

test "resource borrow preserves the owner for a later own call" {
    const source =
        \\create = @host("do:resource-probe/ledger@0.1.0", "create", (u32) -> Ticket)
        \\borrow_value = @host("do:resource-probe/ledger@0.1.0", "borrow-value", (Ticket) -> u32)
        \\consume = @host("do:resource-probe/ledger@0.1.0", "consume", (Ticket) -> u32)
        \\Ticket = @wasi_resource("do:resource-probe/ledger/ticket", { .id i64 })
        \\start() {
        \\    ticket Ticket = create(7)
        \\    borrow_value(ticket)
        \\    consume(ticket)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_resource_ownership(std.testing.allocator, tokens);
}

test "HTTP response status borrow preserves the owner for canonical drop" {
    const source =
        \\get_status = @host("wasi:http/types@0.3.0-rc-2025-09-16", "response.get-status-code", (HttpResponse) -> u16)
        \\drop_response = @host("wasi:http/types@0.3.0-rc-2025-09-16", "response.drop", (HttpResponse) -> nil)
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\async handle(response HttpResponse) -> nil {
        \\    status u16 = get_status(response)
        \\    _ = status
        \\    drop_response(response)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_resource_ownership(std.testing.allocator, tokens);
}

test "preopen descriptor extraction must be dropped" {
    const source =
        \\.host_preopens = @host("wasi:filesystem/preopens@0.3.0", "get-directories", () -> [Tuple<Dir, text>])
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\start() {
        \\    roots [Tuple<Dir, text>] = host_preopens()
        \\    dir Dir = @get(roots, 0, 0)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.ResourceDropped, check_resource_ownership(std.testing.allocator, tokens));
}

test "preopen descriptor use after canonical drop is rejected" {
    const source =
        \\.host_preopens = @host("wasi:filesystem/preopens@0.3.0", "get-directories", () -> [Tuple<Dir, text>])
        \\.host_sync = @host("wasi:filesystem/types@0.3.0", "descriptor.sync", (Dir) -> Result<nil, FileError>)
        \\.host_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (Dir) -> nil)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\FileError error = FileFlushFailed
        \\start() {
        \\    roots [Tuple<Dir, text>] = host_preopens()
        \\    dir Dir = @get(roots, 0, 0)
        \\    host_drop(dir)
        \\    host_sync(dir)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.ResourceAlreadyConsumed, check_resource_ownership(std.testing.allocator, tokens));
}

test "an owned Result can transfer a resource distinct from the consumed input" {
    const registry_json =
        \\{"schema":1,"descriptors":[
        \\  {"locator":"do:resource-probe/http@0.1.0","member":"create-request","resource":"request","resource_path":"http/types/request","params":[],"result":{"type":"request","ownership":"own"},"resource_drop":false},
        \\  {"locator":"wasi:http/client@0.3.0-rc-2025-09-16","member":"send","resource":"request","resource_path":"http/types/request","result_resource":"response","result_resource_path":"http/types/response","params":[{"type":"request","ownership":"own"}],"result":{"type":"result<response,error-code>","ownership":"own"},"resource_drop":false}
        \\]}
    ;
    var registry = try resource_abi_registry.Registry.load(std.testing.allocator, registry_json);
    defer registry.deinit(std.testing.allocator);

    const source =
        \\create_request = @host("do:resource-probe/http@0.1.0", "create-request", () -> HttpRequest)
        \\send = @host("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\start() {
        \\    request HttpRequest = create_request()
        \\    replied Result<HttpResponse, HttpError> = send(request)
        \\    if @is(replied, Ok) {
        \\        response HttpResponse = replied
        \\    }
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.ResourceDropped, check_resource_ownership_with_registry(std.testing.allocator, tokens, registry));
}

test "async host function consumes a resource parameter once" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async run(request HttpRequest) -> nil {
        \\    first Result<HttpResponse, HttpError> = send(request)
        \\    second Result<HttpResponse, HttpError> = send(request)
        \\    _ = first
        \\    _ = second
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.ResourceAlreadyConsumed, check_resource_ownership(std.testing.allocator, tokens));
}
