const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const imports = @import("imports.zig");
const module_graph = @import("module_graph.zig");
const generated_wit_manifest = @import("generated_wit_manifest.zig");
const sema_tokens = @import("sema_tokens.zig");

const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

const pinned_module_path = "./wit/scalar/do_generic_async_scalar_probe__host__probe.do";

test "generated scalar async admission accepts the pinned await/cancel slice" {
    const source = @embedFile("test/check/430_generated_async_scalar.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    var graph = try test_graph(std.testing.allocator);
    defer graph.deinit();
    var plan = try analyze(std.testing.allocator, program, tokens, &graph);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("run", plan.root_name);
    try std.testing.expectEqualStrings("completion", plan.host_member);
    try std.testing.expectEqualStrings("[async-lower][future-read-0]completion", plan.async_import_name);
    try std.testing.expectEqual(@as(u32, 12), plan.payload.offset);
    try std.testing.expectEqual(@as(u32, 4), plan.payload.byte_size);
    try std.testing.expect(plan.await_token_index > 0);
    try std.testing.expect(plan.await_token_index < plan.cancel_token_index);
}

test "generated scalar async admission rejects a hand-written host copy" {
    const source =
        "completion = @host(\"do:generic-async-scalar-probe/host@0.1.0\", \"completion\", () -> Future<u32>)\n" ++
        "run() -> nil {\n" ++
        "    ready Future<u32> = completion()\n" ++
        "    value u32 = @await(ready)\n" ++
        "    pending Future<u32> = completion()\n" ++
        "    @cancel(pending)\n" ++
        "}\n" ++
        "start() {}\n";
    try expect_unsupported(source);
}

test "generated scalar async admission rejects a second await" {
    try expect_unsupported(
        "completion = @lib(\"./wit/scalar/do_generic_async_scalar_probe__host__probe.do\", completion)\n" ++
            "run() -> nil {\n" ++
            "    first Future<u32> = completion()\n" ++
            "    value u32 = @await(first)\n" ++
            "    second Future<u32> = completion()\n" ++
            "    @await(second)\n" ++
            "    pending Future<u32> = completion()\n" ++
            "    @cancel(pending)\n" ++
            "}\n" ++
            "start() {}\n",
    );
}

test "generated scalar async admission rejects a non-u32 payload" {
    try expect_unsupported_with_graph(
        "completion = @lib(\"./wit/scalar/do_generic_async_scalar_probe__host__probe.do\", completion)\n" ++
            "run() -> nil {\n" ++
            "    ready Future<i64> = completion()\n" ++
            "    value i64 = @await(ready)\n" ++
            "    pending Future<i64> = completion()\n" ++
            "    @cancel(pending)\n" ++
            "}\n" ++
            "start() {}\n",
    );
}

test "generated scalar async admission rejects a text payload" {
    try expect_unsupported_with_graph(
        "completion = @lib(\"./wit/scalar/do_generic_async_scalar_probe__host__probe.do\", completion)\n" ++
            "run() -> nil {\n" ++
            "    ready Future<text> = completion()\n" ++
            "    value text = @await(ready)\n" ++
            "    pending Future<text> = completion()\n" ++
            "    @cancel(pending)\n" ++
            "}\n" ++
            "start() {}\n",
    );
}

test "generated scalar async admission rejects timeout await" {
    try expect_unsupported_with_graph(
        "completion = @lib(\"./wit/scalar/do_generic_async_scalar_probe__host__probe.do\", completion)\n" ++
            "run() -> nil {\n" ++
            "    ready Future<u32> = completion()\n" ++
            "    value u32 = await(ready, 10)\n" ++
            "    pending Future<u32> = completion()\n" ++
            "    @cancel(pending)\n" ++
            "}\n" ++
            "start() {}\n",
    );
}

test "generated scalar async admission rejects an async root" {
    try expect_unsupported_with_graph(
        "completion = @lib(\"./wit/scalar/do_generic_async_scalar_probe__host__probe.do\", completion)\n" ++
            "async run() -> nil {\n" ++
            "    ready Future<u32> = completion()\n" ++
            "    value u32 = @await(ready)\n" ++
            "    pending Future<u32> = completion()\n" ++
            "    @cancel(pending)\n" ++
            "}\n" ++
            "start() {}\n",
    );
}

test "generated scalar async admission rejects implicit async creation" {
    try expect_unsupported_with_graph(
        "completion = @lib(\"./wit/scalar/do_generic_async_scalar_probe__host__probe.do\", completion)\n" ++
            "run() -> nil {\n" ++
            "    ready Future<u32> = @async(completion())\n" ++
            "    value u32 = @await(ready)\n" ++
            "    pending Future<u32> = completion()\n" ++
            "    @cancel(pending)\n" ++
            "}\n" ++
            "start() {}\n",
    );
}

test "generated scalar async admission rejects an unregistered locator" {
    try expect_unsupported_with_graph(
        "completion = @lib(\"./wit/do_unregistered_scalar_probe__host__probe.do\", completion)\n" ++
            "run() -> nil {\n" ++
            "    ready Future<u32> = completion()\n" ++
            "    value u32 = @await(ready)\n" ++
            "    pending Future<u32> = completion()\n" ++
            "    @cancel(pending)\n" ++
            "}\n" ++
            "start() {}\n",
    );
}

test "generated scalar async admission rejects resource and stream members" {
    try expect_unsupported_with_graph(
        "resource = @lib(\"./wit/scalar/do_generic_async_scalar_probe__host__probe.do\", resource)\n" ++
            "run() -> nil {\n" ++
            "    pending Future<u32> = resource()\n" ++
            "    @cancel(pending)\n" ++
            "}\n" ++
            "start() {}\n",
    );
    try expect_unsupported_with_graph(
        "stream = @lib(\"./wit/scalar/do_generic_async_scalar_probe__host__probe.do\", stream)\n" ++
            "run() -> nil {\n" ++
            "    pending Future<u32> = stream()\n" ++
            "    @cancel(pending)\n" ++
            "}\n" ++
            "start() {}\n",
    );
}

fn expect_unsupported(source: []const u8) !void {
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedGeneratedAsyncScalarShape, analyze(std.testing.allocator, program, tokens, null));
}

fn expect_unsupported_with_graph(source: []const u8) !void {
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var graph = try test_graph(std.testing.allocator);
    defer graph.deinit();
    try std.testing.expectError(error.UnsupportedGeneratedAsyncScalarShape, analyze(std.testing.allocator, program, tokens, &graph));
}

fn test_graph(allocator: std.mem.Allocator) !imports.ModuleGraph {
    const lowerings = try allocator.alloc(module_graph.GeneratedAsyncLowering, 1);
    errdefer allocator.free(lowerings);
    lowerings[0] = .{
        .locator = try allocator.dupe(u8, "do:generic-async-scalar-probe/host@0.1.0"),
        .member = try allocator.dupe(u8, "completion"),
        .source_signature = try allocator.dupe(u8, "() -> Future<u32>"),
        .wit_package = try allocator.dupe(u8, "do:generic-async-scalar-probe@0.1.0"),
        .wit_world = try allocator.dupe(u8, "probe"),
        .wit_interface = try allocator.dupe(u8, "host"),
        .wit_member = try allocator.dupe(u8, "completion"),
        .async_import_module = try allocator.dupe(u8, "do:generic-async-scalar-probe/host@0.1.0"),
        .async_import_name = try allocator.dupe(u8, "[async-lower][future-read-0]completion"),
        .completion = try allocator.dupe(u8, "completion"),
        .wit_sha256 = [_]u8{0} ** 32,
        .payload = .{
            .core_type = try allocator.dupe(u8, "i32"),
            .offset = 12,
            .byte_size = 4,
            .alignment = 4,
            .encoding = try allocator.dupe(u8, "core-u32"),
        },
    };
    return .{
        .allocator = allocator,
        .dep_root = "",
        .modules = &.{},
        .generated_async_lowerings = lowerings,
    };
}

pub const GeneratedAsyncScalarPlan = struct {
    root_name: []const u8,
    host_locator: []const u8,
    host_member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
    completion: []const u8,
    payload: generated_wit_manifest.GeneratedScalarPayload,
    await_token_index: usize,
    cancel_token_index: usize,

    pub fn deinit(self: *GeneratedAsyncScalarPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        allocator.free(self.host_locator);
        allocator.free(self.host_member);
        allocator.free(self.async_import_module);
        allocator.free(self.async_import_name);
        allocator.free(self.completion);
        allocator.free(self.payload.core_type);
        allocator.free(self.payload.encoding);
        self.* = undefined;
    }
};

pub fn analyze(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    graph_opt: ?*const imports.ModuleGraph,
) !GeneratedAsyncScalarPlan {
    if (graph_opt == null) return error.UnsupportedGeneratedAsyncScalarShape;
    for (program.func_sigs) |sig| {
        if (sig.is_async) return error.UnsupportedGeneratedAsyncScalarShape;
    }
    const root = find_function(tokens, "run") orelse return error.UnsupportedGeneratedAsyncScalarShape;
    if (root.is_async or !signature_is_unit(program, "run")) return error.UnsupportedGeneratedAsyncScalarShape;
    const host = find_generated_scalar_host_binding(tokens, graph_opt.?) orelse
        return error.UnsupportedGeneratedAsyncScalarShape;

    const body = tokens[root.body_start..root.body_end];
    var cursor: usize = 0;
    const first = parse_future_binding(body, cursor) orelse return error.UnsupportedGeneratedAsyncScalarShape;
    if (!std.mem.eql(u8, first.host_name, host.name)) return error.UnsupportedGeneratedAsyncScalarShape;
    cursor = first.next_idx;

    const await_call = parse_value_await(body, cursor, first.future_name) orelse
        return error.UnsupportedGeneratedAsyncScalarShape;
    cursor = await_call.next_idx;

    const second = parse_future_binding(body, cursor) orelse return error.UnsupportedGeneratedAsyncScalarShape;
    if (!std.mem.eql(u8, second.host_name, host.name) or
        std.mem.eql(u8, second.future_name, first.future_name)) return error.UnsupportedGeneratedAsyncScalarShape;
    cursor = second.next_idx;

    const cancel_call = parse_cancel(body, cursor, second.future_name) orelse
        return error.UnsupportedGeneratedAsyncScalarShape;
    if (cancel_call.next_idx != body.len) return error.UnsupportedGeneratedAsyncScalarShape;
    if (count_token_pair(tokens, "@", "async") != 0 or
        count_token_pair(tokens, "@", "await") != 1 or
        count_token_pair(tokens, "@", "cancel") != 1)
    {
        return error.UnsupportedGeneratedAsyncScalarShape;
    }

    return make_plan(allocator, root, host, await_call.token_index + root.body_start, cancel_call.token_index + root.body_start);
}

/// Token-only entry point used by target selection. The parser program is
/// still built here so the admission rules stay identical to `analyze`.
pub fn analyze_tokens(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    graph_opt: ?*const imports.ModuleGraph,
) !GeneratedAsyncScalarPlan {
    var program = try parser.parse_program(allocator, tokens, tokens.len);
    defer program.deinit(allocator);
    return analyze(allocator, program, tokens, graph_opt);
}

const FunctionRange = struct {
    name: []const u8,
    is_async: bool,
    body_start: usize,
    body_end: usize,
};

const HostBinding = struct {
    name: []const u8,
    lowering: module_graph.GeneratedAsyncLowering,
};

const FutureBinding = struct {
    future_name: []const u8,
    host_name: []const u8,
    next_idx: usize,
};

const ValueAwait = struct {
    token_index: usize,
    next_idx: usize,
};

const CancelCall = struct {
    token_index: usize,
    next_idx: usize,
};

fn make_plan(
    allocator: std.mem.Allocator,
    root: FunctionRange,
    host: HostBinding,
    await_token_index: usize,
    cancel_token_index: usize,
) !GeneratedAsyncScalarPlan {
    const root_name = try allocator.dupe(u8, root.name);
    errdefer allocator.free(root_name);
    const host_locator = try allocator.dupe(u8, host.lowering.locator);
    errdefer allocator.free(host_locator);
    const host_member = try allocator.dupe(u8, host.lowering.member);
    errdefer allocator.free(host_member);
    const async_import_module = try allocator.dupe(u8, host.lowering.async_import_module);
    errdefer allocator.free(async_import_module);
    const async_import_name = try allocator.dupe(u8, host.lowering.async_import_name);
    errdefer allocator.free(async_import_name);
    const completion = try allocator.dupe(u8, host.lowering.completion);
    errdefer allocator.free(completion);
    const payload = host.lowering.payload orelse return error.UnsupportedGeneratedAsyncScalarShape;
    const owned_payload = try clone_payload(allocator, payload);
    errdefer free_payload(allocator, owned_payload);
    return .{
        .root_name = root_name,
        .host_locator = host_locator,
        .host_member = host_member,
        .async_import_module = async_import_module,
        .async_import_name = async_import_name,
        .completion = completion,
        .payload = owned_payload,
        .await_token_index = await_token_index,
        .cancel_token_index = cancel_token_index,
    };
}

fn clone_payload(
    allocator: std.mem.Allocator,
    payload: generated_wit_manifest.GeneratedScalarPayload,
) !generated_wit_manifest.GeneratedScalarPayload {
    var owned = generated_wit_manifest.GeneratedScalarPayload{
        .core_type = "",
        .offset = payload.offset,
        .byte_size = payload.byte_size,
        .alignment = payload.alignment,
        .encoding = "",
    };
    errdefer free_payload(allocator, owned);
    owned.core_type = try allocator.dupe(u8, payload.core_type);
    owned.encoding = try allocator.dupe(u8, payload.encoding);
    return owned;
}

fn free_payload(allocator: std.mem.Allocator, payload: generated_wit_manifest.GeneratedScalarPayload) void {
    allocator.free(payload.core_type);
    allocator.free(payload.encoding);
}

fn find_generated_scalar_host_binding(tokens: []const lexer.Token, graph: *const imports.ModuleGraph) ?HostBinding {
    var found: ?HostBinding = null;
    for (graph.generated_async_lowerings) |lowering| {
        if (!is_pinned_scalar_lowering(lowering)) continue;
        var match: ?[]const u8 = null;
        var idx: usize = 0;
        while (idx < tokens.len) : (idx += 1) {
            const binding = parse_lib_binding_at(tokens, idx) orelse continue;
            if (!std.mem.eql(u8, binding.path, pinned_module_path) or
                !std.mem.eql(u8, binding.target, lowering.member)) continue;
            if (match != null) return null;
            match = binding.alias;
        }
        if (match) |name| {
            if (found != null) return null;
            found = .{ .name = name, .lowering = lowering };
        }
    }
    return found;
}

fn is_pinned_scalar_lowering(lowering: module_graph.GeneratedAsyncLowering) bool {
    const payload = lowering.payload orelse return false;
    return std.mem.eql(u8, lowering.locator, "do:generic-async-scalar-probe/host@0.1.0") and
        std.mem.eql(u8, lowering.member, "completion") and
        std.mem.eql(u8, lowering.source_signature, "() -> Future<u32>") and
        std.mem.eql(u8, lowering.wit_package, "do:generic-async-scalar-probe@0.1.0") and
        std.mem.eql(u8, lowering.wit_world, "probe") and
        std.mem.eql(u8, lowering.wit_interface, "host") and
        std.mem.eql(u8, lowering.wit_member, "completion") and
        std.mem.eql(u8, lowering.async_import_module, "do:generic-async-scalar-probe/host@0.1.0") and
        std.mem.eql(u8, lowering.async_import_name, "[async-lower][future-read-0]completion") and
        std.mem.eql(u8, lowering.completion, "completion") and
        std.mem.eql(u8, payload.core_type, "i32") and payload.offset == 12 and
        payload.byte_size == 4 and payload.alignment == 4 and
        std.mem.eql(u8, payload.encoding, "core-u32");
}

const LibBinding = struct {
    alias: []const u8,
    path: []const u8,
    target: []const u8,
};

fn parse_lib_binding_at(tokens: []const lexer.Token, start: usize) ?LibBinding {
    if (start + 8 >= tokens.len or tokens[start].kind != .ident or
        !tok_eq(tokens[start + 1], "=") or !tok_eq(tokens[start + 2], "@") or
        !tok_eq(tokens[start + 3], "lib") or !tok_eq(tokens[start + 4], "(") or
        tokens[start + 5].kind != .string or !tok_eq(tokens[start + 6], ",") or
        tokens[start + 7].kind != .ident or !tok_eq(tokens[start + 8], ")")) return null;
    return .{
        .alias = tokens[start].lexeme,
        .path = string_token_body(tokens[start + 5].lexeme) orelse return null,
        .target = tokens[start + 7].lexeme,
    };
}

fn parse_future_binding(tokens: []const lexer.Token, start: usize) ?FutureBinding {
    const line_end = find_line_end_idx(tokens, start);
    if (start + 8 >= line_end or tokens[start].kind != .ident or
        !tok_eq(tokens[start + 1], "Future") or !tok_eq(tokens[start + 2], "<") or
        !tok_eq(tokens[start + 3], "u32") or !tok_eq(tokens[start + 4], ">") or
        !tok_eq(tokens[start + 5], "=") or tokens[start + 6].kind != .ident or
        !tok_eq(tokens[start + 7], "(") or !tok_eq(tokens[start + 8], ")")) return null;
    return .{
        .future_name = tokens[start].lexeme,
        .host_name = tokens[start + 6].lexeme,
        .next_idx = line_end,
    };
}

fn parse_value_await(tokens: []const lexer.Token, start: usize, future_name: []const u8) ?ValueAwait {
    const line_end = find_line_end_idx(tokens, start);
    if (start + 7 >= line_end or tokens[start].kind != .ident or
        !tok_eq(tokens[start + 1], "u32") or !tok_eq(tokens[start + 2], "=") or
        !tok_eq(tokens[start + 3], "@") or !tok_eq(tokens[start + 4], "await") or
        !tok_eq(tokens[start + 5], "(") or tokens[start + 6].kind != .ident or
        !std.mem.eql(u8, tokens[start + 6].lexeme, future_name) or
        !tok_eq(tokens[start + 7], ")")) return null;
    return .{ .token_index = start + 3, .next_idx = line_end };
}

fn parse_cancel(tokens: []const lexer.Token, start: usize, future_name: []const u8) ?CancelCall {
    const line_end = find_line_end_idx(tokens, start);
    if (start + 4 >= line_end or !tok_eq(tokens[start], "@") or
        !tok_eq(tokens[start + 1], "cancel") or !tok_eq(tokens[start + 2], "(") or
        tokens[start + 3].kind != .ident or !std.mem.eql(u8, tokens[start + 3].lexeme, future_name) or
        !tok_eq(tokens[start + 4], ")")) return null;
    return .{ .token_index = start, .next_idx = line_end };
}

fn signature_is_unit(program: parser.Program, name: []const u8) bool {
    var found = false;
    for (program.func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, name)) continue;
        if (found or sig.is_async or sig.param_min != 0 or
            (sig.param_max orelse std.math.maxInt(usize)) != 0 or sig.return_arity != 0) return false;
        found = true;
    }
    return found;
}

fn find_function(tokens: []const lexer.Token, name: []const u8) ?FunctionRange {
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or tokens[idx].kind != .ident or
            !std.mem.eql(u8, tokens[idx].lexeme, name) or idx + 1 >= tokens.len or
            !tok_eq(tokens[idx + 1], "(")) continue;
        const close_params = find_matching(tokens, idx + 1, "(", ")") catch return null;
        var body_open = close_params + 1;
        while (body_open < tokens.len and !tok_eq(tokens[body_open], "{")) : (body_open += 1) {
            if (tokens[body_open].line != tokens[close_params].line) return null;
        }
        if (body_open >= tokens.len) return null;
        const body_end = find_matching(tokens, body_open, "{", "}") catch return null;
        return .{
            .name = tokens[idx].lexeme,
            .is_async = idx > 0 and tokens[idx - 1].line == tokens[idx].line and tok_eq(tokens[idx - 1], "async"),
            .body_start = body_open + 1,
            .body_end = body_end,
        };
    }
    return null;
}

fn count_token_pair(tokens: []const lexer.Token, first: []const u8, second: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, first) and idx + 1 < tokens.len and tok_eq(tokens[idx + 1], second)) count += 1;
    }
    return count;
}
