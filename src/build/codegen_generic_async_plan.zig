const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const imports = @import("imports.zig");
const module_graph = @import("module_graph.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const sema_tokens = @import("sema_tokens.zig");

const find_matching = sema_tokens.find_matching;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

pub const GenericAsyncSourceMode = enum {
    eager_synchronous,
    descriptor_async,
};

pub const GenericAsyncPlan = struct {
    root_name: []const u8,
    work_name: []const u8,
    await_future_name: []const u8,
    second_await_future_name: []const u8,
    cancel_future_name: []const u8,
    source_mode: GenericAsyncSourceMode,
    host_locator: []const u8,
    host_member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
    await_token_index: usize,
    second_await_token_index: usize,
    cancel_token_index: usize,

    pub fn deinit(self: *GenericAsyncPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        allocator.free(self.work_name);
        allocator.free(self.await_future_name);
        allocator.free(self.second_await_future_name);
        allocator.free(self.cancel_future_name);
        allocator.free(self.host_locator);
        allocator.free(self.host_member);
        allocator.free(self.async_import_module);
        allocator.free(self.async_import_name);
        self.* = undefined;
    }
};

test "generic async admission accepts the exact three-future slice" {
    const source = @embedFile("test/check/417_generic_async_single_future.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    var plan = try analyze(std.testing.allocator, program, tokens, null);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("run", plan.root_name);
    try std.testing.expectEqualStrings("work", plan.work_name);
    try std.testing.expectEqualStrings("ready", plan.await_future_name);
    try std.testing.expectEqualStrings("middle", plan.second_await_future_name);
    try std.testing.expectEqualStrings("pending", plan.cancel_future_name);
    try std.testing.expect(plan.await_token_index < plan.second_await_token_index);
    try std.testing.expect(plan.second_await_token_index < plan.cancel_token_index);
}

test "generic async admission accepts descriptor-backed async host futures" {
    const source = @embedFile("test/check/427_generic_async_runtime_contract.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    var plan = try analyze(std.testing.allocator, program, tokens, null);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("run", plan.root_name);
    try std.testing.expectEqualStrings("work", plan.work_name);
    try std.testing.expectEqualStrings("middle", plan.second_await_future_name);
    try std.testing.expect(@hasField(@TypeOf(plan), "source_mode"));
    if (@hasField(@TypeOf(plan), "source_mode")) {
        try std.testing.expectEqualStrings("descriptor_async", @tagName(@field(plan, "source_mode")));
    }
    try std.testing.expect(@hasField(@TypeOf(plan), "host_locator"));
    if (@hasField(@TypeOf(plan), "host_locator")) {
        try std.testing.expectEqualStrings(
            "do:generic-async-runtime-probe/host@0.1.0",
            @field(plan, "host_locator"),
        );
    }
    try std.testing.expect(@hasField(@TypeOf(plan), "host_member"));
    if (@hasField(@TypeOf(plan), "host_member")) {
        try std.testing.expectEqualStrings("work", @field(plan, "host_member"));
    }
}

test "generic async admission rejects payload futures" {
    try expect_unsupported(
        \\work() -> i32 { return 1 }
        \\run() -> nil {
        \\    pending Future<i32> = @async(work())
        \\    @await(pending)
        \\    other Future<nil> = @async(work())
        \\    @cancel(other)
        \\}
        \\start() {}
    );
}

test "generic async admission rejects stream operations" {
    try expect_unsupported(
        \\work() -> nil { return }
        \\run() -> nil {
        \\    stream Stream<u8> = @async(work())
        \\    @await(stream)
        \\    pending Future<nil> = @async(work())
        \\    @cancel(pending)
        \\}
        \\start() {}
    );
}

test "generic async admission rejects multiple awaits" {
    try expect_unsupported(
        \\work() -> nil { return }
        \\run() -> nil {
        \\    first Future<nil> = @async(work())
        \\    @await(first)
        \\    second Future<nil> = @async(work())
        \\    @await(second)
        \\    third Future<nil> = @async(work())
        \\    @await(third)
        \\    pending Future<nil> = @async(work())
        \\    @cancel(pending)
        \\}
        \\start() {}
    );
}

test "generic async admission rejects async function declarations" {
    try expect_unsupported(
        \\work() -> nil { return }
        \\async run() -> nil {
        \\    ready Future<nil> = @async(work())
        \\    @await(ready)
        \\    pending Future<nil> = @async(work())
        \\    @cancel(pending)
        \\}
        \\start() {}
    );
}

fn expect_unsupported(source: []const u8) !void {
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedGenericAsyncShape, analyze(std.testing.allocator, program, tokens, null));
}

pub fn analyze(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    graph_opt: ?*const imports.ModuleGraph,
) !GenericAsyncPlan {
    for (program.func_sigs) |sig| {
        if (sig.is_async) return error.UnsupportedGenericAsyncShape;
    }
    if (graph_opt) |graph| {
        for (graph.modules) |module| {
            if (module.tokens.len == tokens.len and module.tokens.ptr == tokens.ptr) continue;
            if (contains_async_operation(module.tokens)) return error.UnsupportedGenericAsyncShape;
        }
    }

    const root = find_function(tokens, "run") orelse return error.UnsupportedGenericAsyncShape;
    if (root.is_async or !signature_is_unit(program, "run")) return error.UnsupportedGenericAsyncShape;

    if (graph_opt) |graph| {
        if (find_generated_async_host_binding(tokens, graph)) |host| {
            return analyze_async_host(allocator, tokens, root, .{
                .name = host.name,
                .locator = host.lowering.locator,
                .member = host.lowering.member,
                .async_import_module = host.lowering.async_import_module,
                .async_import_name = host.lowering.async_import_name,
            });
        }
    }

    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);

    if (find_descriptor_async_host_binding(tokens, registry)) |host| {
        return analyze_descriptor_async(allocator, tokens, root, host);
    }

    const work = find_function(tokens, "work") orelse return error.UnsupportedGenericAsyncShape;
    if (work.is_async or !signature_is_unit(program, "work")) return error.UnsupportedGenericAsyncShape;
    return analyze_eager_synchronous(allocator, tokens, root, work);
}

fn analyze_eager_synchronous(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    root: FunctionRange,
    work: FunctionRange,
) !GenericAsyncPlan {
    const body = tokens[root.body_start..root.body_end];
    var cursor: usize = 0;
    const first = parse_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, first.work_name, work.name)) return error.UnsupportedGenericAsyncShape;
    cursor = first.next_idx;

    const first_await_call = parse_intrinsic_call(body, cursor, "await") orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, first_await_call.operand, first.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = first_await_call.next_idx;

    const second = parse_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, second.work_name, work.name) or
        std.mem.eql(u8, second.future_name, first.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = second.next_idx;

    const second_await_call = parse_intrinsic_call(body, cursor, "await") orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, second_await_call.operand, second.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = second_await_call.next_idx;

    const third = parse_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, third.work_name, work.name) or
        std.mem.eql(u8, third.future_name, first.future_name) or
        std.mem.eql(u8, third.future_name, second.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = third.next_idx;

    const cancel_call = parse_intrinsic_call(body, cursor, "cancel") orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, cancel_call.operand, third.future_name) or cancel_call.next_idx != body.len) {
        return error.UnsupportedGenericAsyncShape;
    }

    if (count_intrinsic(tokens, "async") != 3 or count_intrinsic(tokens, "await") != 2 or count_intrinsic(tokens, "cancel") != 1) {
        return error.UnsupportedGenericAsyncShape;
    }

    return make_plan(
        allocator,
        root,
        work.name,
        first,
        second,
        third,
        first_await_call,
        second_await_call,
        cancel_call,
        .eager_synchronous,
        "",
        "",
        "",
        "",
    );
}

fn analyze_descriptor_async(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    root: FunctionRange,
    host: DescriptorAsyncHostBinding,
) !GenericAsyncPlan {
    const descriptor = host.descriptor;
    return analyze_async_host(allocator, tokens, root, .{
        .name = host.name,
        .locator = descriptor.locator,
        .member = descriptor.member,
        .async_import_module = descriptor.canonical.async_import_module,
        .async_import_name = descriptor.canonical.async_import_name,
    });
}

fn analyze_async_host(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    root: FunctionRange,
    host: AsyncHostMetadata,
) !GenericAsyncPlan {
    const body = tokens[root.body_start..root.body_end];
    var cursor: usize = 0;
    const first = parse_descriptor_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, first.work_name, host.name)) return error.UnsupportedGenericAsyncShape;
    cursor = first.next_idx;

    const first_await_call = parse_intrinsic_call(body, cursor, "await") orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, first_await_call.operand, first.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = first_await_call.next_idx;

    const second = parse_descriptor_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, second.work_name, host.name) or
        std.mem.eql(u8, second.future_name, first.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = second.next_idx;

    const second_await_call = parse_intrinsic_call(body, cursor, "await") orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, second_await_call.operand, second.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = second_await_call.next_idx;

    const third = parse_descriptor_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, third.work_name, host.name) or
        std.mem.eql(u8, third.future_name, first.future_name) or
        std.mem.eql(u8, third.future_name, second.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = third.next_idx;

    const cancel_call = parse_intrinsic_call(body, cursor, "cancel") orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, cancel_call.operand, third.future_name) or cancel_call.next_idx != body.len) {
        return error.UnsupportedGenericAsyncShape;
    }

    if (count_intrinsic(tokens, "async") != 0 or count_intrinsic(tokens, "await") != 2 or count_intrinsic(tokens, "cancel") != 1) {
        return error.UnsupportedGenericAsyncShape;
    }

    return make_plan(
        allocator,
        root,
        host.name,
        first,
        second,
        third,
        first_await_call,
        second_await_call,
        cancel_call,
        .descriptor_async,
        host.locator,
        host.member,
        host.async_import_module,
        host.async_import_name,
    );
}

fn make_plan(
    allocator: std.mem.Allocator,
    root: FunctionRange,
    work_name: []const u8,
    first: FutureBinding,
    second: FutureBinding,
    third: FutureBinding,
    first_await_call: IntrinsicCall,
    second_await_call: IntrinsicCall,
    cancel_call: IntrinsicCall,
    source_mode: GenericAsyncSourceMode,
    host_locator: []const u8,
    host_member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
) !GenericAsyncPlan {
    const root_name = try allocator.dupe(u8, root.name);
    errdefer allocator.free(root_name);
    const owned_work_name = try allocator.dupe(u8, work_name);
    errdefer allocator.free(owned_work_name);
    const await_future_name = try allocator.dupe(u8, first.future_name);
    errdefer allocator.free(await_future_name);
    const second_await_future_name = try allocator.dupe(u8, second.future_name);
    errdefer allocator.free(second_await_future_name);
    const cancel_future_name = try allocator.dupe(u8, third.future_name);
    errdefer allocator.free(cancel_future_name);
    const owned_host_locator = try allocator.dupe(u8, host_locator);
    errdefer allocator.free(owned_host_locator);
    const owned_host_member = try allocator.dupe(u8, host_member);
    errdefer allocator.free(owned_host_member);
    const owned_async_import_module = try allocator.dupe(u8, async_import_module);
    errdefer allocator.free(owned_async_import_module);
    const owned_async_import_name = try allocator.dupe(u8, async_import_name);
    errdefer allocator.free(owned_async_import_name);

    return .{
        .root_name = root_name,
        .work_name = owned_work_name,
        .await_future_name = await_future_name,
        .second_await_future_name = second_await_future_name,
        .cancel_future_name = cancel_future_name,
        .source_mode = source_mode,
        .host_locator = owned_host_locator,
        .host_member = owned_host_member,
        .async_import_module = owned_async_import_module,
        .async_import_name = owned_async_import_name,
        .await_token_index = root.body_start + first_await_call.token_index,
        .second_await_token_index = root.body_start + second_await_call.token_index,
        .cancel_token_index = root.body_start + cancel_call.token_index,
    };
}

const FunctionRange = struct {
    name: []const u8,
    is_async: bool,
    body_start: usize,
    body_end: usize,
};

const FutureBinding = struct {
    future_name: []const u8,
    work_name: []const u8,
    next_idx: usize,
};

const DescriptorAsyncHostBinding = struct {
    name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
};

const AsyncHostMetadata = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
};

const GeneratedAsyncHostBinding = struct {
    name: []const u8,
    lowering: module_graph.GeneratedAsyncLowering,
};

const IntrinsicCall = struct {
    token_index: usize,
    operand: []const u8,
    next_idx: usize,
};

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
        if (depth != 0 or tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, name) or
            idx + 1 >= tokens.len or !tok_eq(tokens[idx + 1], "(")) continue;

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

fn find_descriptor_async_host_binding(
    tokens: []const lexer.Token,
    registry: p3_async_manifest.Registry,
) ?DescriptorAsyncHostBinding {
    const locator_expected = "do:generic-async-runtime-probe/host@0.1.0";
    const member_expected = "work";
    var found: ?DescriptorAsyncHostBinding = null;
    var idx: usize = 0;
    while (idx + 14 < tokens.len) : (idx += 1) {
        const binding = parse_descriptor_host_binding_at(tokens, idx) orelse continue;
        if (!std.mem.eql(u8, binding.locator, locator_expected) or
            !std.mem.eql(u8, binding.member, member_expected)) continue;
        const descriptor = registry.find(binding.locator, binding.member) orelse continue;
        if (!valid_generic_async_descriptor(descriptor)) continue;
        if (found != null) return null;
        found = .{ .name = binding.name, .descriptor = descriptor };
    }
    return found;
}

fn find_generated_async_host_binding(
    tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
) ?GeneratedAsyncHostBinding {
    var found: ?GeneratedAsyncHostBinding = null;
    for (graph.generated_async_lowerings) |lowering| {
        var match: ?[]const u8 = null;
        var idx: usize = 0;
        while (idx < tokens.len) : (idx += 1) {
            if (parse_generated_host_binding_at(tokens, idx)) |binding| {
                if (!std.mem.eql(u8, binding.locator, lowering.locator) or
                    !std.mem.eql(u8, binding.member, lowering.member)) continue;
                if (match != null) return null;
                match = binding.name;
                continue;
            }
            if (parse_generated_lib_binding_at(tokens, idx)) |binding| {
                if (!std.mem.startsWith(u8, binding.path, "./wit/") or
                    !std.mem.endsWith(u8, binding.path, ".do") or
                    !std.mem.eql(u8, binding.target, lowering.member)) continue;
                if (match != null) return null;
                match = binding.alias;
            }
        }
        if (match) |name| {
            if (found != null) return null;
            found = .{ .name = name, .lowering = lowering };
        }
    }
    return found;
}

const GeneratedHostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
};

fn parse_generated_host_binding_at(tokens: []const lexer.Token, idx: usize) ?GeneratedHostBinding {
    if (idx + 17 >= tokens.len or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
        !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host_func") or
        !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
        !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
        !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or
        !tok_eq(tokens[idx + 10], ")") or !tok_eq(tokens[idx + 11], "-") or
        !tok_eq(tokens[idx + 12], ">") or !tok_eq(tokens[idx + 13], "Future") or
        !tok_eq(tokens[idx + 14], "<") or !tok_eq(tokens[idx + 15], "nil") or
        !tok_eq(tokens[idx + 16], ">") or !tok_eq(tokens[idx + 17], ")")) return null;
    const locator = string_token_body(tokens[idx + 5].lexeme) orelse return null;
    const member = string_token_body(tokens[idx + 7].lexeme) orelse return null;
    return .{ .name = tokens[idx].lexeme, .locator = locator, .member = member };
}

const GeneratedLibBinding = struct {
    alias: []const u8,
    path: []const u8,
    target: []const u8,
};

fn parse_generated_lib_binding_at(tokens: []const lexer.Token, idx: usize) ?GeneratedLibBinding {
    if (idx + 8 >= tokens.len or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
        !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "lib") or
        !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
        !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .ident or
        !tok_eq(tokens[idx + 8], ")")) return null;
    const path = string_token_body(tokens[idx + 5].lexeme) orelse return null;
    return .{ .alias = tokens[idx].lexeme, .path = path, .target = tokens[idx + 7].lexeme };
}

const DescriptorHostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
};

fn parse_descriptor_host_binding_at(tokens: []const lexer.Token, idx: usize) ?DescriptorHostBinding {
    if (idx + 14 >= tokens.len or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
        !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host_async_func") or
        !tok_eq(tokens[idx + 4], "(") or !tok_eq(tokens[idx + 6], ",") or
        !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or
        !tok_eq(tokens[idx + 10], ")") or !tok_eq(tokens[idx + 11], "-") or
        !tok_eq(tokens[idx + 12], ">") or !tok_eq(tokens[idx + 13], "nil") or
        !tok_eq(tokens[idx + 14], ")")) return null;
    const locator = string_token_body(tokens[idx + 5].lexeme) orelse return null;
    const member = string_token_body(tokens[idx + 7].lexeme) orelse return null;
    return .{ .name = tokens[idx].lexeme, .locator = locator, .member = member };
}

fn valid_generic_async_descriptor(descriptor: p3_async_manifest.Descriptor) bool {
    return std.mem.eql(u8, descriptor.effect, "async") and
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

fn parse_future_binding(tokens: []const lexer.Token, start_idx: usize) ?FutureBinding {
    const line_end = find_line_end_idx(tokens, start_idx);
    if (start_idx + 8 >= line_end or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "Future") or !tok_eq(tokens[start_idx + 2], "<") or
        !tok_eq(tokens[start_idx + 3], "nil") or !tok_eq(tokens[start_idx + 4], ">") or
        !tok_eq(tokens[start_idx + 5], "=") or !tok_eq(tokens[start_idx + 6], "@") or
        !tok_eq(tokens[start_idx + 7], "async") or !tok_eq(tokens[start_idx + 8], "(")) return null;

    const outer_close = find_matching(tokens, start_idx + 8, "(", ")") catch return null;
    if (outer_close + 1 != line_end or tokens[start_idx + 9].kind != .ident or
        !tok_eq(tokens[start_idx + 10], "(") or !tok_eq(tokens[start_idx + 11], ")") or
        !tok_eq(tokens[outer_close], ")")) return null;
    return .{
        .future_name = tokens[start_idx].lexeme,
        .work_name = tokens[start_idx + 9].lexeme,
        .next_idx = line_end,
    };
}

fn parse_descriptor_future_binding(tokens: []const lexer.Token, start_idx: usize) ?FutureBinding {
    const line_end = find_line_end_idx(tokens, start_idx);
    if (start_idx + 8 >= line_end or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "Future") or !tok_eq(tokens[start_idx + 2], "<") or
        !tok_eq(tokens[start_idx + 3], "nil") or !tok_eq(tokens[start_idx + 4], ">") or
        !tok_eq(tokens[start_idx + 5], "=") or tokens[start_idx + 6].kind != .ident or
        !tok_eq(tokens[start_idx + 7], "(") or !tok_eq(tokens[start_idx + 8], ")")) return null;
    return .{
        .future_name = tokens[start_idx].lexeme,
        .work_name = tokens[start_idx + 6].lexeme,
        .next_idx = line_end,
    };
}

fn parse_intrinsic_call(tokens: []const lexer.Token, start_idx: usize, name: []const u8) ?IntrinsicCall {
    const line_end = find_line_end_idx(tokens, start_idx);
    if (start_idx + 5 != line_end or !tok_eq(tokens[start_idx], "@") or
        !std.mem.eql(u8, tokens[start_idx + 1].lexeme, name) or !tok_eq(tokens[start_idx + 2], "(") or
        tokens[start_idx + 3].kind != .ident or !tok_eq(tokens[start_idx + 4], ")")) return null;
    return .{ .token_index = start_idx, .operand = tokens[start_idx + 3].lexeme, .next_idx = line_end };
}

fn contains_async_operation(tokens: []const lexer.Token) bool {
    return count_intrinsic(tokens, "async") != 0 or count_intrinsic(tokens, "await") != 0 or count_intrinsic(tokens, "cancel") != 0;
}

fn count_intrinsic(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (!tok_eq(token, "@") or idx + 1 >= tokens.len or !std.mem.eql(u8, tokens[idx + 1].lexeme, name)) continue;
        count += 1;
    }
    return count;
}
