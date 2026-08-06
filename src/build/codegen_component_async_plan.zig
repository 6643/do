const std = @import("std");
const lexer = @import("lexer.zig");
const async_model = @import("codegen_async_model.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_model = @import("codegen_model.zig");
const imports = @import("imports.zig");
const module_graph = @import("module_graph.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const generated_async_scalar_plan = @import("codegen_generated_async_scalar_plan.zig");

pub const GeneratedAsyncScalarPlan = generated_async_scalar_plan.GeneratedAsyncScalarPlan;

pub fn analyze_generated_async_scalar(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    graph_opt: ?*const imports.ModuleGraph,
) !GeneratedAsyncScalarPlan {
    return generated_async_scalar_plan.analyze_tokens(allocator, tokens, graph_opt);
}

pub const TerminalAction = enum {
    await,
    cancel,
    return_await,
};

pub const PayloadShape = enum {
    scalar_unit,
    scalar_result,
    resource_result_2word,
};

pub const GenericAsyncComponentPlan = struct {
    root_name: []const u8,
    work_name: []const u8,
    host_locator: []const u8,
    host_member: []const u8,
    source_mode: GenericAsyncSourceMode,
    async_import_module: []const u8,
    async_import_name: []const u8,

    pub fn deinit(self: *GenericAsyncComponentPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        allocator.free(self.work_name);
        allocator.free(self.host_locator);
        allocator.free(self.host_member);
        allocator.free(self.async_import_module);
        allocator.free(self.async_import_name);
        self.* = undefined;
    }
};

pub const GenericAsyncSourceMode = enum {
    eager_synchronous,
    descriptor_async,
};

/// Admit only the test-world shape used by the generic async Component gate.
/// This is intentionally separate from descriptor-specific WIT lowering.
pub fn analyze_generic_async_component(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_graph_opt: ?*const imports.ModuleGraph,
) !GenericAsyncComponentPlan {
    const root = find_generic_async_root(tokens) orelse return error.UnsupportedGenericAsyncComponent;
    if (root.is_async) return error.UnsupportedGenericAsyncComponent;

    if (module_graph_opt) |graph| {
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

    if (find_generic_async_host_binding(tokens)) |host| {
        return analyze_eager_generic_async(allocator, tokens, root, host);
    }

    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const host = find_generic_async_descriptor_host_binding(tokens, registry) orelse return error.UnsupportedGenericAsyncComponent;
    const descriptor = host.descriptor;
    return analyze_async_host(allocator, tokens, root, .{
        .name = host.name,
        .locator = host.locator,
        .member = host.member,
        .async_import_module = descriptor.canonical.async_import_module,
        .async_import_name = descriptor.canonical.async_import_name,
    });
}

fn analyze_async_host(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    root: GenericAsyncRoot,
    host: AsyncHostMetadata,
) !GenericAsyncComponentPlan {
    const body = tokens[root.body_start..root.body_end];
    var cursor: usize = 0;
    const first = parse_generic_async_descriptor_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncComponent;
    if (!std.mem.eql(u8, first.host_name, host.name)) return error.UnsupportedGenericAsyncComponent;
    cursor = first.next_idx;
    const await_end = parse_generic_async_intrinsic(body, cursor, "await", first.future_name) orelse return error.UnsupportedGenericAsyncComponent;
    cursor = await_end;
    const second = parse_generic_async_descriptor_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncComponent;
    if (!std.mem.eql(u8, second.host_name, host.name) or std.mem.eql(u8, first.future_name, second.future_name)) {
        return error.UnsupportedGenericAsyncComponent;
    }
    cursor = second.next_idx;
    const second_await_end = parse_generic_async_intrinsic(body, cursor, "await", second.future_name) orelse return error.UnsupportedGenericAsyncComponent;
    cursor = second_await_end;
    const third = parse_generic_async_descriptor_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncComponent;
    if (!std.mem.eql(u8, third.host_name, host.name) or
        std.mem.eql(u8, third.future_name, first.future_name) or
        std.mem.eql(u8, third.future_name, second.future_name))
    {
        return error.UnsupportedGenericAsyncComponent;
    }
    cursor = third.next_idx;
    const cancel_end = parse_generic_async_intrinsic(body, cursor, "cancel", third.future_name) orelse return error.UnsupportedGenericAsyncComponent;
    if (cancel_end != body.len) return error.UnsupportedGenericAsyncComponent;
    if (count_token_pair(tokens, "@", "async") != 0 or
        count_token_pair(tokens, "@", "await") != 2 or
        count_token_pair(tokens, "@", "cancel") != 1)
    {
        return error.UnsupportedGenericAsyncComponent;
    }

    return make_async_host_plan(allocator, root, host.name, host.locator, host.member, host.async_import_module, host.async_import_name);
}

fn analyze_eager_generic_async(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    root: GenericAsyncRoot,
    host: GenericAsyncHostBinding,
) !GenericAsyncComponentPlan {
    const body = tokens[root.body_start..root.body_end];
    var cursor: usize = 0;
    const first = parse_generic_async_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncComponent;
    if (!std.mem.eql(u8, first.host_name, host.name)) return error.UnsupportedGenericAsyncComponent;
    cursor = first.next_idx;
    const await_end = parse_generic_async_intrinsic(body, cursor, "await", first.future_name) orelse return error.UnsupportedGenericAsyncComponent;
    cursor = await_end;
    const second = parse_generic_async_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncComponent;
    if (!std.mem.eql(u8, second.host_name, host.name) or std.mem.eql(u8, first.future_name, second.future_name)) {
        return error.UnsupportedGenericAsyncComponent;
    }
    cursor = second.next_idx;
    const second_await_end = parse_generic_async_intrinsic(body, cursor, "await", second.future_name) orelse return error.UnsupportedGenericAsyncComponent;
    cursor = second_await_end;
    const third = parse_generic_async_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncComponent;
    if (!std.mem.eql(u8, third.host_name, host.name) or
        std.mem.eql(u8, third.future_name, first.future_name) or
        std.mem.eql(u8, third.future_name, second.future_name))
    {
        return error.UnsupportedGenericAsyncComponent;
    }
    cursor = third.next_idx;
    const cancel_end = parse_generic_async_intrinsic(body, cursor, "cancel", third.future_name) orelse return error.UnsupportedGenericAsyncComponent;
    if (cancel_end != body.len) return error.UnsupportedGenericAsyncComponent;
    if (count_token_pair(tokens, "@", "async") != 3 or
        count_token_pair(tokens, "@", "await") != 2 or
        count_token_pair(tokens, "@", "cancel") != 1)
    {
        return error.UnsupportedGenericAsyncComponent;
    }

    const root_name = try allocator.dupe(u8, root.name);
    errdefer allocator.free(root_name);
    const work_name = try allocator.dupe(u8, host.name);
    errdefer allocator.free(work_name);
    const host_locator = try allocator.dupe(u8, host.locator);
    errdefer allocator.free(host_locator);
    const host_member = try allocator.dupe(u8, host.member);
    errdefer allocator.free(host_member);
    const async_import_module = try allocator.dupe(u8, "");
    errdefer allocator.free(async_import_module);
    const async_import_name = try allocator.dupe(u8, "");
    errdefer allocator.free(async_import_name);
    return .{
        .root_name = root_name,
        .work_name = work_name,
        .host_locator = host_locator,
        .host_member = host_member,
        .source_mode = .eager_synchronous,
        .async_import_module = async_import_module,
        .async_import_name = async_import_name,
    };
}

fn make_async_host_plan(
    allocator: std.mem.Allocator,
    root: GenericAsyncRoot,
    work_name: []const u8,
    host_locator: []const u8,
    host_member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
) !GenericAsyncComponentPlan {
    const root_name = try allocator.dupe(u8, root.name);
    errdefer allocator.free(root_name);
    const owned_work_name = try allocator.dupe(u8, work_name);
    errdefer allocator.free(owned_work_name);
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
        .host_locator = owned_host_locator,
        .host_member = owned_host_member,
        .source_mode = .descriptor_async,
        .async_import_module = owned_async_import_module,
        .async_import_name = owned_async_import_name,
    };
}

const GenericAsyncHostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
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

const GenericAsyncDescriptorHostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
    descriptor: p3_async_manifest.Descriptor,
};

const GenericAsyncRoot = struct {
    name: []const u8,
    body_start: usize,
    body_end: usize,
    is_async: bool,
};

const GenericAsyncFuture = struct {
    future_name: []const u8,
    host_name: []const u8,
    next_idx: usize,
};

fn find_generic_async_host_binding(tokens: []const lexer.Token) ?GenericAsyncHostBinding {
    const expected_locator = "do:generic-async-probe/host@0.1.0";
    const expected_member = "work";
    var idx: usize = 0;
    while (idx + 14 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
            !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host") or
            !tok_eq(tokens[idx + 4], "(") or !tok_eq(tokens[idx + 6], ",") or
            !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or
            !tok_eq(tokens[idx + 10], ")") or !tok_eq(tokens[idx + 11], "-") or
            !tok_eq(tokens[idx + 12], ">") or !tok_eq(tokens[idx + 13], "nil") or
            !tok_eq(tokens[idx + 14], ")")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        const member = string_token_body(tokens[idx + 7]) orelse continue;
        if (!std.mem.eql(u8, locator, expected_locator) or !std.mem.eql(u8, member, expected_member)) continue;
        return .{ .name = tokens[idx].lexeme, .locator = locator, .member = member };
    }
    return null;
}

fn find_generic_async_descriptor_host_binding(
    tokens: []const lexer.Token,
    registry: p3_async_manifest.Registry,
) ?GenericAsyncDescriptorHostBinding {
    var found: ?GenericAsyncDescriptorHostBinding = null;
    var idx: usize = 0;
    while (idx + 14 < tokens.len) : (idx += 1) {
        const binding = parse_generic_async_host_binding_at(tokens, idx) orelse continue;
        const descriptor = registry.find(binding.locator, binding.member) orelse continue;
        if (!valid_generic_async_descriptor(descriptor)) continue;
        if (found != null) return null;
        found = .{
            .name = binding.name,
            .locator = binding.locator,
            .member = binding.member,
            .descriptor = descriptor,
        };
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
        !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host") or
        !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
        !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
        !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or
        !tok_eq(tokens[idx + 10], ")") or !tok_eq(tokens[idx + 11], "-") or
        !tok_eq(tokens[idx + 12], ">") or !tok_eq(tokens[idx + 13], "Future") or
        !tok_eq(tokens[idx + 14], "<") or !tok_eq(tokens[idx + 15], "nil") or
        !tok_eq(tokens[idx + 16], ">") or !tok_eq(tokens[idx + 17], ")")) return null;
    const locator = string_token_body(tokens[idx + 5]) orelse return null;
    const member = string_token_body(tokens[idx + 7]) orelse return null;
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
    const path = string_token_body(tokens[idx + 5]) orelse return null;
    return .{ .alias = tokens[idx].lexeme, .path = path, .target = tokens[idx + 7].lexeme };
}

fn parse_generic_async_host_binding_at(tokens: []const lexer.Token, idx: usize) ?GenericAsyncHostBinding {
    if (idx + 14 >= tokens.len or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
        !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host") or
        !tok_eq(tokens[idx + 4], "(") or !tok_eq(tokens[idx + 6], ",") or
        !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or
        !tok_eq(tokens[idx + 10], ")") or !tok_eq(tokens[idx + 11], "-") or
        !tok_eq(tokens[idx + 12], ">") or !tok_eq(tokens[idx + 13], "nil") or
        !tok_eq(tokens[idx + 14], ")")) return null;
    const locator = string_token_body(tokens[idx + 5]) orelse return null;
    const member = string_token_body(tokens[idx + 7]) orelse return null;
    return .{ .name = tokens[idx].lexeme, .locator = locator, .member = member };
}

fn valid_generic_async_descriptor(descriptor: p3_async_manifest.Descriptor) bool {
    return std.mem.eql(u8, descriptor.locator, "do:generic-async-runtime-probe/host@0.1.0") and
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

fn find_generic_async_root(tokens: []const lexer.Token) ?GenericAsyncRoot {
    var idx: usize = 0;
    while (idx + 6 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, "run") or
            !tok_eq(tokens[idx + 1], "(") or !tok_eq(tokens[idx + 2], ")") or
            !tok_eq(tokens[idx + 3], "-") or !tok_eq(tokens[idx + 4], ">") or
            !tok_eq(tokens[idx + 5], "nil") or !tok_eq(tokens[idx + 6], "{")) continue;
        const body_end = find_matching(tokens, idx + 6, "{", "}") orelse return null;
        return .{
            .name = tokens[idx].lexeme,
            .body_start = idx + 7,
            .body_end = body_end,
            .is_async = idx > 0 and tok_eq(tokens[idx - 1], "async"),
        };
    }
    return null;
}

fn parse_generic_async_future_binding(tokens: []const lexer.Token, idx: usize) ?GenericAsyncFuture {
    if (idx + 12 >= tokens.len or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or
        !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "nil") or !tok_eq(tokens[idx + 4], ">") or
        !tok_eq(tokens[idx + 5], "=") or !tok_eq(tokens[idx + 6], "@") or !tok_eq(tokens[idx + 7], "async") or
        !tok_eq(tokens[idx + 8], "(") or tokens[idx + 9].kind != .ident or !tok_eq(tokens[idx + 10], "(") or
        !tok_eq(tokens[idx + 11], ")") or !tok_eq(tokens[idx + 12], ")")) return null;
    return .{ .future_name = tokens[idx].lexeme, .host_name = tokens[idx + 9].lexeme, .next_idx = idx + 13 };
}

fn parse_generic_async_descriptor_future_binding(tokens: []const lexer.Token, idx: usize) ?GenericAsyncFuture {
    if (idx + 8 >= tokens.len or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or
        !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "nil") or !tok_eq(tokens[idx + 4], ">") or
        !tok_eq(tokens[idx + 5], "=") or tokens[idx + 6].kind != .ident or !tok_eq(tokens[idx + 7], "(") or
        !tok_eq(tokens[idx + 8], ")")) return null;
    return .{ .future_name = tokens[idx].lexeme, .host_name = tokens[idx + 6].lexeme, .next_idx = idx + 9 };
}

fn parse_generic_async_intrinsic(tokens: []const lexer.Token, idx: usize, name: []const u8, operand: []const u8) ?usize {
    if (idx + 4 >= tokens.len or !tok_eq(tokens[idx], "@") or !std.mem.eql(u8, tokens[idx + 1].lexeme, name) or
        !tok_eq(tokens[idx + 2], "(") or tokens[idx + 3].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 3].lexeme, operand) or !tok_eq(tokens[idx + 4], ")")) return null;
    return idx + 5;
}

fn count_token_pair(tokens: []const lexer.Token, first: []const u8, second: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, first) and idx + 1 < tokens.len and tok_eq(tokens[idx + 1], second)) count += 1;
    }
    return count;
}

pub const Parameter = struct {
    name: []const u8,
    storage: async_model.FrameSlotStorage,
};

pub const ScalarArgument = union(enum) {
    parameter,
    u64_literal: u64,
    u64_add_parameter_literal: u64,
};

pub const PostAwaitComputation = struct {
    source_name: []const u8,
    result_name: []const u8,
    addend: u64,
};

pub const ControlFlow = union(enum) {
    linear,
    if_eq_parameter_literal: u64,
    loop_countdown: LoopCountdown,
};

pub const LoopCountdown = struct {
    counter_name: []const u8,
    initial: LoopCountdownInitial,
    host_argument: LoopCountdownHostArgument,
    pre_guard: bool,
};

pub const LoopCountdownInitial = union(enum) {
    u64_literal: u64,
    parameter,
    parameter_add_u64_literal: u64,
};

pub const LoopCountdownHostArgument = enum {
    parameter,
    counter,
};

pub const Operation = struct {
    descriptor: p3_async_manifest.Descriptor,
    future_name: []const u8,
    argument_name: []const u8,
    argument: ScalarArgument,
    payload_shape: PayloadShape,
    result_payload: ?p3_async_manifest.ResultPayload,
    error_variants: []const p3_async_manifest.ErrorVariantPayload = &.{},
};

pub const ComponentAsyncFunctionPlan = struct {
    export_name: []const u8,
    parameter: Parameter,
    operations: []Operation,
    control: ControlFlow,
    terminal: TerminalAction,
    post_await: ?PostAwaitComputation = null,
    async_plan: ?async_model.AsyncFunctionPlan,

    pub fn analyze(
        allocator: std.mem.Allocator,
        tokens: []const lexer.Token,
        registry: p3_async_manifest.Registry,
    ) !ComponentAsyncFunctionPlan {
        const function = parse_async_function(tokens) orelse return error.UnsupportedP3WaitForComponent;
        const parameter_storage = async_model.frame_slot_storage_from_type(function.parameter_type);

        if (try analyze_if_eq_parameter_literal(allocator, tokens, function, parameter_storage, registry)) |plan| {
            return plan;
        }
        if (try analyze_loop_countdown(allocator, tokens, function, parameter_storage, registry)) |plan| {
            return plan;
        }

        var operations = std.ArrayList(Operation).empty;
        errdefer operations.deinit(allocator);
        var argument = ScalarBinding{ .name = function.parameter_name, .argument = .parameter };
        var pending_future: ?[]const u8 = null;
        var terminal: ?TerminalAction = null;
        var post_await: ?PostAwaitComputation = null;
        var contract: ?p3_async_manifest.Descriptor = null;
        var payload_shape: ?PayloadShape = null;
        var idx = function.body_start;
        while (idx < function.body_end) {
            if (pending_future == null) {
                if (payload_shape == .scalar_unit and terminal == .await and post_await == null) {
                    if (parse_post_await_computation(tokens, idx, function.body_end, argument.name)) |computation| {
                        post_await = computation.value;
                        idx = computation.next_idx;
                        continue;
                    }
                }
                if (payload_shape == .scalar_unit and terminal == .await) {
                    if (parse_void_return(tokens, idx, function.body_end)) |next_idx| {
                        if (next_idx != function.body_end) return error.UnsupportedP3WaitForComponent;
                        idx = next_idx;
                        continue;
                    }
                }
                if (parse_scalar_alias(tokens, idx, function.body_end, function.parameter_type, argument.name)) |alias| {
                    argument.name = alias.name;
                    idx = alias.next_idx;
                    continue;
                }
                if (parse_u64_literal_binding(tokens, idx, function.body_end, function.parameter_type)) |literal| {
                    argument = .{ .name = literal.name, .argument = .{ .u64_literal = literal.value } };
                    idx = literal.next_idx;
                    continue;
                }
                if (std.meta.activeTag(argument.argument) == .parameter) {
                    if (parse_u64_add_parameter_literal_binding(tokens, idx, function.body_end, function.parameter_type, argument.name)) |addition| {
                        argument = .{ .name = addition.name, .argument = .{ .u64_add_parameter_literal = addition.value } };
                        idx = addition.next_idx;
                        continue;
                    }
                }
                if (parse_future_binding(tokens, idx, function.body_end, argument.name)) |binding| {
                    const host = find_host_binding(tokens, binding.host_name) orelse return error.UnsupportedP3WaitForComponent;
                    const descriptor = registry.find(host.locator, host.member) orelse return error.UnsupportedP3WaitForComponent;
                    const allows_cancel_nil_result = parse_cancel(tokens, binding.next_idx, function.body_end, binding.name) == function.body_end and
                        type_tokens_equal(tokens, function.result_start, function.result_end, "nil");
                    const validated = try validate_operation_descriptor(
                        tokens,
                        function,
                        binding,
                        descriptor,
                        parameter_storage,
                        contract,
                        allows_cancel_nil_result,
                    );
                    const shape = validated.shape;
                    if (payload_shape) |existing| {
                        if (existing != shape) return error.UnsupportedP3WaitForComponent;
                    } else payload_shape = shape;
                    if (contract == null) contract = descriptor;
                    try operations.append(allocator, .{
                        .descriptor = descriptor,
                        .future_name = binding.name,
                        .argument_name = argument.name,
                        .argument = argument.argument,
                        .payload_shape = shape,
                        .result_payload = validated.result_payload,
                        .error_variants = validated.error_variants,
                    });
                    pending_future = binding.name;
                    idx = binding.next_idx;
                    continue;
                }
                return error.UnsupportedP3WaitForComponent;
            }

            const future_name = pending_future.?;
            if (payload_shape == .scalar_unit) {
                if (parse_await(tokens, idx, function.body_end, future_name)) |next_idx| {
                    pending_future = null;
                    terminal = .await;
                    idx = next_idx;
                    continue;
                }
            }
            if (payload_shape == .resource_result_2word) {
                if (parse_return_await(tokens, idx, function.body_end, future_name)) |next_idx| {
                    if (next_idx != function.body_end) return error.UnsupportedP3WaitForComponent;
                    pending_future = null;
                    terminal = .return_await;
                    idx = next_idx;
                    continue;
                }
            }
            if (payload_shape == .scalar_result) {
                if (parse_return_await(tokens, idx, function.body_end, future_name)) |next_idx| {
                    if (next_idx != function.body_end) return error.UnsupportedP3WaitForComponent;
                    pending_future = null;
                    terminal = .return_await;
                    idx = next_idx;
                    continue;
                }
            }
            if (parse_cancel(tokens, idx, function.body_end, future_name)) |next_idx| {
                if (next_idx != function.body_end) return error.UnsupportedP3WaitForComponent;
                if (!type_tokens_equal(tokens, function.result_start, function.result_end, "nil")) return error.UnsupportedP3WaitForComponent;
                pending_future = null;
                terminal = .cancel;
                idx = next_idx;
                continue;
            }
            return error.UnsupportedP3WaitForComponent;
        }
        if (pending_future != null or operations.items.len == 0 or terminal == null or payload_shape == null) return error.UnsupportedP3WaitForComponent;

        return .{
            .export_name = function.name,
            .parameter = .{ .name = function.parameter_name, .storage = parameter_storage },
            .operations = try operations.toOwnedSlice(allocator),
            .control = .linear,
            .terminal = terminal.?,
            .post_await = post_await,
            .async_plan = if (payload_shape.? == .scalar_unit)
                try collect_async_plan(allocator, tokens, function.name)
            else
                null,
        };
    }

    pub fn deinit(self: *ComponentAsyncFunctionPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.operations);
        if (self.async_plan) |*plan| plan.deinit(allocator);
        self.* = undefined;
    }
};

pub const StreamU8AcquirePlan = struct {
    export_name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
    handles_name: []const u8,
    reader_name: []const u8,
    completion_name: []const u8,
    reads: [max_stream_u8_reads]StreamU8Read,
    read_count: usize,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !StreamU8AcquirePlan {
        const host = find_stream_u8_host_binding(tokens, registry) orelse return error.UnsupportedP3WaitForComponent;
        const function = parse_stream_u8_function(tokens) orelse return error.UnsupportedP3WaitForComponent;

        var idx = function.body_start;
        const prefix = parse_stream_u8_acquire_prefix(tokens, idx, function.body_end, host.name) orelse return error.UnsupportedP3WaitForComponent;
        idx = prefix.next_idx;
        var reads: [max_stream_u8_reads]StreamU8Read = undefined;
        var read_count: usize = 0;
        while (read_count < reads.len) {
            const pending = parse_stream_u8_next(tokens, idx, function.body_end, prefix.reader_name) orelse break;
            idx = pending.next_idx;
            const item = parse_stream_u8_await(tokens, idx, function.body_end, pending.name) orelse return error.UnsupportedP3WaitForComponent;
            idx = item.next_idx;
            idx = parse_stream_u8_item_discard(tokens, idx, function.body_end, item.name) orelse return error.UnsupportedP3WaitForComponent;
            reads[read_count] = .{ .pending_name = pending.name, .item_name = item.name };
            read_count += 1;
        }
        if (read_count == 0) return error.UnsupportedP3WaitForComponent;
        idx = parse_stream_u8_cancel(tokens, idx, function.body_end, prefix.completion_name) orelse return error.UnsupportedP3WaitForComponent;
        if (idx != function.body_end) return error.UnsupportedP3WaitForComponent;

        return .{
            .export_name = function.name,
            .descriptor = host.descriptor,
            .handles_name = prefix.handles_name,
            .reader_name = prefix.reader_name,
            .completion_name = prefix.completion_name,
            .reads = reads,
            .read_count = read_count,
        };
    }
};

pub const max_stream_mirror_reads: usize = 3;

pub const StreamMirrorRead = struct {
    pending_name: []const u8,
    item_name: []const u8,
    value_name: []const u8,
    write_pending_name: []const u8,
    write_result_name: []const u8,
};

pub const StreamMirrorPlan = struct {
    export_name: []const u8,
    source_descriptor: p3_async_manifest.Descriptor,
    sink_descriptor: p3_async_manifest.Descriptor,
    source_host_name: []const u8,
    sink_host_name: []const u8,
    source_handles_name: []const u8,
    source_reader_name: []const u8,
    source_completion_name: []const u8,
    output_reader_name: []const u8,
    writer_name: []const u8,
    capacity: u32,
    max_reads: usize,
    read: StreamMirrorRead,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !StreamMirrorPlan {
        const source_host = find_stream_mirror_source_host_binding(tokens, registry) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        const sink_host = find_stream_mirror_sink_host_binding(tokens, registry) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        const function = parse_stream_mirror_function(tokens) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        if (!type_tokens_equal(tokens, function.result_start, function.result_end, "Result<nil,ProbeError>"))
            return error.UnsupportedP3StreamMirrorComponent;

        var idx = function.body_start;
        const prefix = parse_stream_u8_acquire_prefix(tokens, idx, function.body_end, source_host.name) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        idx = prefix.next_idx;

        const stream = parse_guest_stream_new(tokens, idx, function.body_end) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        if (stream.capacity != 1) return error.UnsupportedP3StreamMirrorComponent;
        idx = stream.next_idx;
        idx = parse_writer_defer_close(tokens, idx, function.body_end, stream.writer_name) orelse
            return error.UnsupportedP3StreamMirrorComponent;

        const counter = parse_loop_countdown_binding(tokens, idx, function.body_end, "u64", "") orelse
            return error.UnsupportedP3StreamMirrorComponent;
        switch (counter.initial) {
            .u64_literal => |value| if (value != 3) return error.UnsupportedP3StreamMirrorComponent,
            else => return error.UnsupportedP3StreamMirrorComponent,
        }
        idx = counter.next_idx;
        if (idx + 1 >= function.body_end or !tok_eq(tokens[idx], "loop") or !tok_eq(tokens[idx + 1], "{"))
            return error.UnsupportedP3StreamMirrorComponent;
        const loop_open = idx + 1;
        const loop_close = find_matching(tokens, loop_open, "{", "}") orelse
            return error.UnsupportedP3StreamMirrorComponent;

        var loop_idx = parse_countdown_break(tokens, loop_open + 1, loop_close, counter.name) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        const pending = parse_stream_u8_next(tokens, loop_idx, loop_close, prefix.reader_name) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        loop_idx = pending.next_idx;
        const item = parse_stream_u8_await(tokens, loop_idx, loop_close, pending.name) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        loop_idx = item.next_idx;
        const branch = parse_stream_mirror_branch(tokens, loop_idx, loop_close, pending.name, item.name, stream.writer_name, counter.name) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        if (branch.next_idx != loop_close)
            return error.UnsupportedP3StreamMirrorComponent;

        idx = loop_close + 1;
        idx = parse_stream_u8_cancel(tokens, idx, function.body_end, prefix.completion_name) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        const sink = parse_future_binding(tokens, idx, function.body_end, stream.writer_name) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        if (!std.mem.eql(u8, sink.host_name, sink_host.name) or
            !type_tokens_equal(tokens, sink.result_start, sink.result_end, "Result<nil,ProbeError>"))
            return error.UnsupportedP3StreamMirrorComponent;
        idx = parse_return_await(tokens, sink.next_idx, function.body_end, sink.name) orelse
            return error.UnsupportedP3StreamMirrorComponent;
        if (idx != function.body_end)
            return error.UnsupportedP3StreamMirrorComponent;

        return .{
            .export_name = function.name,
            .source_descriptor = source_host.descriptor,
            .sink_descriptor = sink_host.descriptor,
            .source_host_name = source_host.name,
            .sink_host_name = sink_host.name,
            .source_handles_name = prefix.handles_name,
            .source_reader_name = prefix.reader_name,
            .source_completion_name = prefix.completion_name,
            .output_reader_name = stream.reader_name,
            .writer_name = stream.writer_name,
            .capacity = stream.capacity,
            .max_reads = max_stream_mirror_reads,
            .read = branch.read,
        };
    }
};

/// The fixed stream source acquisition shared by component stream probes and
/// HTTP request-body lowering. It deliberately stops before any read or
/// cancellation operation so consumers can own the reader and completion
/// future across their own terminal sequence.
pub const StreamU8AcquirePrefix = struct {
    descriptor: p3_async_manifest.Descriptor,
    host_name: []const u8,
    handles_name: []const u8,
    reader_name: []const u8,
    completion_name: []const u8,
    next_idx: usize,
};

pub fn analyze_stream_u8_acquire_prefix(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    registry: p3_async_manifest.Registry,
) !StreamU8AcquirePrefix {
    const host = find_stream_u8_host_binding(tokens, registry) orelse return error.UnsupportedP3WaitForComponent;
    const prefix = parse_stream_u8_acquire_prefix(tokens, start_idx, end_idx, host.name) orelse
        return error.UnsupportedP3WaitForComponent;
    return .{
        .descriptor = host.descriptor,
        .host_name = host.name,
        .handles_name = prefix.handles_name,
        .reader_name = prefix.reader_name,
        .completion_name = prefix.completion_name,
        .next_idx = prefix.next_idx,
    };
}

pub const EndpointMode = enum {
    forwarded_reader,
    guest_producer,
};

pub const ProducerMode = enum {
    fixed_sequence,
    countdown,
};

pub const WriterTerminalAction = union(enum) {
    close,
    abort_pipe_when_value: u8,
};

pub const max_guest_producer_writes: usize = 8;
const max_guest_producer_bindings: usize = 8;

/// A bounded guest-created stream shape that another descriptor-specific
/// lowering may consume without inheriting the stdout writer endpoint.
pub const GuestProducerShape = struct {
    function_name: []const u8,
    reader_name: []const u8,
    writer_name: []const u8,
    write_future_name: []const u8,
    values: [max_guest_producer_writes]u8,
    write_count: usize,
    capacity: u32,
    next_idx: usize,
};

pub const GuestStreamPrefix = struct {
    reader_name: []const u8,
    writer_name: []const u8,
    capacity: u32,
    next_idx: usize,
};

pub const GuestProducerWrites = struct {
    write_future_name: []const u8,
    values: [max_guest_producer_writes]u8,
    write_count: usize,
    next_idx: usize,
};

pub fn analyze_guest_stream_prefix(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?GuestStreamPrefix {
    const stream = parse_guest_stream_new(tokens, start_idx, end_idx) orelse return null;
    return .{
        .reader_name = stream.reader_name,
        .writer_name = stream.writer_name,
        .capacity = stream.capacity,
        .next_idx = stream.next_idx,
    };
}

pub fn analyze_guest_producer_writes(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    writer_name: []const u8,
) ?GuestProducerWrites {
    var writes = parse_guest_write_sequence(tokens, start_idx, end_idx, writer_name) orelse return null;
    const cursor = writes.next_idx;
    if (cursor + 4 > end_idx or !tok_eq(tokens[cursor], "close") or
        !tok_eq(tokens[cursor + 1], "(") or tokens[cursor + 2].kind != .ident or
        !std.mem.eql(u8, tokens[cursor + 2].lexeme, writer_name) or !tok_eq(tokens[cursor + 3], ")")) return null;
    writes.next_idx = cursor + 4;
    return writes;
}

fn parse_guest_write_sequence(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    writer_name: []const u8,
) ?GuestProducerWrites {
    var values = [_]u8{0} ** max_guest_producer_writes;
    var bindings = [_]GuestU8Binding{undefined} ** max_guest_producer_bindings;
    var binding_count: usize = 0;
    var write_count: usize = 0;
    var write_future_name: ?[]const u8 = null;
    var cursor = start_idx;
    while (write_count < max_guest_producer_writes) {
        if (parse_guest_u8_binding(tokens, cursor, end_idx)) |binding| {
            if (binding_count == max_guest_producer_bindings) break;
            bindings[binding_count] = .{ .name = binding.name, .value = binding.value };
            binding_count += 1;
            cursor = binding.next_idx;
            continue;
        }
        const write = parse_guest_write_binding(tokens, cursor, end_idx, writer_name, bindings[0..binding_count]) orelse break;
        const awaited = parse_guest_await_binding(tokens, write.next_idx, end_idx, write.future_name) orelse break;
        cursor = parse_guest_discard(tokens, awaited.next_idx, end_idx, awaited.result_name) orelse break;
        values[write_count] = write.value;
        if (write_future_name == null) write_future_name = write.future_name;
        write_count += 1;
    }
    if (write_count == 0) return null;
    return .{
        .write_future_name = write_future_name orelse return null,
        .values = values,
        .write_count = write_count,
        .next_idx = cursor,
    };
}

/// Parse only the producer prefix. The caller owns the operation-specific
/// suffix (for example, HTTP request construction) and must validate it.
pub fn analyze_guest_producer_shape(tokens: []const lexer.Token) ?GuestProducerShape {
    var idx: usize = 0;
    while (idx + 6 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], "async") or tokens[idx + 1].kind != .ident or !tok_eq(tokens[idx + 2], "(") or
            !tok_eq(tokens[idx + 3], ")") or !tok_eq(tokens[idx + 4], "-") or !tok_eq(tokens[idx + 5], ">")) continue;
        var body_open = idx + 6;
        while (body_open < tokens.len and !tok_eq(tokens[body_open], "{")) : (body_open += 1) {}
        if (body_open == tokens.len) continue;
        const body_end = find_matching(tokens, body_open, "{", "}") orelse continue;
        const stream = analyze_guest_stream_prefix(tokens, body_open + 1, body_end) orelse continue;
        const writes = analyze_guest_producer_writes(tokens, stream.next_idx, body_end, stream.writer_name) orelse continue;
        return .{
            .function_name = tokens[idx + 1].lexeme,
            .reader_name = stream.reader_name,
            .writer_name = stream.writer_name,
            .write_future_name = writes.write_future_name,
            .values = writes.values,
            .write_count = writes.write_count,
            .capacity = stream.capacity,
            .next_idx = writes.next_idx,
        };
    }
    return null;
}

pub const StreamWriterPlan = struct {
    export_name: []const u8,
    parameter_name: []const u8,
    future_name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
    stream: p3_async_manifest.StreamWriterShape,
    endpoint_mode: EndpointMode,
    queue_capacity: u32,
    producer_mode: ProducerMode = .fixed_sequence,
    producer_count_name: ?[]const u8 = null,
    producer_value_name: ?[]const u8 = null,
    producer_reader_name: ?[]const u8 = null,
    producer_writer_name: ?[]const u8 = null,
    producer_write_future_name: ?[]const u8 = null,
    producer_host_future_name: ?[]const u8 = null,
    producer_helper_name: ?[]const u8 = null,
    producer_value: ?u8 = null,
    producer_terminal: WriterTerminalAction = .close,
    producer_values: [max_guest_producer_writes]u8 = [_]u8{0} ** max_guest_producer_writes,
    producer_write_count: usize = 0,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !StreamWriterPlan {
        const host = find_stream_writer_host_binding(tokens, registry) orelse return error.UnsupportedP3StreamWriterComponent;
        const stream = switch (p3_async_manifest.lowering_shape(host.descriptor) orelse return error.UnsupportedP3StreamWriterComponent) {
            .stream_writer => |value| value,
            else => return error.UnsupportedP3StreamWriterComponent,
        };
        if (find_guest_producer_function(tokens, host.name)) |function| {
            return .{
                .export_name = function.name,
                .parameter_name = function.writer_name,
                .future_name = function.host_future_name,
                .descriptor = host.descriptor,
                .stream = stream,
                .endpoint_mode = .guest_producer,
                .queue_capacity = function.capacity,
                .producer_mode = function.mode,
                .producer_count_name = function.count_name,
                .producer_value_name = function.value_name,
                .producer_reader_name = function.reader_name,
                .producer_writer_name = function.writer_name,
                .producer_write_future_name = function.write_future_name,
                .producer_host_future_name = function.host_future_name,
                .producer_helper_name = function.helper_name,
                .producer_value = function.value,
                .producer_terminal = function.terminal,
                .producer_values = function.values,
                .producer_write_count = function.write_count,
            };
        }
        const function = find_stream_writer_function(tokens) orelse return error.UnsupportedP3StreamWriterComponent;
        const body_end = function.body_end;
        const binding_start = parse_writer_defer_close(tokens, function.body_start, body_end, function.parameter_name) orelse
            return error.UnsupportedP3StreamWriterComponent;
        const binding = parse_future_binding(tokens, binding_start, body_end, function.parameter_name) orelse
            return error.UnsupportedP3StreamWriterComponent;
        if (!std.mem.eql(u8, binding.host_name, host.name)) return error.UnsupportedP3StreamWriterComponent;
        const binding_result_end = find_matching(tokens, binding.result_start + 1, "<", ">") orelse return error.UnsupportedP3StreamWriterComponent;
        if (!token_ranges_equal(tokens, binding.result_start, binding_result_end + 1, function.result_start, function.result_end)) return error.UnsupportedP3StreamWriterComponent;
        const after_binding = binding.next_idx;
        const return_end = parse_return_await(tokens, after_binding, body_end, binding.name) orelse return error.UnsupportedP3StreamWriterComponent;
        if (return_end != body_end) return error.UnsupportedP3StreamWriterComponent;
        return .{
            .export_name = function.name,
            .parameter_name = function.parameter_name,
            .future_name = binding.name,
            .descriptor = host.descriptor,
            .stream = stream,
            .endpoint_mode = .forwarded_reader,
            .queue_capacity = 1,
        };
    }
};

fn parse_writer_defer_close(tokens: []const lexer.Token, idx: usize, end_idx: usize, writer_name: []const u8) ?usize {
    if (idx + 4 >= end_idx or !tok_eq(tokens[idx], "defer") or !tok_eq(tokens[idx + 1], "close") or
        !tok_eq(tokens[idx + 2], "(") or tokens[idx + 3].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 3].lexeme, writer_name) or !tok_eq(tokens[idx + 4], ")")) return null;
    return idx + 5;
}

const StreamWriterFunction = struct {
    name: []const u8,
    parameter_name: []const u8,
    body_start: usize,
    body_end: usize,
    result_start: usize,
    result_end: usize,
};

const GuestProducerFunction = struct {
    name: []const u8,
    reader_name: []const u8,
    writer_name: []const u8,
    write_future_name: []const u8,
    host_future_name: []const u8,
    helper_name: ?[]const u8,
    mode: ProducerMode,
    count_name: ?[]const u8,
    value_name: ?[]const u8,
    value: u8,
    terminal: WriterTerminalAction,
    values: [max_guest_producer_writes]u8,
    write_count: usize,
    capacity: u32,
};

const GuestStreamBinding = struct {
    reader_name: []const u8,
    writer_name: []const u8,
    capacity: u32,
    next_idx: usize,
};

const GuestWriteBinding = struct {
    future_name: []const u8,
    value: u8,
    next_idx: usize,
};

const GuestU8ValueBinding = struct {
    name: []const u8,
    value: u8,
    next_idx: usize,
};

const GuestU8Binding = struct {
    name: []const u8,
    value: u8,
};

const GuestAwaitBinding = struct {
    result_name: []const u8,
    next_idx: usize,
};

fn find_guest_producer_function(tokens: []const lexer.Token, host_name: []const u8) ?GuestProducerFunction {
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], "async") or tokens[idx + 1].kind != .ident or !tok_eq(tokens[idx + 2], "(")) continue;
        var return_start: usize = undefined;
        var count_name: ?[]const u8 = null;
        var value_name: ?[]const u8 = null;
        if (tok_eq(tokens[idx + 3], ")")) {
            return_start = idx + 4;
        } else {
            if (idx + 5 >= tokens.len or tokens[idx + 3].kind != .ident or !tok_eq(tokens[idx + 4], "u64")) continue;
            count_name = tokens[idx + 3].lexeme;
            if (tok_eq(tokens[idx + 5], ")")) {
                return_start = idx + 6;
            } else {
                if (idx + 9 >= tokens.len or !tok_eq(tokens[idx + 5], ",") or tokens[idx + 6].kind != .ident or
                    !tok_eq(tokens[idx + 7], "u8") or !tok_eq(tokens[idx + 8], ")")) continue;
                value_name = tokens[idx + 6].lexeme;
                return_start = idx + 9;
            }
        }
        if (return_start + 7 >= tokens.len or !tok_eq(tokens[return_start], "-") or !tok_eq(tokens[return_start + 1], ">") or
            !tok_eq(tokens[return_start + 2], "Result") or !tok_eq(tokens[return_start + 3], "<") or !tok_eq(tokens[return_start + 4], "nil") or
            !tok_eq(tokens[return_start + 5], ",") or tokens[return_start + 6].kind != .ident or !tok_eq(tokens[return_start + 7], ">")) continue;
        const result_end = find_matching(tokens, return_start + 3, "<", ">") orelse continue;
        if (result_end + 1 >= tokens.len or !tok_eq(tokens[result_end + 1], "{")) continue;
        const body_end = find_matching(tokens, result_end + 1, "{", "}") orelse continue;
        const body_start = result_end + 2;
        const stream = parse_guest_stream_new(tokens, body_start, body_end) orelse continue;
        if (count_name) |name| {
            if (stream.capacity != 1) continue;
            if (parse_dynamic_guest_producer_body(tokens, stream.next_idx, body_end, name, value_name, stream.writer_name, host_name)) |dynamic| {
                if (value_name != null and dynamic.value_name == null) continue;
                return .{
                    .name = tokens[idx + 1].lexeme,
                    .reader_name = stream.reader_name,
                    .writer_name = stream.writer_name,
                    .write_future_name = dynamic.write_future_name,
                    .host_future_name = dynamic.host_future_name,
                    .helper_name = null,
                    .mode = .countdown,
                    .count_name = name,
                    .value_name = dynamic.value_name,
                    .value = dynamic.value,
                    .terminal = dynamic.terminal,
                    .values = [_]u8{0} ** max_guest_producer_writes,
                    .write_count = 0,
                    .capacity = stream.capacity,
                };
            }
            if (value_name == null) continue;
            const helper_binding = parse_parameterized_helper_binding(tokens, stream.next_idx, body_end, stream.writer_name, name, value_name.?) orelse continue;
            var helper = find_parameterized_stream_writer_function_named(tokens, helper_binding.host_name) orelse continue;
            const root_helper_name = helper.name;
            const binding_result_end = find_matching(tokens, helper_binding.result_start + 1, "<", ">") orelse continue;
            if (!token_ranges_equal(tokens, helper_binding.result_start, binding_result_end + 1, helper.result_start, helper.result_end)) continue;
            var dynamic = parse_dynamic_guest_producer_body(
                tokens,
                helper.body_start,
                helper.body_end,
                helper.count_name,
                helper.value_name,
                helper.writer_name,
                host_name,
            );
            var forwarding_hops: usize = 0;
            while (dynamic == null and forwarding_hops < max_parameterized_forwarding_hops) : (forwarding_hops += 1) {
                helper = parse_parameterized_forwarding_helper(tokens, helper) orelse break;
                dynamic = parse_dynamic_guest_producer_body(
                    tokens,
                    helper.body_start,
                    helper.body_end,
                    helper.count_name,
                    helper.value_name,
                    helper.writer_name,
                    host_name,
                );
            }
            const selected_dynamic = dynamic orelse continue;
            if (selected_dynamic.value_name == null) continue;
            const after_root = parse_return_await(tokens, helper_binding.next_idx, body_end, helper_binding.name) orelse continue;
            if (after_root != body_end) continue;
            return .{
                .name = tokens[idx + 1].lexeme,
                .reader_name = stream.reader_name,
                .writer_name = stream.writer_name,
                .write_future_name = selected_dynamic.write_future_name,
                .host_future_name = selected_dynamic.host_future_name,
                .helper_name = root_helper_name,
                .mode = .countdown,
                .count_name = name,
                .value_name = value_name,
                .value = selected_dynamic.value,
                .terminal = selected_dynamic.terminal,
                .values = [_]u8{0} ** max_guest_producer_writes,
                .write_count = 0,
                .capacity = stream.capacity,
            };
        }
        const root_writes = parse_guest_write_sequence(tokens, stream.next_idx, body_end, stream.writer_name);
        var selected_writes = root_writes;
        var cursor = stream.next_idx;
        if (root_writes) |writes| cursor = writes.next_idx;
        var host: FutureBinding = undefined;
        var helper_name: ?[]const u8 = null;
        if (root_writes == null) {
            host = parse_future_binding_any(tokens, cursor, body_end) orelse continue;
            if (!std.mem.eql(u8, host.argument_name, stream.writer_name)) continue;
            const helper = find_stream_writer_function_named(tokens, host.host_name) orelse continue;
            const helper_body = analyze_stream_writer_helper_body(tokens, helper, host_name) orelse continue;
            selected_writes = helper_body.writes;
            if (selected_writes == null) continue;
            helper_name = host.host_name;
        } else if (parse_writer_defer_close(tokens, cursor, body_end, stream.writer_name)) |after_defer| {
            host = parse_future_binding(tokens, after_defer, body_end, stream.writer_name) orelse continue;
            if (!std.mem.eql(u8, host.host_name, host_name)) continue;
        } else {
            host = parse_future_binding_any(tokens, cursor, body_end) orelse continue;
            if (!std.mem.eql(u8, host.argument_name, stream.writer_name)) continue;
            const helper = find_stream_writer_function_named(tokens, host.host_name) orelse continue;
            _ = analyze_stream_writer_helper_body(tokens, helper, host_name) orelse continue;
            helper_name = host.host_name;
        }
        const after_host = parse_return_await(tokens, host.next_idx, body_end, host.name) orelse continue;
        if (after_host != body_end) continue;
        const writes = selected_writes orelse continue;
        return .{
            .name = tokens[idx + 1].lexeme,
            .reader_name = stream.reader_name,
            .writer_name = stream.writer_name,
            .write_future_name = writes.write_future_name,
            .host_future_name = host.name,
            .helper_name = helper_name,
            .mode = .fixed_sequence,
            .count_name = null,
            .value_name = null,
            .value = writes.values[0],
            .terminal = .close,
            .values = writes.values,
            .write_count = writes.write_count,
            .capacity = stream.capacity,
        };
    }
    return null;
}

const DynamicGuestProducer = struct {
    write_future_name: []const u8,
    host_future_name: []const u8,
    value_name: ?[]const u8,
    value: u8,
    terminal: WriterTerminalAction,
};

const ParameterizedHelperBinding = struct {
    name: []const u8,
    host_name: []const u8,
    writer_name: []const u8,
    count_name: []const u8,
    value_name: []const u8,
    result_start: usize,
    result_end: usize,
    next_idx: usize,
};

fn parse_dynamic_guest_producer_body(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    count_name: []const u8,
    value_name: ?[]const u8,
    writer_name: []const u8,
    host_name: []const u8,
) ?DynamicGuestProducer {
    const counter = parse_loop_countdown_binding(tokens, start_idx, end_idx, "u64", count_name) orelse return null;
    switch (counter.initial) {
        .parameter => {},
        else => return null,
    }
    if (counter.next_idx + 1 >= end_idx or !tok_eq(tokens[counter.next_idx], "loop") or !tok_eq(tokens[counter.next_idx + 1], "{")) return null;
    const loop_open = counter.next_idx + 1;
    const loop_close = find_matching(tokens, loop_open, "{", "}") orelse return null;
    const body_start = loop_open + 1;
    const write_start = parse_countdown_break(tokens, body_start, loop_close, counter.name) orelse return null;
    var no_bindings = [_]GuestU8Binding{};
    const write = if (value_name) |name| blk: {
        const parameter_write = parse_guest_parameter_write_binding(tokens, write_start, loop_close, writer_name, name) orelse return null;
        break :blk GuestWriteBinding{ .future_name = parameter_write.future_name, .value = 0, .next_idx = parameter_write.next_idx };
    } else parse_guest_write_binding(tokens, write_start, loop_close, writer_name, no_bindings[0..]) orelse return null;
    const awaited = parse_guest_await_binding(tokens, write.next_idx, loop_close, write.future_name) orelse return null;
    const after_discard = parse_guest_discard(tokens, awaited.next_idx, loop_close, awaited.result_name) orelse return null;
    const after_decrement = parse_countdown_decrement(tokens, after_discard, loop_close, counter.name) orelse return null;
    if (after_decrement != loop_close or (value_name == null and write.value != 65)) return null;
    var terminal: WriterTerminalAction = .close;
    var terminal_next_idx: usize = undefined;
    if (parse_writer_defer_close(tokens, loop_close + 1, end_idx, writer_name)) |close_idx| {
        terminal_next_idx = close_idx;
    } else if (parse_branch_terminal(tokens, loop_close + 1, end_idx, writer_name, value_name)) |branch| {
        terminal = .{ .abort_pipe_when_value = branch.selector_value };
        terminal_next_idx = branch.next_idx;
    } else return null;
    const host = parse_future_binding(tokens, terminal_next_idx, end_idx, writer_name) orelse return null;
    if (!std.mem.eql(u8, host.host_name, host_name)) return null;
    const after_host = parse_return_await(tokens, host.next_idx, end_idx, host.name) orelse return null;
    if (after_host != end_idx) return null;
    return .{ .write_future_name = write.future_name, .host_future_name = host.name, .value_name = value_name, .value = write.value, .terminal = terminal };
}

const BranchTerminal = struct {
    selector_value: u8,
    next_idx: usize,
};

fn parse_branch_terminal(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    writer_name: []const u8,
    value_name: ?[]const u8,
) ?BranchTerminal {
    const selected_name = value_name orelse return null;
    if (idx + 8 >= end_idx or !tok_eq(tokens[idx], "if") or !tok_eq(tokens[idx + 1], "@") or
        !tok_eq(tokens[idx + 2], "eq") or !tok_eq(tokens[idx + 3], "(") or tokens[idx + 4].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 4].lexeme, selected_name) or !tok_eq(tokens[idx + 5], ",") or
        tokens[idx + 6].kind != .number or !tok_eq(tokens[idx + 7], ")") or !tok_eq(tokens[idx + 8], "{")) return null;
    const selector_value = std.fmt.parseUnsigned(u8, tokens[idx + 6].lexeme, 10) catch return null;
    const then_close = find_matching(tokens, idx + 8, "{", "}") orelse return null;
    const then_next = parse_writer_close_call(tokens, idx + 9, then_close, writer_name) orelse return null;
    if (then_next != then_close) return null;
    if (then_close + 2 >= end_idx or !tok_eq(tokens[then_close + 1], "else") or !tok_eq(tokens[then_close + 2], "{")) return null;
    const else_close = find_matching(tokens, then_close + 2, "{", "}") orelse return null;
    const else_next = parse_writer_abort_pipe_call(tokens, then_close + 3, else_close, writer_name) orelse return null;
    if (else_next != else_close) return null;
    return .{ .selector_value = selector_value, .next_idx = else_close + 1 };
}

fn parse_writer_close_call(tokens: []const lexer.Token, idx: usize, end_idx: usize, writer_name: []const u8) ?usize {
    if (idx + 3 >= end_idx or !tok_eq(tokens[idx], "close") or !tok_eq(tokens[idx + 1], "(") or
        tokens[idx + 2].kind != .ident or !std.mem.eql(u8, tokens[idx + 2].lexeme, writer_name) or !tok_eq(tokens[idx + 3], ")")) return null;
    return idx + 4;
}

fn parse_writer_abort_pipe_call(tokens: []const lexer.Token, idx: usize, end_idx: usize, writer_name: []const u8) ?usize {
    if (idx + 5 >= end_idx or !tok_eq(tokens[idx], "abort") or !tok_eq(tokens[idx + 1], "(") or
        tokens[idx + 2].kind != .ident or !std.mem.eql(u8, tokens[idx + 2].lexeme, writer_name) or
        !tok_eq(tokens[idx + 3], ",") or tokens[idx + 4].kind != .number or !tok_eq(tokens[idx + 5], ")")) return null;
    const code = std.fmt.parseUnsigned(u8, tokens[idx + 4].lexeme, 10) catch return null;
    if (code != 2) return null;
    return idx + 6;
}

const GuestParameterWriteBinding = struct {
    future_name: []const u8,
    next_idx: usize,
};

fn parse_guest_parameter_write_binding(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    writer_name: []const u8,
    value_name: []const u8,
) ?GuestParameterWriteBinding {
    if (idx + 9 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const future_close = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (future_close != idx + 9 or !tok_eq(tokens[future_close + 1], "=") or !std.mem.eql(u8, tokens[future_close + 2].lexeme, writer_name) or
        !tok_eq(tokens[future_close + 3], "(") or tokens[future_close + 4].kind != .ident or
        !std.mem.eql(u8, tokens[future_close + 4].lexeme, value_name) or !tok_eq(tokens[future_close + 5], ")")) return null;
    if (!tok_eq(tokens[idx + 3], "Result") or !tok_eq(tokens[idx + 4], "<") or !tok_eq(tokens[idx + 5], "nil") or
        !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .ident or !tok_eq(tokens[idx + 8], ">") or !tok_eq(tokens[idx + 9], ">")) return null;
    return .{ .future_name = tokens[idx].lexeme, .next_idx = future_close + 6 };
}

fn parse_guest_stream_new(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?GuestStreamBinding {
    if (idx + 2 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "StreamReader") or !tok_eq(tokens[idx + 2], "<")) return null;
    const reader_close = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (reader_close + 5 >= end_idx or !tok_eq(tokens[idx + 3], "u8") or !tok_eq(tokens[reader_close + 1], ",") or
        tokens[reader_close + 2].kind != .ident or !tok_eq(tokens[reader_close + 3], "StreamWriter") or
        !tok_eq(tokens[reader_close + 4], "<") or !tok_eq(tokens[reader_close + 5], "u8")) return null;
    const writer_close = find_matching(tokens, reader_close + 4, "<", ">") orelse return null;
    if (writer_close + 4 >= end_idx or !tok_eq(tokens[writer_close + 1], "=") or !tok_eq(tokens[writer_close + 2], "new_stream") or
        !tok_eq(tokens[writer_close + 3], "<") or !tok_eq(tokens[writer_close + 4], "u8")) return null;
    const call_type_close = find_matching(tokens, writer_close + 3, "<", ">") orelse return null;
    if (call_type_close + 3 >= end_idx or !tok_eq(tokens[call_type_close + 1], "(") or tokens[call_type_close + 2].kind != .number or
        !tok_eq(tokens[call_type_close + 3], ")")) return null;
    const capacity = std.fmt.parseUnsigned(u32, tokens[call_type_close + 2].lexeme, 10) catch return null;
    return .{
        .reader_name = tokens[idx].lexeme,
        .writer_name = tokens[reader_close + 2].lexeme,
        .capacity = capacity,
        .next_idx = call_type_close + 4,
    };
}

fn parse_guest_u8_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?GuestU8ValueBinding {
    if (idx + 3 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "u8") or
        !tok_eq(tokens[idx + 2], "=") or tokens[idx + 3].kind != .number) return null;
    const value = std.fmt.parseUnsigned(u8, tokens[idx + 3].lexeme, 10) catch return null;
    return .{ .name = tokens[idx].lexeme, .value = value, .next_idx = idx + 4 };
}

fn parse_guest_write_binding(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    writer_name: []const u8,
    bindings: []const GuestU8Binding,
) ?GuestWriteBinding {
    if (idx + 8 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const future_close = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (future_close + 5 >= end_idx or !tok_eq(tokens[future_close + 1], "=") or !std.mem.eql(u8, tokens[future_close + 2].lexeme, writer_name) or
        !tok_eq(tokens[future_close + 3], "(") or !tok_eq(tokens[future_close + 5], ")")) return null;
    if (future_close != idx + 9 or !tok_eq(tokens[idx + 3], "Result") or !tok_eq(tokens[idx + 4], "<") or !tok_eq(tokens[idx + 5], "nil") or
        !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .ident or !tok_eq(tokens[idx + 8], ">") or !tok_eq(tokens[idx + 9], ">")) return null;
    const value = if (tokens[future_close + 4].kind == .number)
        std.fmt.parseUnsigned(u8, tokens[future_close + 4].lexeme, 10) catch return null
    else
        find_guest_u8_binding(bindings, tokens[future_close + 4].lexeme) orelse return null;
    return .{ .future_name = tokens[idx].lexeme, .value = value, .next_idx = future_close + 6 };
}

fn find_guest_u8_binding(bindings: []const GuestU8Binding, name: []const u8) ?u8 {
    var idx = bindings.len;
    while (idx > 0) {
        idx -= 1;
        if (std.mem.eql(u8, bindings[idx].name, name)) return bindings[idx].value;
    }
    return null;
}

fn parse_guest_discard(tokens: []const lexer.Token, idx: usize, end_idx: usize, name: []const u8) ?usize {
    if (idx + 3 >= end_idx or !tok_eq(tokens[idx], "_") or !tok_eq(tokens[idx + 1], "=") or tokens[idx + 2].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 2].lexeme, name)) return null;
    return idx + 3;
}

fn parse_guest_await_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize, future_name: []const u8) ?GuestAwaitBinding {
    if (idx + 5 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Result") or !tok_eq(tokens[idx + 2], "<")) return null;
    const result_close = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (result_close + 1 >= end_idx or !tok_eq(tokens[result_close + 1], "=")) return null;
    const await_end = parse_await(tokens, result_close + 2, end_idx, future_name) orelse return null;
    return .{ .result_name = tokens[idx].lexeme, .next_idx = await_end };
}

const StreamWriterHostBinding = struct {
    name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
};

fn find_stream_writer_host_binding(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?StreamWriterHostBinding {
    var idx: usize = 0;
    while (idx + 23 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            (!tok_eq(tokens[idx + 3], "host") and !tok_eq(tokens[idx + 3], "host_func")) or !tok_eq(tokens[idx + 4], "(") or
            !tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or
            !tok_eq(tokens[idx + 10], "StreamWriter") or !tok_eq(tokens[idx + 11], "<") or !tok_eq(tokens[idx + 12], "u8") or
            !tok_eq(tokens[idx + 13], ">") or !tok_eq(tokens[idx + 14], ")") or !tok_eq(tokens[idx + 15], "-") or
            !tok_eq(tokens[idx + 16], ">") or !tok_eq(tokens[idx + 17], "Result") or !tok_eq(tokens[idx + 18], "<") or
            !tok_eq(tokens[idx + 19], "nil") or !tok_eq(tokens[idx + 20], ",") or tokens[idx + 21].kind != .ident or
            !tok_eq(tokens[idx + 22], ">") or !tok_eq(tokens[idx + 23], ")")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        const member = string_token_body(tokens[idx + 7]) orelse continue;
        const descriptor = registry.find(locator, member) orelse continue;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse continue) {
            .stream_writer => return .{ .name = tokens[idx].lexeme, .descriptor = descriptor },
            else => continue,
        }
    }
    return null;
}

fn find_stream_mirror_sink_host_binding(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?StreamWriterHostBinding {
    const locator_expected = "do:stream-probe@0.1.0";
    const member_expected = "write-via-stream";
    var found: ?StreamWriterHostBinding = null;
    var idx: usize = 0;
    while (idx + 23 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            (!tok_eq(tokens[idx + 3], "host") and !tok_eq(tokens[idx + 3], "host_func")) or !tok_eq(tokens[idx + 4], "(") or
            !tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or
            !tok_eq(tokens[idx + 10], "StreamWriter") or !tok_eq(tokens[idx + 11], "<") or !tok_eq(tokens[idx + 12], "u8") or
            !tok_eq(tokens[idx + 13], ">") or !tok_eq(tokens[idx + 14], ")") or !tok_eq(tokens[idx + 15], "-") or
            !tok_eq(tokens[idx + 16], ">") or !type_tokens_equal(tokens, idx + 17, idx + 23, "Result<nil,ProbeError>") or
            !tok_eq(tokens[idx + 23], ")")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        const member = string_token_body(tokens[idx + 7]) orelse continue;
        if (!std.mem.eql(u8, locator, locator_expected) or !std.mem.eql(u8, member, member_expected)) continue;
        const descriptor = registry.find(locator, member) orelse continue;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse continue) {
            .stream_writer => {
                if (found != null) return null;
                found = .{ .name = tokens[idx].lexeme, .descriptor = descriptor };
            },
            else => continue,
        }
    }
    return found;
}

fn find_stream_writer_function(tokens: []const lexer.Token) ?StreamWriterFunction {
    return find_stream_writer_function_named(tokens, null);
}

fn find_stream_writer_function_named(tokens: []const lexer.Token, expected_name: ?[]const u8) ?StreamWriterFunction {
    var idx: usize = 0;
    while (idx + 17 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "(") or
            tokens[idx + 2].kind != .ident or !tok_eq(tokens[idx + 3], "StreamWriter") or !tok_eq(tokens[idx + 4], "<") or
            !tok_eq(tokens[idx + 5], "u8") or !tok_eq(tokens[idx + 6], ">") or !tok_eq(tokens[idx + 7], ")") or
            !tok_eq(tokens[idx + 8], "-") or !tok_eq(tokens[idx + 9], ">") or !tok_eq(tokens[idx + 10], "Result") or
            !tok_eq(tokens[idx + 11], "<") or !tok_eq(tokens[idx + 12], "nil") or !tok_eq(tokens[idx + 13], ",")) continue;
        if (expected_name) |name| {
            if (!std.mem.eql(u8, tokens[idx].lexeme, name)) continue;
        }
        const result_end = find_matching(tokens, idx + 11, "<", ">") orelse continue;
        if (result_end + 1 >= tokens.len or !tok_eq(tokens[result_end + 1], "{")) continue;
        const body_end = find_matching(tokens, result_end + 1, "{", "}") orelse continue;
        return .{
            .name = tokens[idx].lexeme,
            .parameter_name = tokens[idx + 2].lexeme,
            .body_start = result_end + 2,
            .body_end = body_end,
            .result_start = idx + 10,
            .result_end = result_end + 1,
        };
    }
    return null;
}

const ParameterizedStreamWriterFunction = struct {
    name: []const u8,
    writer_name: []const u8,
    count_name: []const u8,
    value_name: []const u8,
    parameter_order: [3]ParameterizedParameterKind,
    body_start: usize,
    body_end: usize,
    result_start: usize,
    result_end: usize,
};

// Keep helper-chain admission bounded until general async-call lowering exists.
const max_parameterized_forwarding_hops: usize = 5;

const ParameterizedParameterKind = enum {
    writer,
    count,
    value,
};

const ParameterizedParameter = struct {
    name: []const u8,
    kind: ParameterizedParameterKind,
    next_idx: usize,
};

fn parse_parameterized_parameter(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?ParameterizedParameter {
    if (idx >= end_idx or tokens[idx].kind != .ident or idx + 1 >= end_idx) return null;
    if (tok_eq(tokens[idx + 1], "u64")) {
        return .{ .name = tokens[idx].lexeme, .kind = .count, .next_idx = idx + 2 };
    }
    if (tok_eq(tokens[idx + 1], "u8")) {
        return .{ .name = tokens[idx].lexeme, .kind = .value, .next_idx = idx + 2 };
    }
    if (idx + 4 >= end_idx or !tok_eq(tokens[idx + 1], "StreamWriter") or !tok_eq(tokens[idx + 2], "<") or
        !tok_eq(tokens[idx + 3], "u8") or !tok_eq(tokens[idx + 4], ">")) return null;
    return .{ .name = tokens[idx].lexeme, .kind = .writer, .next_idx = idx + 5 };
}

fn find_parameterized_stream_writer_function_named(
    tokens: []const lexer.Token,
    expected_name: []const u8,
) ?ParameterizedStreamWriterFunction {
    var idx: usize = 0;
    while (idx + 3 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], "async") or tokens[idx + 1].kind != .ident or
            !std.mem.eql(u8, tokens[idx + 1].lexeme, expected_name) or !tok_eq(tokens[idx + 2], "(")) continue;

        var parameters: [3]ParameterizedParameter = undefined;
        var parameter_order: [3]ParameterizedParameterKind = undefined;
        var seen = [_]bool{false} ** 3;
        var writer_name: []const u8 = undefined;
        var count_name: []const u8 = undefined;
        var value_name: []const u8 = undefined;
        var cursor = idx + 3;
        var parameter_index: usize = 0;
        var valid = true;
        while (parameter_index < parameters.len) : (parameter_index += 1) {
            const parameter = parse_parameterized_parameter(tokens, cursor, tokens.len) orelse {
                valid = false;
                break;
            };
            const kind_index = @intFromEnum(parameter.kind);
            if (seen[kind_index]) {
                valid = false;
                break;
            }
            seen[kind_index] = true;
            parameters[parameter_index] = parameter;
            parameter_order[parameter_index] = parameter.kind;
            switch (parameter.kind) {
                .writer => writer_name = parameter.name,
                .count => count_name = parameter.name,
                .value => value_name = parameter.name,
            }
            cursor = parameter.next_idx;
            if (parameter_index + 1 < parameters.len) {
                if (cursor >= tokens.len or !tok_eq(tokens[cursor], ",")) {
                    valid = false;
                    break;
                }
                cursor += 1;
            }
        }
        if (!valid or cursor >= tokens.len or !tok_eq(tokens[cursor], ")")) continue;
        if (cursor + 8 >= tokens.len or !tok_eq(tokens[cursor + 1], "-") or !tok_eq(tokens[cursor + 2], ">") or
            !tok_eq(tokens[cursor + 3], "Result") or !tok_eq(tokens[cursor + 4], "<") or !tok_eq(tokens[cursor + 5], "nil") or
            !tok_eq(tokens[cursor + 6], ",") or tokens[cursor + 7].kind != .ident or !tok_eq(tokens[cursor + 8], ">")) continue;
        const result_start = cursor + 3;
        const result_close = find_matching(tokens, cursor + 4, "<", ">") orelse continue;
        if (result_close + 1 >= tokens.len or !tok_eq(tokens[result_close + 1], "{")) continue;
        const body_end = find_matching(tokens, result_close + 1, "{", "}") orelse continue;
        return .{
            .name = tokens[idx + 1].lexeme,
            .writer_name = writer_name,
            .count_name = count_name,
            .value_name = value_name,
            .parameter_order = parameter_order,
            .body_start = result_close + 2,
            .body_end = body_end,
            .result_start = result_start,
            .result_end = result_close + 1,
        };
    }
    return null;
}

fn parse_parameterized_helper_binding(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    writer_name: []const u8,
    count_name: []const u8,
    value_name: []const u8,
) ?ParameterizedHelperBinding {
    if (idx + 5 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const result_end = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (result_end + 4 >= end_idx or !tok_eq(tokens[result_end + 1], "=") or tokens[result_end + 2].kind != .ident or
        !tok_eq(tokens[result_end + 3], "(")) return null;
    const helper = find_parameterized_stream_writer_function_named(tokens, tokens[result_end + 2].lexeme) orelse return null;
    var cursor = result_end + 4;
    for (helper.parameter_order, 0..) |kind, parameter_index| {
        if (cursor >= end_idx or tokens[cursor].kind != .ident) return null;
        const expected_name = switch (kind) {
            .writer => writer_name,
            .count => count_name,
            .value => value_name,
        };
        if (!std.mem.eql(u8, tokens[cursor].lexeme, expected_name)) return null;
        cursor += 1;
        if (parameter_index + 1 < helper.parameter_order.len) {
            if (cursor >= end_idx or !tok_eq(tokens[cursor], ",")) return null;
            cursor += 1;
        }
    }
    if (cursor >= end_idx or !tok_eq(tokens[cursor], ")")) return null;
    return .{
        .name = tokens[idx].lexeme,
        .host_name = tokens[result_end + 2].lexeme,
        .writer_name = writer_name,
        .count_name = count_name,
        .value_name = value_name,
        .result_start = idx + 3,
        .result_end = result_end,
        .next_idx = cursor + 1,
    };
}

fn parse_parameterized_forwarding_helper(
    tokens: []const lexer.Token,
    helper: ParameterizedStreamWriterFunction,
) ?ParameterizedStreamWriterFunction {
    const binding = parse_parameterized_helper_binding(
        tokens,
        helper.body_start,
        helper.body_end,
        helper.writer_name,
        helper.count_name,
        helper.value_name,
    ) orelse return null;
    const final_helper = find_parameterized_stream_writer_function_named(tokens, binding.host_name) orelse return null;
    const binding_result_end = find_matching(tokens, binding.result_start + 1, "<", ">") orelse return null;
    if (!token_ranges_equal(tokens, binding.result_start, binding_result_end + 1, final_helper.result_start, final_helper.result_end)) return null;
    const return_end = parse_return_await(tokens, binding.next_idx, helper.body_end, binding.name) orelse return null;
    if (return_end != helper.body_end) return null;
    return final_helper;
}

const StreamWriterHelperBody = struct {
    writes: ?GuestProducerWrites = null,
};

fn analyze_stream_writer_helper_body(
    tokens: []const lexer.Token,
    helper: StreamWriterFunction,
    host_name: []const u8,
) ?StreamWriterHelperBody {
    return analyze_stream_writer_helper_body_at_depth(tokens, helper, host_name, 0);
}

fn analyze_stream_writer_helper_body_at_depth(
    tokens: []const lexer.Token,
    helper: StreamWriterFunction,
    host_name: []const u8,
    forwarding_depth: usize,
) ?StreamWriterHelperBody {
    var writes: ?GuestProducerWrites = null;
    var cursor = helper.body_start;
    var closed = false;
    if (parse_guest_write_sequence(tokens, cursor, helper.body_end, helper.parameter_name)) |candidate| {
        writes = candidate;
        cursor = candidate.next_idx;
        if (parse_writer_defer_close(tokens, cursor, helper.body_end, helper.parameter_name)) |after_defer| {
            cursor = after_defer;
            closed = true;
        }
    } else if (parse_writer_defer_close(tokens, cursor, helper.body_end, helper.parameter_name)) |after_defer| {
        cursor = after_defer;
        closed = true;
    }
    const host = parse_future_binding(tokens, cursor, helper.body_end, helper.parameter_name) orelse return null;
    if (!std.mem.eql(u8, host.host_name, host_name)) {
        // A forwarding helper may pass the still-owned lease through one
        // private async helper. It must not write or close before transfer.
        if (writes != null or closed or forwarding_depth >= 1) return null;
        const next_helper = find_stream_writer_function_named(tokens, host.host_name) orelse return null;
        const nested = analyze_stream_writer_helper_body_at_depth(tokens, next_helper, host_name, forwarding_depth + 1) orelse return null;
        if (nested.writes == null) return null;
        return nested;
    }
    if (!closed) return null;
    const binding_result_end = find_matching(tokens, host.result_start + 1, "<", ">") orelse return null;
    if (!token_ranges_equal(tokens, host.result_start, binding_result_end + 1, helper.result_start, helper.result_end)) return null;
    const return_end = parse_return_await(tokens, host.next_idx, helper.body_end, host.name) orelse return null;
    if (return_end != helper.body_end) return null;
    return .{ .writes = writes };
}

pub const max_stream_u8_reads = 3;

pub const StreamU8Read = struct {
    pending_name: []const u8,
    item_name: []const u8,
};

const StreamU8Function = struct {
    name: []const u8,
    body_start: usize,
    body_end: usize,
};

const StreamU8HostBinding = struct {
    name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
};

const StreamU8TupleBinding = struct {
    handles_name: []const u8,
    error_name: []const u8,
    next_idx: usize,
};

const StreamU8AcquirePrefixParts = struct {
    handles_name: []const u8,
    reader_name: []const u8,
    completion_name: []const u8,
    next_idx: usize,
};

const StreamU8NamedBinding = struct {
    name: []const u8,
    next_idx: usize,
};

const StreamMirrorFunction = struct {
    name: []const u8,
    result_start: usize,
    result_end: usize,
    body_start: usize,
    body_end: usize,
};

const StreamMirrorBranch = struct {
    read: StreamMirrorRead,
    next_idx: usize,
};

fn parse_stream_mirror_function(tokens: []const lexer.Token) ?StreamMirrorFunction {
    var idx: usize = 0;
    while (idx + 7 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "(") or
            !tok_eq(tokens[idx + 2], ")") or !tok_eq(tokens[idx + 3], "-") or !tok_eq(tokens[idx + 4], ">")) continue;
        const result_start = idx + 5;
        var body_open = result_start;
        while (body_open < tokens.len and !tok_eq(tokens[body_open], "{")) : (body_open += 1) {}
        if (body_open == result_start or body_open == tokens.len) continue;
        const body_end = find_matching(tokens, body_open, "{", "}") orelse continue;
        return .{
            .name = tokens[idx].lexeme,
            .result_start = result_start,
            .result_end = body_open,
            .body_start = body_open + 1,
            .body_end = body_end,
        };
    }
    return null;
}

fn parse_stream_mirror_branch(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    pending_name: []const u8,
    item_name: []const u8,
    writer_name: []const u8,
    counter_name: []const u8,
) ?StreamMirrorBranch {
    if (idx + 8 >= end_idx or !tok_eq(tokens[idx], "if") or !tok_eq(tokens[idx + 1], "@") or
        !tok_eq(tokens[idx + 2], "is") or !tok_eq(tokens[idx + 3], "(") or tokens[idx + 4].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 4].lexeme, item_name) or !tok_eq(tokens[idx + 5], ",") or
        !tok_eq(tokens[idx + 6], "Ok") or !tok_eq(tokens[idx + 7], ")") or !tok_eq(tokens[idx + 8], "{")) return null;

    const then_open = idx + 8;
    const then_close = find_matching(tokens, then_open, "{", "}") orelse return null;
    if (then_close + 1 >= end_idx or !tok_eq(tokens[then_close + 1], "else") or
        !tok_eq(tokens[then_close + 2], "{")) return null;
    const else_open = then_close + 2;
    const else_close = find_matching(tokens, else_open, "{", "}") orelse return null;
    if (else_close + 1 != end_idx) return null;

    const value = parse_stream_mirror_value_binding(tokens, then_open + 1, then_close, item_name) orelse return null;
    const write = parse_future_binding(tokens, value.next_idx, then_close, value.name) orelse return null;
    if (!std.mem.eql(u8, write.host_name, writer_name) or
        !type_tokens_equal(tokens, write.result_start, write.result_end, "Result<nil,StreamError>")) return null;
    const write_result = parse_stream_mirror_write_await(tokens, write.next_idx, then_close, write.name) orelse return null;
    const after_discard = parse_guest_discard(tokens, write_result.next_idx, then_close, write_result.name) orelse return null;
    const after_decrement = parse_countdown_decrement(tokens, after_discard, then_close, counter_name) orelse return null;
    if (after_decrement != then_close) return null;

    if (else_open + 1 >= else_close or !tok_eq(tokens[else_open + 1], "break") or else_open + 2 != else_close) return null;
    return .{
        .read = .{
            .pending_name = pending_name,
            .item_name = item_name,
            .value_name = value.name,
            .write_pending_name = write.name,
            .write_result_name = write_result.name,
        },
        .next_idx = else_close + 1,
    };
}

fn parse_stream_mirror_value_binding(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    item_name: []const u8,
) ?StreamU8NamedBinding {
    if (idx + 3 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "u8") or
        !tok_eq(tokens[idx + 2], "=") or tokens[idx + 3].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 3].lexeme, item_name)) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = idx + 4 };
}

fn parse_stream_mirror_write_await(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    future_name: []const u8,
) ?StreamU8NamedBinding {
    if (idx + 7 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Result") or
        !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "nil") or !tok_eq(tokens[idx + 4], ",") or
        tokens[idx + 5].kind != .ident or !tok_eq(tokens[idx + 6], ">") or !tok_eq(tokens[idx + 7], "=") or
        !std.mem.eql(u8, tokens[idx + 5].lexeme, "StreamError")) return null;
    const await_end = parse_await(tokens, idx + 8, end_idx, future_name) orelse return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = await_end };
}

fn parse_stream_u8_function(tokens: []const lexer.Token) ?StreamU8Function {
    var idx: usize = 0;
    while (idx + 7 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "(") or !tok_eq(tokens[idx + 2], ")") or !tok_eq(tokens[idx + 3], "-") or !tok_eq(tokens[idx + 4], ">") or !tok_eq(tokens[idx + 5], "nil") or !tok_eq(tokens[idx + 6], "{")) continue;
        const body_end = find_matching(tokens, idx + 6, "{", "}") orelse continue;
        return .{ .name = tokens[idx].lexeme, .body_start = idx + 7, .body_end = body_end };
    }
    return null;
}

fn find_stream_u8_host_binding(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?StreamU8HostBinding {
    var found: ?StreamU8HostBinding = null;
    var idx: usize = 0;
    while (idx + 30 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            (!tok_eq(tokens[idx + 3], "host") and !tok_eq(tokens[idx + 3], "host_func")) or !tok_eq(tokens[idx + 4], "(")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        const member = string_token_body(tokens[idx + 7]) orelse continue;
        if (!tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 8], ",") or !stream_u8_host_signature_at(tokens, idx)) continue;
        const descriptor = registry.find(locator, member) orelse continue;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse continue) {
            .stream_reader_acquire => {
                if (found != null) return null;
                found = .{ .name = tokens[idx].lexeme, .descriptor = descriptor };
            },
            else => continue,
        }
    }
    return found;
}

fn find_stream_mirror_source_host_binding(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?StreamU8HostBinding {
    const locator_expected = "do:stream-probe@0.1.0";
    const member_expected = "read-via-stream";
    var found: ?StreamU8HostBinding = null;
    var idx: usize = 0;
    while (idx + 30 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            (!tok_eq(tokens[idx + 3], "host") and !tok_eq(tokens[idx + 3], "host_func")) or !tok_eq(tokens[idx + 4], "(")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        const member = string_token_body(tokens[idx + 7]) orelse continue;
        if (!tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 8], ",") or
            !std.mem.eql(u8, locator, locator_expected) or !std.mem.eql(u8, member, member_expected) or
            !stream_u8_host_signature_at(tokens, idx)) continue;
        const descriptor = registry.find(locator, member) orelse continue;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse continue) {
            .stream_reader_acquire => {
                if (found != null) return null;
                found = .{ .name = tokens[idx].lexeme, .descriptor = descriptor };
            },
            else => continue,
        }
    }
    return found;
}

fn stream_u8_host_signature_at(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 30 >= tokens.len or !tok_eq(tokens[idx + 9], "(") or !tok_eq(tokens[idx + 10], ")") or !tok_eq(tokens[idx + 11], "-") or !tok_eq(tokens[idx + 12], ">") or !tok_eq(tokens[idx + 13], "Tuple") or !tok_eq(tokens[idx + 14], "<") or !tok_eq(tokens[idx + 15], "Stream") or !tok_eq(tokens[idx + 16], "<") or !tok_eq(tokens[idx + 17], "u8") or !tok_eq(tokens[idx + 18], ">") or !tok_eq(tokens[idx + 19], ",") or !tok_eq(tokens[idx + 20], "Future") or !tok_eq(tokens[idx + 21], "<") or !tok_eq(tokens[idx + 22], "Result") or !tok_eq(tokens[idx + 23], "<") or !tok_eq(tokens[idx + 24], "nil") or !tok_eq(tokens[idx + 25], ",") or tokens[idx + 26].kind != .ident or !tok_eq(tokens[idx + 27], ">") or !tok_eq(tokens[idx + 28], ">") or !tok_eq(tokens[idx + 29], ">") or !tok_eq(tokens[idx + 30], ")")) return false;
    return std.mem.endsWith(u8, tokens[idx + 26].lexeme, "Error");
}

fn parse_stream_u8_tuple_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize, host_name: []const u8) ?StreamU8TupleBinding {
    if (idx + 21 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Tuple") or !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "Stream") or !tok_eq(tokens[idx + 4], "<") or !tok_eq(tokens[idx + 5], "u8") or !tok_eq(tokens[idx + 6], ">") or !tok_eq(tokens[idx + 7], ",") or !tok_eq(tokens[idx + 8], "Future") or !tok_eq(tokens[idx + 9], "<") or !tok_eq(tokens[idx + 10], "Result") or !tok_eq(tokens[idx + 11], "<") or !tok_eq(tokens[idx + 12], "nil") or !tok_eq(tokens[idx + 13], ",") or tokens[idx + 14].kind != .ident or !tok_eq(tokens[idx + 15], ">") or !tok_eq(tokens[idx + 16], ">") or !tok_eq(tokens[idx + 17], ">") or !tok_eq(tokens[idx + 18], "=") or tokens[idx + 19].kind != .ident or !std.mem.eql(u8, tokens[idx + 19].lexeme, host_name) or !tok_eq(tokens[idx + 20], "(") or !tok_eq(tokens[idx + 21], ")")) return null;
    if (!std.mem.endsWith(u8, tokens[idx + 14].lexeme, "Error")) return null;
    return .{ .handles_name = tokens[idx].lexeme, .error_name = tokens[idx + 14].lexeme, .next_idx = idx + 22 };
}

fn parse_stream_u8_acquire_prefix(tokens: []const lexer.Token, idx: usize, end_idx: usize, host_name: []const u8) ?StreamU8AcquirePrefixParts {
    const tuple = parse_stream_u8_tuple_binding(tokens, idx, end_idx, host_name) orelse return null;
    const reader = parse_stream_u8_reader_extract(tokens, tuple.next_idx, end_idx, tuple.handles_name) orelse return null;
    const completion = parse_stream_u8_completion_extract(tokens, reader.next_idx, end_idx, tuple.handles_name, tuple.error_name) orelse return null;
    return .{
        .handles_name = tuple.handles_name,
        .reader_name = reader.name,
        .completion_name = completion.name,
        .next_idx = completion.next_idx,
    };
}

fn parse_stream_u8_reader_extract(tokens: []const lexer.Token, idx: usize, end_idx: usize, handles_name: []const u8) ?StreamU8NamedBinding {
    if (idx + 12 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Stream") or !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "u8") or !tok_eq(tokens[idx + 4], ">") or !tok_eq(tokens[idx + 5], "=") or !tok_eq(tokens[idx + 6], "@") or !tok_eq(tokens[idx + 7], "get") or !tok_eq(tokens[idx + 8], "(") or tokens[idx + 9].kind != .ident or !std.mem.eql(u8, tokens[idx + 9].lexeme, handles_name) or !tok_eq(tokens[idx + 10], ",") or !tok_eq(tokens[idx + 11], "0") or !tok_eq(tokens[idx + 12], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = idx + 13 };
}

fn parse_stream_u8_completion_extract(tokens: []const lexer.Token, idx: usize, end_idx: usize, handles_name: []const u8, error_name: []const u8) ?StreamU8NamedBinding {
    if (idx + 17 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "Result") or !tok_eq(tokens[idx + 4], "<") or !tok_eq(tokens[idx + 5], "nil") or !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .ident or !std.mem.eql(u8, tokens[idx + 7].lexeme, error_name) or !tok_eq(tokens[idx + 8], ">") or !tok_eq(tokens[idx + 9], ">") or !tok_eq(tokens[idx + 10], "=") or !tok_eq(tokens[idx + 11], "@") or !tok_eq(tokens[idx + 12], "get") or !tok_eq(tokens[idx + 13], "(") or tokens[idx + 14].kind != .ident or !std.mem.eql(u8, tokens[idx + 14].lexeme, handles_name) or !tok_eq(tokens[idx + 15], ",") or !tok_eq(tokens[idx + 16], "1") or !tok_eq(tokens[idx + 17], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = idx + 18 };
}

fn parse_stream_u8_next(tokens: []const lexer.Token, idx: usize, end_idx: usize, reader_name: []const u8) ?StreamU8NamedBinding {
    if (idx + 15 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "Result") or !tok_eq(tokens[idx + 4], "<") or !tok_eq(tokens[idx + 5], "u8") or !tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 7], "nil") or !tok_eq(tokens[idx + 8], ">") or !tok_eq(tokens[idx + 9], ">") or !tok_eq(tokens[idx + 10], "=") or !tok_eq(tokens[idx + 11], "@") or !tok_eq(tokens[idx + 12], "next") or !tok_eq(tokens[idx + 13], "(") or tokens[idx + 14].kind != .ident or !std.mem.eql(u8, tokens[idx + 14].lexeme, reader_name) or !tok_eq(tokens[idx + 15], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = idx + 16 };
}

fn parse_stream_u8_await(tokens: []const lexer.Token, idx: usize, end_idx: usize, pending_name: []const u8) ?StreamU8NamedBinding {
    if (idx + 7 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Result") or !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "u8") or !tok_eq(tokens[idx + 4], ",") or !tok_eq(tokens[idx + 5], "nil") or !tok_eq(tokens[idx + 6], ">") or !tok_eq(tokens[idx + 7], "=")) return null;
    const await_end = parse_await(tokens, idx + 8, end_idx, pending_name) orelse return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = await_end };
}

fn parse_stream_u8_item_discard(tokens: []const lexer.Token, idx: usize, end_idx: usize, item_name: []const u8) ?usize {
    if (idx + 2 >= end_idx or !tok_eq(tokens[idx], "_") or !tok_eq(tokens[idx + 1], "=") or tokens[idx + 2].kind != .ident or !std.mem.eql(u8, tokens[idx + 2].lexeme, item_name)) return null;
    return idx + 3;
}

fn parse_stream_u8_cancel(tokens: []const lexer.Token, idx: usize, end_idx: usize, completion_name: []const u8) ?usize {
    if (idx + 4 >= end_idx or !tok_eq(tokens[idx], "@") or !tok_eq(tokens[idx + 1], "cancel") or !tok_eq(tokens[idx + 2], "(") or tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, completion_name) or !tok_eq(tokens[idx + 4], ")")) return null;
    return idx + 5;
}

fn analyze_if_eq_parameter_literal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    function: Function,
    parameter_storage: async_model.FrameSlotStorage,
    registry: p3_async_manifest.Registry,
) !?ComponentAsyncFunctionPlan {
    const start = function.body_start;
    if (start + 7 >= function.body_end or !tok_eq(tokens[start], "if") or !tok_eq(tokens[start + 1], "@") or !tok_eq(tokens[start + 2], "eq") or !tok_eq(tokens[start + 3], "(") or tokens[start + 4].kind != .ident or !std.mem.eql(u8, tokens[start + 4].lexeme, function.parameter_name) or !tok_eq(tokens[start + 5], ",") or tokens[start + 6].kind != .number or !tok_eq(tokens[start + 7], ")")) return null;
    if (parameter_storage != .i64 or !std.mem.eql(u8, function.parameter_type, "u64")) return error.UnsupportedP3WaitForComponent;
    const condition = std.fmt.parseUnsigned(u64, tokens[start + 6].lexeme, 10) catch return error.UnsupportedP3WaitForComponent;
    const then_open = start + 8;
    if (then_open >= function.body_end or !tok_eq(tokens[then_open], "{")) return null;
    const then_close = find_matching(tokens, then_open, "{", "}") orelse return error.UnsupportedP3WaitForComponent;
    const else_idx = then_close + 1;
    if (else_idx + 1 >= function.body_end or !tok_eq(tokens[else_idx], "else") or !tok_eq(tokens[else_idx + 1], "{")) return error.UnsupportedP3WaitForComponent;
    const else_open = else_idx + 1;
    const else_close = find_matching(tokens, else_open, "{", "}") orelse return error.UnsupportedP3WaitForComponent;
    var first: Operation = undefined;
    var second: Operation = undefined;
    var operations: []Operation = undefined;
    if (else_close == function.body_end - 1) {
        first = try parse_if_branch_operation(tokens, then_open + 1, then_close, function, parameter_storage, registry, null, true);
        second = try parse_if_branch_operation(tokens, else_open + 1, else_close, function, parameter_storage, registry, first.descriptor, true);
        operations = try allocator.dupe(Operation, &.{ first, second });
    } else {
        first = try parse_if_branch_operation(tokens, then_open + 1, then_close, function, parameter_storage, registry, null, false);
        second = try parse_if_branch_operation(tokens, else_open + 1, else_close, function, parameter_storage, registry, first.descriptor, false);
        const joined = try parse_if_branch_operation(tokens, else_close + 1, function.body_end, function, parameter_storage, registry, first.descriptor, true);
        operations = try allocator.dupe(Operation, &.{ first, second, joined });
    }
    errdefer allocator.free(operations);
    return .{
        .export_name = function.name,
        .parameter = .{ .name = function.parameter_name, .storage = parameter_storage },
        .operations = operations,
        .control = .{ .if_eq_parameter_literal = condition },
        .terminal = .await,
        .async_plan = try collect_async_plan(allocator, tokens, function.name),
    };
}

fn analyze_loop_countdown(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    function: Function,
    parameter_storage: async_model.FrameSlotStorage,
    registry: p3_async_manifest.Registry,
) !?ComponentAsyncFunctionPlan {
    if (parameter_storage != .i64 or !std.mem.eql(u8, function.parameter_type, "u64")) return null;
    const counter = parse_loop_countdown_binding(tokens, function.body_start, function.body_end, function.parameter_type, function.parameter_name) orelse return null;
    const loop_idx = counter.next_idx;
    if (loop_idx >= function.body_end or !tok_eq(tokens[loop_idx], "loop") or loop_idx + 1 >= function.body_end or !tok_eq(tokens[loop_idx + 1], "{")) return null;
    const loop_open = loop_idx + 1;
    const loop_close = find_matching(tokens, loop_open, "{", "}") orelse return error.UnsupportedP3WaitForComponent;
    const final_return = parse_void_return(tokens, loop_close + 1, function.body_end) orelse return error.UnsupportedP3WaitForComponent;
    if (final_return != function.body_end) return error.UnsupportedP3WaitForComponent;

    const first_body_idx = loop_open + 1;
    const pre_guard_end = parse_countdown_break(tokens, first_body_idx, loop_close, counter.name);
    const pre_guard = pre_guard_end != null;
    const binding_idx = pre_guard_end orelse first_body_idx;
    if (!pre_guard and counter.initial == .u64_literal and counter.initial.u64_literal == 0) return error.UnsupportedP3WaitForComponent;
    const binding = parse_future_binding_any(tokens, binding_idx, loop_close) orelse return error.UnsupportedP3WaitForComponent;
    const host_argument: LoopCountdownHostArgument = if (std.mem.eql(u8, binding.argument_name, function.parameter_name))
        .parameter
    else if (std.mem.eql(u8, binding.argument_name, counter.name))
        .counter
    else
        return error.UnsupportedP3WaitForComponent;
    const host = find_host_binding(tokens, binding.host_name) orelse return error.UnsupportedP3WaitForComponent;
    const descriptor = registry.find(host.locator, host.member) orelse return error.UnsupportedP3WaitForComponent;
    const validated = try validate_operation_descriptor(tokens, function, binding, descriptor, parameter_storage, null, false);
    if (validated.shape != .scalar_unit) return error.UnsupportedP3WaitForComponent;
    const after_await = parse_await(tokens, binding.next_idx, loop_close, binding.name) orelse return error.UnsupportedP3WaitForComponent;
    const after_decrement = parse_countdown_decrement(tokens, after_await, loop_close, counter.name) orelse return error.UnsupportedP3WaitForComponent;
    if (pre_guard) {
        if (after_decrement != loop_close) return error.UnsupportedP3WaitForComponent;
    } else {
        const after_break = parse_countdown_break(tokens, after_decrement, loop_close, counter.name) orelse return error.UnsupportedP3WaitForComponent;
        if (after_break != loop_close) return error.UnsupportedP3WaitForComponent;
    }

    const operations = try allocator.dupe(Operation, &.{.{
        .descriptor = descriptor,
        .future_name = binding.name,
        .argument_name = binding.argument_name,
        .argument = .parameter,
        .payload_shape = .scalar_unit,
        .result_payload = null,
        .error_variants = validated.error_variants,
    }});
    errdefer allocator.free(operations);
    return .{
        .export_name = function.name,
        .parameter = .{ .name = function.parameter_name, .storage = parameter_storage },
        .operations = operations,
        .control = .{ .loop_countdown = .{ .counter_name = counter.name, .initial = counter.initial, .host_argument = host_argument, .pre_guard = pre_guard } },
        .terminal = .await,
        .async_plan = try collect_async_plan(allocator, tokens, function.name),
    };
}

fn parse_countdown_decrement(tokens: []const lexer.Token, idx: usize, end: usize, counter_name: []const u8) ?usize {
    if (idx + 8 >= end or tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, counter_name) or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "sub") or !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .ident or !std.mem.eql(u8, tokens[idx + 5].lexeme, counter_name) or !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .number or !std.mem.eql(u8, tokens[idx + 7].lexeme, "1") or !tok_eq(tokens[idx + 8], ")")) return null;
    return idx + 9;
}

fn parse_countdown_break(tokens: []const lexer.Token, idx: usize, end: usize, counter_name: []const u8) ?usize {
    if (idx + 10 >= end or !tok_eq(tokens[idx], "if") or !tok_eq(tokens[idx + 1], "@") or !tok_eq(tokens[idx + 2], "eq") or !tok_eq(tokens[idx + 3], "(") or tokens[idx + 4].kind != .ident or !std.mem.eql(u8, tokens[idx + 4].lexeme, counter_name) or !tok_eq(tokens[idx + 5], ",") or tokens[idx + 6].kind != .number or !std.mem.eql(u8, tokens[idx + 6].lexeme, "0") or !tok_eq(tokens[idx + 7], ")") or !tok_eq(tokens[idx + 8], "{") or !tok_eq(tokens[idx + 9], "break") or !tok_eq(tokens[idx + 10], "}")) return null;
    return idx + 11;
}

fn parse_if_branch_operation(
    tokens: []const lexer.Token,
    start: usize,
    end: usize,
    function: Function,
    parameter_storage: async_model.FrameSlotStorage,
    registry: p3_async_manifest.Registry,
    contract: ?p3_async_manifest.Descriptor,
    require_terminal_return: bool,
) !Operation {
    const binding = parse_future_binding(tokens, start, end, function.parameter_name) orelse return error.UnsupportedP3WaitForComponent;
    const host = find_host_binding(tokens, binding.host_name) orelse return error.UnsupportedP3WaitForComponent;
    const descriptor = registry.find(host.locator, host.member) orelse return error.UnsupportedP3WaitForComponent;
    const validated = try validate_operation_descriptor(tokens, function, binding, descriptor, parameter_storage, contract, false);
    if (validated.shape != .scalar_unit) return error.UnsupportedP3WaitForComponent;
    const after_await = parse_await(tokens, binding.next_idx, end, binding.name) orelse return error.UnsupportedP3WaitForComponent;
    if (require_terminal_return) {
        const after_return = parse_void_return(tokens, after_await, end) orelse return error.UnsupportedP3WaitForComponent;
        if (after_return != end) return error.UnsupportedP3WaitForComponent;
    } else if (after_await != end) return error.UnsupportedP3WaitForComponent;
    return .{
        .descriptor = descriptor,
        .future_name = binding.name,
        .argument_name = function.parameter_name,
        .argument = .parameter,
        .payload_shape = .scalar_unit,
        .result_payload = null,
        .error_variants = validated.error_variants,
    };
}

const Function = struct {
    name: []const u8,
    parameter_name: []const u8,
    parameter_type: []const u8,
    result_start: usize,
    result_end: usize,
    body_start: usize,
    body_end: usize,
};

const HostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
    parameter_type: []const u8,
};

const ScalarAlias = struct {
    name: []const u8,
    next_idx: usize,
};

const ScalarBinding = struct {
    name: []const u8,
    argument: ScalarArgument,
};

const U64LiteralBinding = struct {
    name: []const u8,
    value: u64,
    next_idx: usize,
};

const LoopCountdownBinding = struct {
    name: []const u8,
    initial: LoopCountdownInitial,
    next_idx: usize,
};

const U64AddParameterLiteralBinding = struct {
    name: []const u8,
    value: u64,
    next_idx: usize,
};

const PostAwaitComputationBinding = struct {
    value: PostAwaitComputation,
    next_idx: usize,
};

const FutureBinding = struct {
    name: []const u8,
    host_name: []const u8,
    argument_name: []const u8,
    result_start: usize,
    result_end: usize,
    next_idx: usize,
};

fn collect_async_plan(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    export_name: []const u8,
) !async_model.AsyncFunctionPlan {
    var functions = std.ArrayList(codegen_model.FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try codegen_collect_functions.collect_func_decls(allocator, tokens, &.{}, &.{}, null, &functions);
    const plans = try async_model.collect_async_functions(allocator, functions.items);
    var selected: ?async_model.AsyncFunctionPlan = null;
    for (plans, 0..) |*plan, idx| {
        if (std.mem.eql(u8, plan.source_name, export_name)) {
            selected = plan.*;
            plan.* = undefined;
            for (plans[0..idx]) |*previous| previous.deinit(allocator);
            for (plans[idx + 1 ..]) |*following| following.deinit(allocator);
            allocator.free(plans);
            return selected.?;
        }
    }
    allocator.free(plans);
    return error.UnsupportedP3WaitForComponent;
}

fn validate_operation_descriptor(
    tokens: []const lexer.Token,
    function: Function,
    binding: FutureBinding,
    descriptor: p3_async_manifest.Descriptor,
    parameter_storage: async_model.FrameSlotStorage,
    contract: ?p3_async_manifest.Descriptor,
    allow_cancel_nil_result: bool,
) !ValidatedPayload {
    const shape = p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3WaitForComponent;
    var validated: ValidatedPayload = switch (shape) {
        .scalar_unit => |scalar| blk: {
            const core_type = async_model.frame_slot_storage_core_wasm_type(parameter_storage) orelse return error.UnsupportedP3WaitForComponent;
            if (!std.mem.eql(u8, function.parameter_type, scalar.source_param) or !std.mem.eql(u8, core_type, scalar.core_param)) return error.UnsupportedP3WaitForComponent;
            break :blk .{ .shape = .scalar_unit, .result_payload = null };
        },
        .scalar_result => |result| blk: {
            const core_type = async_model.frame_slot_storage_core_wasm_type(parameter_storage) orelse return error.UnsupportedP3WaitForComponent;
            if (descriptor.params.len != 1 or descriptor.canonical.core_params.len == 0 or
                !std.mem.eql(u8, function.parameter_type, descriptor.params[0]) or
                !std.mem.eql(u8, core_type, descriptor.canonical.core_params[descriptor.canonical.core_params.len - 1]))
            {
                return error.UnsupportedP3WaitForComponent;
            }
            break :blk .{ .shape = .scalar_result, .result_payload = .{
                .tag = result.tag,
                .ok = result.ok,
                .err = result.err,
            } };
        },
        .resource_result_2word => |resource| blk: {
            if (!std.mem.eql(u8, function.parameter_type, resource.source_param) or parameter_storage != .unsupported) return error.UnsupportedP3WaitForComponent;
            break :blk .{ .shape = .resource_result_2word, .result_payload = null };
        },
        else => return error.UnsupportedP3WaitForComponent,
    };
    validated.error_variants = descriptor.canonical.error_variants;
    const payload_shape = validated.shape;
    const future_result = if (payload_shape == .scalar_unit) "nil" else descriptor.result;
    if ((!type_tokens_equal(tokens, function.result_start, function.result_end, descriptor.result) and !allow_cancel_nil_result) or
        !type_tokens_equal(tokens, binding.result_start, binding.result_end, future_result)) return error.UnsupportedP3WaitForComponent;
    if (contract) |first| {
        if (!std.mem.eql(u8, first.wit.package, descriptor.wit.package) or
            !std.mem.eql(u8, first.wit.interface, descriptor.wit.interface) or
            !std.mem.eql(u8, first.wit.world, descriptor.wit.world)) return error.UnsupportedP3WaitForComponent;
    }
    return validated;
}

const ValidatedPayload = struct {
    shape: PayloadShape,
    result_payload: ?p3_async_manifest.ResultPayload,
    error_variants: []const p3_async_manifest.ErrorVariantPayload = &.{},
};

fn parse_async_function(tokens: []const lexer.Token) ?Function {
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        const name_idx: usize = if (tok_eq(tokens[idx], "async")) idx + 1 else idx;
        const open_params: usize = if (tok_eq(tokens[idx], "async")) idx + 2 else idx + 1;
        if (name_idx >= tokens.len or open_params + 2 >= tokens.len or
            tokens[name_idx].kind != .ident or !tok_eq(tokens[open_params], "(")) continue;
        const close_params = find_matching(tokens, open_params, "(", ")") orelse continue;
        if (close_params != open_params + 3 or tokens[open_params + 1].kind != .ident or
            tokens[open_params + 2].kind != .ident) continue;
        if (!tok_eq(tokens[close_params + 1], "-") or !tok_eq(tokens[close_params + 2], ">")) continue;
        const result_start = close_params + 3;
        var body_open = result_start;
        while (body_open < tokens.len and !tok_eq(tokens[body_open], "{")) : (body_open += 1) {}
        if (body_open == result_start or body_open == tokens.len) continue;
        const body_end = find_matching(tokens, body_open, "{", "}") orelse continue;
        return .{
            .name = tokens[name_idx].lexeme,
            .parameter_name = tokens[open_params + 1].lexeme,
            .parameter_type = tokens[open_params + 2].lexeme,
            .result_start = result_start,
            .result_end = body_open,
            .body_start = body_open + 1,
            .body_end = body_end,
        };
    }
    return null;
}

fn find_host_binding(tokens: []const lexer.Token, name: []const u8) ?HostBinding {
    var idx: usize = 0;
    while (idx + 15 < tokens.len) : (idx += 1) {
        if (parse_host_binding_at(tokens, idx)) |binding| {
            if (std.mem.eql(u8, binding.name, name)) return binding;
        }
    }
    return null;
}

fn parse_host_binding_at(tokens: []const lexer.Token, idx: usize) ?HostBinding {
    if (idx + 13 >= tokens.len or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host_func") or !tok_eq(tokens[idx + 4], "(")) return null;
    const locator = string_token_body(tokens[idx + 5]) orelse return null;
    if (!tok_eq(tokens[idx + 6], ",")) return null;
    const member = string_token_body(tokens[idx + 7]) orelse return null;
    if (!tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or tokens[idx + 10].kind != .ident or !tok_eq(tokens[idx + 11], ")")) return null;
    if (!tok_eq(tokens[idx + 12], "-") or !tok_eq(tokens[idx + 13], ">")) return null;
    return .{
        .name = tokens[idx].lexeme,
        .locator = locator,
        .member = member,
        .parameter_type = tokens[idx + 10].lexeme,
    };
}

fn parse_scalar_alias(tokens: []const lexer.Token, idx: usize, end_idx: usize, parameter_type: []const u8, source_name: []const u8) ?ScalarAlias {
    if (idx + 3 >= end_idx or tokens[idx].kind != .ident or tokens[idx + 1].kind != .ident or !tok_eq(tokens[idx + 2], "=") or tokens[idx + 3].kind != .ident) return null;
    if (!std.mem.eql(u8, tokens[idx + 1].lexeme, parameter_type) or !std.mem.eql(u8, tokens[idx + 3].lexeme, source_name)) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = idx + 4 };
}

fn parse_u64_literal_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize, parameter_type: []const u8) ?U64LiteralBinding {
    if (!std.mem.eql(u8, parameter_type, "u64") or idx + 3 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "u64") or !tok_eq(tokens[idx + 2], "=") or tokens[idx + 3].kind != .number) return null;
    const value = std.fmt.parseUnsigned(u64, tokens[idx + 3].lexeme, 10) catch return null;
    return .{ .name = tokens[idx].lexeme, .value = value, .next_idx = idx + 4 };
}

fn parse_loop_countdown_binding(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    parameter_type: []const u8,
    parameter_name: []const u8,
) ?LoopCountdownBinding {
    if (!std.mem.eql(u8, parameter_type, "u64") or idx + 3 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "u64") or !tok_eq(tokens[idx + 2], "=")) return null;
    const value = tokens[idx + 3];
    if (value.kind == .number) {
        const literal = std.fmt.parseUnsigned(u64, value.lexeme, 10) catch return null;
        return .{ .name = tokens[idx].lexeme, .initial = .{ .u64_literal = literal }, .next_idx = idx + 4 };
    }
    if (value.kind == .ident and std.mem.eql(u8, value.lexeme, parameter_name)) {
        return .{ .name = tokens[idx].lexeme, .initial = .parameter, .next_idx = idx + 4 };
    }
    if (idx + 9 >= end_idx or !tok_eq(value, "@") or !tok_eq(tokens[idx + 4], "add") or !tok_eq(tokens[idx + 5], "(") or tokens[idx + 6].kind != .ident or !std.mem.eql(u8, tokens[idx + 6].lexeme, parameter_name) or !tok_eq(tokens[idx + 7], ",") or tokens[idx + 8].kind != .number or !tok_eq(tokens[idx + 9], ")")) return null;
    const literal = std.fmt.parseUnsigned(u64, tokens[idx + 8].lexeme, 10) catch return null;
    return .{ .name = tokens[idx].lexeme, .initial = .{ .parameter_add_u64_literal = literal }, .next_idx = idx + 10 };
}

fn parse_u64_add_parameter_literal_binding(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    parameter_type: []const u8,
    parameter_name: []const u8,
) ?U64AddParameterLiteralBinding {
    if (!std.mem.eql(u8, parameter_type, "u64") or idx + 9 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "u64") or !tok_eq(tokens[idx + 2], "=") or !tok_eq(tokens[idx + 3], "@") or !tok_eq(tokens[idx + 4], "add") or !tok_eq(tokens[idx + 5], "(") or tokens[idx + 6].kind != .ident or !std.mem.eql(u8, tokens[idx + 6].lexeme, parameter_name) or !tok_eq(tokens[idx + 7], ",") or tokens[idx + 8].kind != .number or !tok_eq(tokens[idx + 9], ")")) return null;
    const value = std.fmt.parseUnsigned(u64, tokens[idx + 8].lexeme, 10) catch return null;
    return .{ .name = tokens[idx].lexeme, .value = value, .next_idx = idx + 10 };
}

fn parse_post_await_computation(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    source_name: []const u8,
) ?PostAwaitComputationBinding {
    if (idx + 12 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "u64") or
        !tok_eq(tokens[idx + 2], "=") or !tok_eq(tokens[idx + 3], "@") or !tok_eq(tokens[idx + 4], "add") or
        !tok_eq(tokens[idx + 5], "(") or tokens[idx + 6].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 6].lexeme, source_name) or !tok_eq(tokens[idx + 7], ",") or
        tokens[idx + 8].kind != .number or !tok_eq(tokens[idx + 9], ")") or
        !tok_eq(tokens[idx + 10], "_") or !tok_eq(tokens[idx + 11], "=") or
        tokens[idx + 12].kind != .ident or !std.mem.eql(u8, tokens[idx + 12].lexeme, tokens[idx].lexeme)) return null;
    const addend = std.fmt.parseUnsigned(u64, tokens[idx + 8].lexeme, 10) catch return null;
    return .{
        .value = .{
            .source_name = source_name,
            .result_name = tokens[idx].lexeme,
            .addend = addend,
        },
        .next_idx = idx + 13,
    };
}

fn parse_future_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize, argument_name: []const u8) ?FutureBinding {
    if (idx + 8 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const result_end = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (result_end + 5 >= end_idx or !tok_eq(tokens[result_end + 1], "=") or tokens[result_end + 2].kind != .ident or !tok_eq(tokens[result_end + 3], "(") or tokens[result_end + 4].kind != .ident or !std.mem.eql(u8, tokens[result_end + 4].lexeme, argument_name) or !tok_eq(tokens[result_end + 5], ")")) return null;
    return .{
        .name = tokens[idx].lexeme,
        .host_name = tokens[result_end + 2].lexeme,
        .argument_name = tokens[result_end + 4].lexeme,
        .result_start = idx + 3,
        .result_end = result_end,
        .next_idx = result_end + 6,
    };
}

fn parse_future_binding_any(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?FutureBinding {
    if (idx + 8 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const result_end = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (result_end + 5 >= end_idx or !tok_eq(tokens[result_end + 1], "=") or tokens[result_end + 2].kind != .ident or !tok_eq(tokens[result_end + 3], "(") or tokens[result_end + 4].kind != .ident or !tok_eq(tokens[result_end + 5], ")")) return null;
    return .{
        .name = tokens[idx].lexeme,
        .host_name = tokens[result_end + 2].lexeme,
        .argument_name = tokens[result_end + 4].lexeme,
        .result_start = idx + 3,
        .result_end = result_end,
        .next_idx = result_end + 6,
    };
}

fn parse_await(tokens: []const lexer.Token, idx: usize, end_idx: usize, future_name: []const u8) ?usize {
    const op_idx = if (tok_eq(tokens[idx], "@") and idx + 1 < end_idx and tok_eq(tokens[idx + 1], "await")) idx + 1 else idx;
    if (op_idx + 3 >= end_idx or !tok_eq(tokens[op_idx], "await") or !tok_eq(tokens[op_idx + 1], "(") or tokens[op_idx + 2].kind != .ident or !std.mem.eql(u8, tokens[op_idx + 2].lexeme, future_name) or !tok_eq(tokens[op_idx + 3], ")")) return null;
    return op_idx + 4;
}

fn parse_return_await(tokens: []const lexer.Token, idx: usize, end_idx: usize, future_name: []const u8) ?usize {
    if (idx >= end_idx or !tok_eq(tokens[idx], "return")) return null;
    const op_idx = if (idx + 2 < end_idx and tok_eq(tokens[idx + 1], "@") and tok_eq(tokens[idx + 2], "await")) idx + 2 else idx + 1;
    if (op_idx + 3 >= end_idx or !tok_eq(tokens[op_idx], "await") or !tok_eq(tokens[op_idx + 1], "(") or tokens[op_idx + 2].kind != .ident or !std.mem.eql(u8, tokens[op_idx + 2].lexeme, future_name) or !tok_eq(tokens[op_idx + 3], ")")) return null;
    return op_idx + 4;
}

fn parse_void_return(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?usize {
    if (idx >= end_idx or !tok_eq(tokens[idx], "return")) return null;
    return idx + 1;
}

fn parse_cancel(tokens: []const lexer.Token, idx: usize, end_idx: usize, future_name: []const u8) ?usize {
    if (idx + 4 >= end_idx or !tok_eq(tokens[idx], "@") or !tok_eq(tokens[idx + 1], "cancel") or !tok_eq(tokens[idx + 2], "(") or tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, future_name) or !tok_eq(tokens[idx + 4], ")")) return null;
    return idx + 5;
}

fn find_matching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) ?usize {
    var depth: usize = 0;
    var idx = open_idx;
    while (idx < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], open)) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[idx], close)) continue;
        if (depth == 0) return null;
        depth -= 1;
        if (depth == 0) return idx;
    }
    return null;
}

fn string_token_body(token: lexer.Token) ?[]const u8 {
    if (token.kind != .string or token.lexeme.len < 2) return null;
    return token.lexeme[1 .. token.lexeme.len - 1];
}

fn type_tokens_equal(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected: []const u8) bool {
    var expected_idx: usize = 0;
    for (tokens[start_idx..end_idx]) |token| {
        if (expected_idx + token.lexeme.len > expected.len) return false;
        if (!std.mem.eql(u8, expected[expected_idx .. expected_idx + token.lexeme.len], token.lexeme)) return false;
        expected_idx += token.lexeme.len;
    }
    return expected_idx == expected.len;
}

fn tok_eq(token: lexer.Token, text: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, text);
}

fn token_ranges_equal(tokens: []const lexer.Token, left_start: usize, left_end: usize, right_start: usize, right_end: usize) bool {
    if (left_end < left_start or right_end < right_start or left_end - left_start != right_end - right_start) return false;
    var index: usize = 0;
    while (index < left_end - left_start) : (index += 1) {
        if (!std.mem.eql(u8, tokens[left_start + index].lexeme, tokens[right_start + index].lexeme)) return false;
    }
    return true;
}

test "ComponentAsyncFunctionPlan collects sequential registered scalar awaits" {
    const source =
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    first Future<nil> = wait_for(how_long)
        \\    await(first)
        \\    second Future<nil> = wait_until(how_long)
        \\    await(second)
        \\    third Future<nil> = wait_for(how_long)
        \\    await(third)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var plan = try ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), plan.operations.len);
    try std.testing.expectEqual(TerminalAction.await, plan.terminal);
    try std.testing.expectEqualStrings("run", plan.export_name);
    try std.testing.expectEqualStrings("monotonic-clock.wait-for", plan.operations[0].descriptor.member);
    try std.testing.expectEqualStrings("monotonic-clock.wait-until", plan.operations[1].descriptor.member);
    try std.testing.expectEqualStrings("how_long", plan.operations[0].argument_name);
    try std.testing.expectEqualStrings("how_long", plan.operations[1].argument_name);
}

test "ComponentAsyncFunctionPlan accepts ordinary declarations with canonical await" {
    const source =
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    @await(pending)
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var plan = try ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), plan.operations.len);
    try std.testing.expectEqual(TerminalAction.await, plan.terminal);
    try std.testing.expectEqualStrings("run", plan.export_name);
}

test "ComponentAsyncFunctionPlan accepts ordinary declarations with canonical cancel" {
    const source =
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    @cancel(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var plan = try ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), plan.operations.len);
    try std.testing.expectEqual(TerminalAction.cancel, plan.terminal);
}

test "ComponentAsyncFunctionPlan collects a private resource Result await" {
    const source =
        \\send = @host_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpRequest = @wasi_resource("do:resource-probe/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe/http/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async run(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var plan = try ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), plan.operations.len);
    try std.testing.expectEqual(PayloadShape.resource_result_2word, plan.operations[0].payload_shape);
    try std.testing.expectEqual(TerminalAction.return_await, plan.terminal);
    try std.testing.expect(plan.async_plan == null);
}

test "ComponentAsyncFunctionPlan collects the private owned-error resource Result await" {
    const source =
        \\send = @host_func("do:resource-probe-owned-error/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpErrorResource>)
        \\HttpRequest = @wasi_resource("do:resource-probe-owned-error/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe-owned-error/http/response", { .id i64 })
        \\HttpErrorResource = @wasi_resource("do:resource-probe-owned-error/http/error-resource", { .id i64 })
        \\async run(request HttpRequest) -> Result<HttpResponse, HttpErrorResource> {
        \\    pending Future<Result<HttpResponse, HttpErrorResource>> = send(request)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var plan = try ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), plan.operations.len);
    try std.testing.expectEqual(PayloadShape.resource_result_2word, plan.operations[0].payload_shape);
    try std.testing.expectEqual(TerminalAction.return_await, plan.terminal);
    try std.testing.expect(plan.async_plan == null);
}

test "ComponentAsyncFunctionPlan carries canonical scalar Result payload metadata" {
    const source =
        \\result_run = @host_func("do:result-probe@0.1.0", "run", (i32) -> Result<i32,i32>)
        \\async run(value i32) -> Result<i32,i32> {
        \\    pending Future<Result<i32,i32>> = result_run(value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var plan = ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry) catch |err| {
        try std.testing.expect(err != error.UnsupportedP3WaitForComponent);
        return;
    };
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), plan.operations.len);
    try std.testing.expectEqual(PayloadShape.scalar_result, plan.operations[0].payload_shape);
    try std.testing.expect(plan.operations[0].result_payload != null);
    try std.testing.expectEqualStrings("i32", plan.operations[0].result_payload.?.tag);
    try std.testing.expectEqual(@as(usize, 1), plan.operations[0].result_payload.?.ok.len);
    try std.testing.expectEqual(@as(usize, 1), plan.operations[0].result_payload.?.err.len);
    try std.testing.expectEqual(@as(usize, 0), plan.operations[0].error_variants.len);
    try std.testing.expectEqual(TerminalAction.return_await, plan.terminal);
}

test "ComponentAsyncFunctionPlan rejects a scalar return with trailing source" {
    const source =
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    await(pending)
        \\    return
        \\    another Future<nil> = wait_for(how_long)
        \\    await(another)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.UnsupportedP3WaitForComponent,
        ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry),
    );
}

test "ComponentAsyncFunctionPlan captures a post-await scalar computation" {
    const source =
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    deadline u64 = @add(input, 1)
        \\    pending Future<nil> = wait_for(deadline)
        \\    await(pending)
        \\    after u64 = @add(deadline, 1)
        \\    _ = after
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var plan = try ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), plan.operations.len);
    try std.testing.expectEqual(TerminalAction.await, plan.terminal);
    try std.testing.expect(plan.post_await != null);
    try std.testing.expectEqualStrings("deadline", plan.post_await.?.source_name);
    try std.testing.expectEqualStrings("after", plan.post_await.?.result_name);
    try std.testing.expectEqual(@as(u64, 1), plan.post_await.?.addend);
}

test "StreamU8AcquirePlan records the pinned CLI stdin acquisition sequence" {
    const source =
        \\stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
        \\StdinError error = Io | IllegalByteSequence | Pipe
        \\run() -> nil {
        \\    handles Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
        \\    reader Stream<u8> = @get(handles, 0)
        \\    completion Future<Result<nil, StdinError>> = @get(handles, 1)
        \\    pending Future<Result<u8, nil>> = @next(reader)
        \\    item Result<u8, nil> = @await(pending)
        \\    _ = item
        \\    second_pending Future<Result<u8, nil>> = @next(reader)
        \\    second_item Result<u8, nil> = @await(second_pending)
        \\    _ = second_item
        \\    eof_pending Future<Result<u8, nil>> = @next(reader)
        \\    eof Result<u8, nil> = @await(eof_pending)
        \\    _ = eof
        \\    @cancel(completion)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamU8AcquirePlan.analyze(tokens, registry);
    try std.testing.expectEqualStrings("run", plan.export_name);
    try std.testing.expectEqualStrings("reader", plan.reader_name);
    try std.testing.expectEqualStrings("completion", plan.completion_name);
    try std.testing.expectEqual(@as(usize, 3), plan.read_count);
    try std.testing.expectEqualStrings("pending", plan.reads[0].pending_name);
    try std.testing.expectEqualStrings("second_pending", plan.reads[1].pending_name);
    try std.testing.expectEqualStrings("eof_pending", plan.reads[2].pending_name);
}

test "stream reader acquisition prefix stops before consumer-owned terminal work" {
    const source =
        \\stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
        \\StdinError error = Io | IllegalByteSequence | Pipe
        \\async run() -> Result<HttpResponse, HttpError> {
        \\    source Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
        \\    reader Stream<u8> = @get(source, 0)
        \\    source_done Future<Result<nil, StdinError>> = @get(source, 1)
        \\    return Err(HttpFailure)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    var start_idx: usize = 0;
    while (start_idx < tokens.len and !std.mem.eql(u8, tokens[start_idx].lexeme, "source")) : (start_idx += 1) {}
    const prefix = try analyze_stream_u8_acquire_prefix(tokens, start_idx, tokens.len, registry);
    try std.testing.expectEqualStrings("reader", prefix.reader_name);
    try std.testing.expectEqualStrings("source_done", prefix.completion_name);
    try std.testing.expectEqualStrings("wasi:cli/stdin@0.3.0-rc-2025-09-16", prefix.descriptor.locator);
    try std.testing.expect(prefix.next_idx > start_idx);
}

test "stream reader acquisition prefix respects its end boundary" {
    const source =
        \\stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
        \\StdinError error = Io | IllegalByteSequence | Pipe
        \\async run() -> Result<HttpResponse, HttpError> {
        \\    source Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
        \\    reader Stream<u8> = @get(source, 0)
        \\    source_done Future<Result<nil, StdinError>> = @get(source, 1)
        \\    return Err(HttpFailure)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var start_idx: usize = 0;
    while (start_idx < tokens.len and !std.mem.eql(u8, tokens[start_idx].lexeme, "source")) : (start_idx += 1) {}
    var completion_start = start_idx;
    while (completion_start < tokens.len and !std.mem.eql(u8, tokens[completion_start].lexeme, "source_done")) : (completion_start += 1) {}
    try std.testing.expect(completion_start < tokens.len);
    var completion_close = completion_start;
    while (completion_close < tokens.len and !tok_eq(tokens[completion_close], ")")) : (completion_close += 1) {}
    try std.testing.expect(completion_close < tokens.len);

    try std.testing.expectError(
        error.UnsupportedP3WaitForComponent,
        analyze_stream_u8_acquire_prefix(tokens, start_idx, completion_close, registry),
    );
}

test "StreamWriterPlan carries descriptor operations and the A forwarding boundary" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io | IllegalByteSequence | Pipe
        \\async write(writer StreamWriter<u8>) -> Result<nil, StdoutError> {
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(EndpointMode.forwarded_reader, plan.endpoint_mode);
    try std.testing.expectEqual(@as(u32, 1), plan.queue_capacity);
    try std.testing.expectEqualStrings("u8", plan.stream.element);
    try std.testing.expectEqualStrings("[stream-new-0]write-via-stream", plan.stream.new.import_name);
    try std.testing.expectEqualStrings("[async-lower][stream-write-0]write-via-stream", plan.stream.write.import_name);
    try std.testing.expectEqualStrings("[stream-drop-writable-0]write-via-stream", plan.stream.drop_writable.import_name);
}

test "guest producer shape stops after an explicit writer close" {
    const source =
        \\async run() -> Result<nil, HttpError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    value u8 = 65
        \\    pending Future<Result<nil, StreamError>> = writer(value)
        \\    result Result<nil, StreamError> = await(pending)
        \\    _ = result
        \\    close(writer)
        \\    _ = reader
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const shape = analyze_guest_producer_shape(tokens) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("run", shape.function_name);
    try std.testing.expectEqualStrings("reader", shape.reader_name);
    try std.testing.expectEqualStrings("writer", shape.writer_name);
    try std.testing.expectEqualStrings("pending", shape.write_future_name);
    try std.testing.expectEqual(@as(u32, 1), shape.capacity);
    try std.testing.expectEqual(@as(usize, 1), shape.write_count);
    try std.testing.expectEqual(@as(u8, 65), shape.values[0]);
    try std.testing.expect(shape.next_idx > 0);
}

test "StreamWriterPlan identifies a guest producer endpoint" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, StdoutError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    write_pending Future<Result<nil, StreamError>> = writer(65)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(66)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(EndpointMode.guest_producer, plan.endpoint_mode);
    try std.testing.expectEqual(@as(u32, 1), plan.queue_capacity);
    try std.testing.expectEqualStrings("reader", plan.producer_reader_name.?);
    try std.testing.expectEqualStrings("writer", plan.producer_writer_name.?);
    try std.testing.expectEqualStrings("write_pending", plan.producer_write_future_name.?);
    try std.testing.expectEqualStrings("pending", plan.producer_host_future_name.?);
    try std.testing.expectEqual(@as(u8, 65), plan.producer_value.?);
    try std.testing.expectEqual(@as(usize, 2), plan.producer_write_count);
    try std.testing.expectEqual(@as(u8, 65), plan.producer_values[0]);
    try std.testing.expectEqual(@as(u8, 66), plan.producer_values[1]);
}

test "StreamWriterPlan accepts a producer lease transferred through an async helper" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async write_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async produce() -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    write_pending Future<Result<nil, StreamError>> = writer(65)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(66)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    pending Future<Result<nil, ProbeError>> = write_stream(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(EndpointMode.guest_producer, plan.endpoint_mode);
    try std.testing.expectEqual(@as(usize, 2), plan.producer_write_count);
    try std.testing.expectEqualStrings("write_stream", plan.producer_helper_name.?);
}

test "StreamWriterPlan accepts writes performed by the lease helper" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async write_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    first u8 = 65
        \\    write_pending Future<Result<nil, StreamError>> = writer(first)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    second u8 = 66
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async produce() -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = write_stream(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(EndpointMode.guest_producer, plan.endpoint_mode);
    try std.testing.expectEqualStrings("write_stream", plan.producer_helper_name.?);
    try std.testing.expectEqual(@as(usize, 2), plan.producer_write_count);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 65, 66 }, plan.producer_values[0..2]);
}

test "StreamWriterPlan accepts a two-hop producer lease transfer" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    first u8 = 65
        \\    write_pending Future<Result<nil, StreamError>> = writer(first)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    second u8 = 66
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer)
        \\    return await(pending)
        \\}
        \\async produce() -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(EndpointMode.guest_producer, plan.endpoint_mode);
    try std.testing.expectEqualStrings("forward_stream", plan.producer_helper_name.?);
    try std.testing.expectEqual(@as(usize, 2), plan.producer_write_count);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 65, 66 }, plan.producer_values[0..2]);
}

test "StreamWriterPlan rejects a third producer lease forwarding hop" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    first u8 = 65
        \\    write_pending Future<Result<nil, StreamError>> = writer(first)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async forward_b(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer)
        \\    return await(pending)
        \\}
        \\async forward_a(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = forward_b(writer)
        \\    return await(pending)
        \\}
        \\async produce() -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_a(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3StreamWriterComponent, StreamWriterPlan.analyze(tokens, registry));
}

test "StreamWriterPlan accepts a parameterized producer lease helper" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        write_pending Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(write_pending)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("finish_stream", plan.producer_helper_name.?);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
}

test "StreamWriterPlan accepts reordered parameterized producer helper" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(count u64, writer StreamWriter<u8>, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        write_pending Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(write_pending)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(count, writer, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("finish_stream", plan.producer_helper_name.?);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
}

test "StreamWriterPlan rejects literal parameterized producer helper arguments" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, 7, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3StreamWriterComponent, StreamWriterPlan.analyze(tokens, registry));
}

test "StreamWriterPlan accepts a parameterized producer forwarding helper" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        write_pending Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(write_pending)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("forward_stream", plan.producer_helper_name.?);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
}

test "StreamWriterPlan accepts reordered parameterized forwarding helper arguments" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(value u8, writer StreamWriter<u8>, count u64) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        write_pending Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(write_pending)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(value, writer, count)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("forward_stream", plan.producer_helper_name.?);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
}

test "StreamWriterPlan accepts a parameterized producer with two forwarding hops" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        write_pending Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(write_pending)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("forward_stream", plan.producer_helper_name.?);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
}

test "StreamWriterPlan accepts a third parameterized producer forwarding hop" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        pending_write Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(pending_write)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async entry_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = entry_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("entry_stream", plan.producer_helper_name.?);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
}

test "StreamWriterPlan accepts a fourth parameterized producer forwarding hop" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        pending_write Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(pending_write)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async entry_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async outer_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = entry_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = outer_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("outer_stream", plan.producer_helper_name.?);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
}

test "StreamWriterPlan accepts a fifth parameterized producer forwarding hop" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        pending_write Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(pending_write)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async inner_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = inner_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async entry_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async outer_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = entry_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = outer_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("outer_stream", plan.producer_helper_name.?);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
}

test "StreamWriterPlan rejects a sixth parameterized producer forwarding hop" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        pending_write Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(pending_write)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = inner_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async inner_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async entry_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async outer_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = entry_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async super_outer_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = outer_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = super_outer_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3StreamWriterComponent, StreamWriterPlan.analyze(tokens, registry));
}

test "StreamWriterPlan rejects reordered parameterized producer forwarding arguments" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, value, count)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3StreamWriterComponent, StreamWriterPlan.analyze(tokens, registry));
}

test "StreamWriterPlan accepts a dynamic countdown producer" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce(count u64) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending Future<Result<nil, StreamError>> = writer(65)
        \\        result Result<nil, StreamError> = await(pending)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(EndpointMode.guest_producer, plan.endpoint_mode);
    try std.testing.expectEqualStrings("produce", plan.export_name);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqual(@as(u8, 65), plan.producer_value.?);
    try std.testing.expectEqual(@as(usize, 0), plan.producer_write_count);
}

test "StreamWriterPlan accepts a parameterized dynamic countdown producer" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending Future<Result<nil, StreamError>> = writer(value)
        \\        result Result<nil, StreamError> = await(pending)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(EndpointMode.guest_producer, plan.endpoint_mode);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("count", plan.producer_count_name.?);
    try std.testing.expectEqualStrings("value", plan.producer_value_name.?);
}

test "StreamWriterPlan accepts one helper transfer with branch terminal" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        write_pending Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(write_pending)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    if @eq(value, 90) {
        \\        close(writer)
        \\    } else {
        \\        abort(writer, 2)
        \\    }
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(EndpointMode.guest_producer, plan.endpoint_mode);
    try std.testing.expectEqual(ProducerMode.countdown, plan.producer_mode);
    try std.testing.expectEqualStrings("finish_stream", plan.producer_helper_name.?);
}

test "StreamWriterPlan rejects a parameterized producer that ignores its value parameter" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending Future<Result<nil, StreamError>> = writer(65)
        \\        result Result<nil, StreamError> = await(pending)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3StreamWriterComponent, StreamWriterPlan.analyze(tokens, registry));
}

test "StreamWriterPlan rejects a dynamic producer without a zero pre-guard" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce(count u64) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    remaining u64 = count
        \\    loop {
        \\        pending Future<Result<nil, StreamError>> = writer(65)
        \\        result Result<nil, StreamError> = await(pending)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3StreamWriterComponent, StreamWriterPlan.analyze(tokens, registry));
}

test "StreamWriterPlan accepts a bound u8 value in a guest producer write" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, StdoutError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    first u8 = 65
        \\    write_pending Future<Result<nil, StreamError>> = writer(first)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(EndpointMode.guest_producer, plan.endpoint_mode);
    try std.testing.expectEqual(@as(usize, 1), plan.producer_write_count);
    try std.testing.expectEqual(@as(u8, 65), plan.producer_values[0]);
}

test "StreamWriterPlan preserves a three-value source sequence" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, StdoutError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    first u8 = 65
        \\    write_pending Future<Result<nil, StreamError>> = writer(first)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    second u8 = 66
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    third u8 = 67
        \\    write_pending_3 Future<Result<nil, StreamError>> = writer(third)
        \\    write_result_3 Result<nil, StreamError> = await(write_pending_3)
        \\    _ = write_result_3
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamWriterPlan.analyze(tokens, registry);
    try std.testing.expectEqual(@as(usize, 3), plan.producer_write_count);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 65, 66, 67 }, plan.producer_values[0..3]);
}

test "StreamWriterPlan rejects a source sequence beyond the bounded limit" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, StdoutError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    first u8 = 65
        \\    write_pending_1 Future<Result<nil, StreamError>> = writer(first)
        \\    write_result_1 Result<nil, StreamError> = await(write_pending_1)
        \\    _ = write_result_1
        \\    second u8 = 66
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    third u8 = 67
        \\    write_pending_3 Future<Result<nil, StreamError>> = writer(third)
        \\    write_result_3 Result<nil, StreamError> = await(write_pending_3)
        \\    _ = write_result_3
        \\    fourth u8 = 68
        \\    write_pending_4 Future<Result<nil, StreamError>> = writer(fourth)
        \\    write_result_4 Result<nil, StreamError> = await(write_pending_4)
        \\    _ = write_result_4
        \\    fifth u8 = 69
        \\    write_pending_5 Future<Result<nil, StreamError>> = writer(fifth)
        \\    write_result_5 Result<nil, StreamError> = await(write_pending_5)
        \\    _ = write_result_5
        \\    sixth u8 = 70
        \\    write_pending_6 Future<Result<nil, StreamError>> = writer(sixth)
        \\    write_result_6 Result<nil, StreamError> = await(write_pending_6)
        \\    _ = write_result_6
        \\    seventh u8 = 71
        \\    write_pending_7 Future<Result<nil, StreamError>> = writer(seventh)
        \\    write_result_7 Result<nil, StreamError> = await(write_pending_7)
        \\    _ = write_result_7
        \\    eighth u8 = 72
        \\    write_pending_8 Future<Result<nil, StreamError>> = writer(eighth)
        \\    write_result_8 Result<nil, StreamError> = await(write_pending_8)
        \\    _ = write_result_8
        \\    ninth u8 = 73
        \\    write_pending_9 Future<Result<nil, StreamError>> = writer(ninth)
        \\    write_result_9 Result<nil, StreamError> = await(write_pending_9)
        \\    _ = write_result_9
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3StreamWriterComponent, StreamWriterPlan.analyze(tokens, registry));
}

test "StreamMirrorPlan accepts the bounded source to writer loop" {
    const source =
        \\probe_read = @host("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\produce() -> Result<nil, ProbeError> {
        \\    source Tuple<Stream<u8>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    input Stream<u8> = @get(source, 0)
        \\    source_done Future<Result<nil, ProbeError>> = @get(source, 1)
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    defer close(writer)
        \\    remaining u64 = 3
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        read_pending Future<Result<u8, nil>> = @next(input)
        \\        item Result<u8, nil> = @await(read_pending)
        \\        if @is(item, Ok) {
        \\            value u8 = item
        \\            write_pending Future<Result<nil, StreamError>> = writer(value)
        \\            write_result Result<nil, StreamError> = @await(write_pending)
        \\            _ = write_result
        \\            remaining = @sub(remaining, 1)
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    @cancel(source_done)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return @await(pending)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try StreamMirrorPlan.analyze(tokens, registry);
    try std.testing.expectEqual(@as(usize, 3), plan.max_reads);
    try std.testing.expectEqual(@as(u32, 1), plan.capacity);
    try std.testing.expectEqualStrings("input", plan.source_reader_name);
    try std.testing.expectEqualStrings("source_done", plan.source_completion_name);
    try std.testing.expectEqualStrings("sink_write", plan.sink_host_name);
}

test "StreamMirrorPlan rejects a dynamic mirror bound" {
    const source =
        \\probe_read = @host("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce(limit u64) -> Result<nil, ProbeError> {
        \\    source Tuple<Stream<u8>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    input Stream<u8> = @get(source, 0)
        \\    source_done Future<Result<nil, ProbeError>> = @get(source, 1)
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    defer close(writer)
        \\    remaining u64 = limit
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        read_pending Future<Result<u8, nil>> = @next(input)
        \\        item Result<u8, nil> = await(read_pending)
        \\        if @is(item, Ok) {
        \\            value u8 = item
        \\            write_pending Future<Result<nil, StreamError>> = writer(value)
        \\            write_result Result<nil, StreamError> = await(write_pending)
        \\            _ = write_result
        \\            remaining = @sub(remaining, 1)
        \\        } else { break }
        \\    }
        \\    @cancel(source_done)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3StreamMirrorComponent, StreamMirrorPlan.analyze(tokens, registry));
}
