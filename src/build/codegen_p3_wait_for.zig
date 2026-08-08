const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const async_model = @import("codegen_async_model.zig");
const codegen_emit_async = @import("codegen_emit_async.zig");
const gc_async_frame = @import("codegen_gc_async_frame.zig");
const async_byte_budget = @import("async_byte_budget.zig");
const component_async_plan = @import("codegen_component_async_plan.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    if (analyze_cli_result_program(tokens, registry)) |plan| return emit_cli_result_core_wat(allocator, plan);
    var shared = component_async_plan.ComponentAsyncFunctionPlan.analyze(allocator, tokens, registry) catch return error.UnsupportedP3WaitForComponent;
    defer shared.deinit(allocator);
    if (shared.operations.len == 1 and shared.operations[0].payload_shape == .scalar_result) {
        return emit_scalar_result_core_wat(allocator, &shared);
    }
    var wat = switch (shared.control) {
        .linear => blk: {
            if (shared.operations.len > 2) break :blk try emit_sequential_component_core_wat(allocator, &shared);
            const plan = try clock_template_plan_from_shared(&shared);
            const async_plan = shared.async_plan orelse return error.UnsupportedP3WaitForComponent;
            break :blk try emit_component_core_wat(allocator, plan, &async_plan);
        },
        .if_eq_parameter_literal => try emit_if_eq_component_core_wat(allocator, &shared),
        .loop_countdown => try emit_loop_countdown_component_core_wat(allocator, &shared),
    };
    if (shared.async_plan) |*async_plan| {
        wat = try append_async_plan_metadata(allocator, wat, async_plan);
    }
    return wat;
}

fn append_async_plan_metadata(
    allocator: std.mem.Allocator,
    wat: []u8,
    plan: *const async_model.AsyncFunctionPlan,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    errdefer allocator.free(wat);

    try out.appendSlice(allocator, wat);
    try out.appendSlice(allocator, "\n");
    try codegen_emit_async.emit_frame_metadata(allocator, &out, plan.*);
    const result = try out.toOwnedSlice(allocator);
    allocator.free(wat);
    return result;
}

pub fn emit_component_wit() []const u8 {
    return component_wit;
}

pub fn emit_component_wit_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    if (analyze_cli_result_program(tokens, registry)) |plan| return emit_cli_result_wit_for_plan(allocator, plan);
    var shared = try component_async_plan.ComponentAsyncFunctionPlan.analyze(allocator, tokens, registry);
    defer shared.deinit(allocator);
    if (shared.operations.len == 1 and shared.operations[0].payload_shape == .scalar_result) {
        return emit_scalar_result_wit_for_plan(allocator, &shared);
    }
    if (shared.operations.len > 2) return emit_component_wit_for_shared_plan(allocator, &shared);
    const plan = try clock_template_plan_from_shared(&shared);
    return emit_component_wit_for_plan(allocator, plan);
}

const CliResultPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    export_name: []const u8,
    completion_behavior: CliResultCompletionBehavior,
};

const CliResultCompletionBehavior = enum {
    passthrough,
    invert_ok,
};

fn analyze_cli_result_program(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?CliResultPlan {
    const host = parse_cli_result_host_binding(tokens) orelse return null;
    const descriptor = registry.find(host.locator, host.member) orelse return null;
    if (descriptor.params.len != 0 or !std.mem.eql(u8, descriptor.result, "Result<nil,nil>") or
        descriptor.wit_sha256 == null or !std.mem.eql(u8, descriptor.wit_sha256.?, "04b2de3bf344052c78080f3c5320442132b4e7c20b42633a92b8400b6d29ab0d") or
        descriptor.canonical.core_params.len != 1 or !std.mem.eql(u8, descriptor.canonical.core_params[0], "i32") or
        descriptor.canonical.core_results.len != 1 or !std.mem.eql(u8, descriptor.canonical.core_results[0], "i32")) return null;
    const function = parse_cli_result_async_function(tokens, host.end_idx + 1) orelse return null;
    const completion_behavior = parse_cli_result_body(tokens, function, host.name) orelse return null;
    return .{
        .descriptor = descriptor,
        .export_name = function.name,
        .completion_behavior = completion_behavior,
    };
}

const CliResultHostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
    end_idx: usize,
};

fn parse_cli_result_host_binding(tokens: []const lexer.Token) ?CliResultHostBinding {
    var idx: usize = 0;
    while (idx + 19 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host_async_func") or !tok_eq(tokens[idx + 4], "(")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        if (!tok_eq(tokens[idx + 6], ",")) continue;
        const member = string_token_body(tokens[idx + 7]) orelse continue;
        if (!tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or !tok_eq(tokens[idx + 10], ")") or !tok_eq(tokens[idx + 11], "-") or !tok_eq(tokens[idx + 12], ">")) continue;
        if (!result_unit_tokens(tokens, idx + 13) or !tok_eq(tokens[idx + 19], ")")) continue;
        return .{ .name = tokens[idx].lexeme, .locator = locator, .member = member, .end_idx = idx + 19 };
    }
    return null;
}

const CliResultAsyncFunction = struct {
    name: []const u8,
    body_start: usize,
    body_end: usize,
};

fn parse_cli_result_async_function(tokens: []const lexer.Token, start_idx: usize) ?CliResultAsyncFunction {
    var idx = start_idx;
    while (idx + 8 < tokens.len) : (idx += 1) {
        const name_idx = if (tok_eq(tokens[idx], "async")) idx + 1 else idx;
        const open_params = if (tok_eq(tokens[idx], "async")) idx + 2 else idx + 1;
        if (name_idx >= tokens.len or open_params >= tokens.len or tokens[name_idx].kind != .ident or
            !tok_eq(tokens[open_params], "(")) continue;
        const close_params = find_matching(tokens, open_params, "(", ")") orelse continue;
        if (close_params != open_params + 1 or !tok_eq(tokens[close_params + 1], "-") or
            !tok_eq(tokens[close_params + 2], ">")) continue;
        if (close_params + 9 >= tokens.len or !result_unit_tokens(tokens, close_params + 3) or
            !tok_eq(tokens[close_params + 9], "{")) continue;
        const body_end = find_matching(tokens, close_params + 9, "{", "}") orelse continue;
        return .{ .name = tokens[name_idx].lexeme, .body_start = close_params + 10, .body_end = body_end };
    }
    return null;
}

fn parse_cli_result_body(tokens: []const lexer.Token, function: CliResultAsyncFunction, host_name: []const u8) ?CliResultCompletionBehavior {
    const idx = function.body_start;
    if (idx + 13 >= function.body_end or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<") or !result_unit_tokens(tokens, idx + 3) or !tok_eq(tokens[idx + 9], ">") or !tok_eq(tokens[idx + 10], "=")) return null;
    if (!std.mem.eql(u8, tokens[idx + 11].lexeme, host_name) or !tok_eq(tokens[idx + 12], "(") or !tok_eq(tokens[idx + 13], ")")) return null;

    const await_start = idx + 14;
    if (await_start + 4 < function.body_end and tok_eq(tokens[await_start], "return")) {
        const op_idx = if (tok_eq(tokens[await_start + 1], "@") and tok_eq(tokens[await_start + 2], "await")) await_start + 2 else await_start + 1;
        const operand_idx = op_idx + 2;
        if (op_idx + 3 < function.body_end and tok_eq(tokens[op_idx], "await") and tok_eq(tokens[op_idx + 1], "(") and
            tokens[operand_idx].kind == .ident and std.mem.eql(u8, tokens[operand_idx].lexeme, tokens[idx].lexeme) and
            tok_eq(tokens[op_idx + 3], ")") and op_idx + 4 == function.body_end) return .passthrough;
    }

    if (await_start + 11 >= function.body_end or tokens[await_start].kind != .ident or !result_unit_tokens(tokens, await_start + 1) or !tok_eq(tokens[await_start + 7], "=")) return null;
    const op_idx = if (tok_eq(tokens[await_start + 8], "@") and tok_eq(tokens[await_start + 9], "await")) await_start + 9 else await_start + 8;
    if (op_idx + 3 >= function.body_end or !tok_eq(tokens[op_idx], "await") or !tok_eq(tokens[op_idx + 1], "(") or
        tokens[op_idx + 2].kind != .ident or !std.mem.eql(u8, tokens[op_idx + 2].lexeme, tokens[idx].lexeme) or
        !tok_eq(tokens[op_idx + 3], ")")) return null;
    const result_name = tokens[await_start].lexeme;
    const if_start = op_idx + 4;
    if (if_start + 8 >= function.body_end or !tok_eq(tokens[if_start], "if") or !tok_eq(tokens[if_start + 1], "@") or !tok_eq(tokens[if_start + 2], "is") or !tok_eq(tokens[if_start + 3], "(") or tokens[if_start + 4].kind != .ident or !std.mem.eql(u8, tokens[if_start + 4].lexeme, result_name) or !tok_eq(tokens[if_start + 5], ",") or !tok_eq(tokens[if_start + 6], "Ok") or !tok_eq(tokens[if_start + 7], ")") or !tok_eq(tokens[if_start + 8], "{")) return null;
    const branch_end = find_matching(tokens, if_start + 8, "{", "}") orelse return null;
    if (branch_end != if_start + 13 or !tok_eq(tokens[if_start + 9], "return") or !unit_result_constructor(tokens, if_start + 10, "Err")) return null;
    const final_return = branch_end + 1;
    if (final_return + 4 != function.body_end or !tok_eq(tokens[final_return], "return") or !unit_result_constructor(tokens, final_return + 1, "Ok")) return null;
    return .invert_ok;
}

fn unit_result_constructor(tokens: []const lexer.Token, idx: usize, name: []const u8) bool {
    return idx + 2 < tokens.len and tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "(") and tok_eq(tokens[idx + 2], ")");
}

fn result_unit_tokens(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 5 < tokens.len and tok_eq(tokens[idx], "Result") and tok_eq(tokens[idx + 1], "<") and tok_eq(tokens[idx + 2], "nil") and tok_eq(tokens[idx + 3], ",") and tok_eq(tokens[idx + 4], "nil") and tok_eq(tokens[idx + 5], ">");
}

test "component lowering uses the shared Component async plan" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    first Future<nil> = wait_for(how_long)
        \\    await(first)
        \\    second Future<nil> = wait_until(how_long)
        \\    await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    var shared = try component_async_plan.ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer shared.deinit(std.testing.allocator);

    const plan = try clock_template_plan_from_shared(&shared);
    try std.testing.expectEqual(ClockTemplateBody.two_await, plan.body);
    try std.testing.expectEqualStrings("monotonic-clock.wait-for", plan.descriptor.member);
    try std.testing.expectEqualStrings("monotonic-clock.wait-until", plan.second_descriptor.?.member);
    try std.testing.expectEqual(@as(usize, 2), shared.async_plan.?.frame.resume_states.len);
}

test "single async wait checks for immediate host completion before joining" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 2\n    i32.eq\n    if (result i32)") != null);
}

test "single async wait lowers a post-await scalar computation" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
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
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-slot] deadline") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $async-frame $state") != null);
    try std.testing.expect(std.mem.count(u8, wat, "struct.get $async-frame $slot-deadline") >= 2);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $async-frame $slot-deadline\n        i64.const 1\n        i64.add") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "call $first-host-call"));
}

const ClockTemplatePlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    second_descriptor: ?p3_async_manifest.Descriptor = null,
    export_name: []const u8,
    parameter_name: []const u8,
    first_argument_name: []const u8,
    second_argument_name: []const u8 = "",
    parameter_storage: async_model.FrameSlotStorage,
    first_argument: component_async_plan.ScalarArgument = .parameter,
    second_argument: component_async_plan.ScalarArgument = .parameter,
    post_await: ?component_async_plan.PostAwaitComputation = null,
    body: ClockTemplateBody,
};

const ClockTemplateBody = enum {
    await,
    cancel,
    two_await,
};

fn clock_template_plan_from_shared(shared: *const component_async_plan.ComponentAsyncFunctionPlan) !ClockTemplatePlan {
    if (shared.operations.len == 1) return .{
        .descriptor = shared.operations[0].descriptor,
        .export_name = shared.export_name,
        .parameter_name = shared.parameter.name,
        .first_argument_name = shared.operations[0].argument_name,
        .second_argument_name = if (shared.operations.len > 1) shared.operations[1].argument_name else "",
        .parameter_storage = shared.parameter.storage,
        .first_argument = shared.operations[0].argument,
        .post_await = shared.post_await,
        .body = switch (shared.terminal) {
            .await => .await,
            .cancel => .cancel,
            .return_await => return error.UnsupportedP3WaitForComponent,
        },
    };
    if (shared.operations.len != 2 or shared.terminal != .await) return error.UnsupportedP3WaitForComponent;
    return .{
        .descriptor = shared.operations[0].descriptor,
        .second_descriptor = shared.operations[1].descriptor,
        .export_name = shared.export_name,
        .parameter_name = shared.parameter.name,
        .first_argument_name = shared.operations[0].argument_name,
        .second_argument_name = shared.operations[1].argument_name,
        .parameter_storage = shared.parameter.storage,
        .first_argument = shared.operations[0].argument,
        .second_argument = shared.operations[1].argument,
        .body = .two_await,
    };
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

fn tok_eq(token: lexer.Token, text: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, text);
}

fn string_token_body(token: lexer.Token) ?[]const u8 {
    if (token.kind != .string or token.lexeme.len < 2) return null;
    return token.lexeme[1 .. token.lexeme.len - 1];
}

fn emit_component_core_wat(
    allocator: std.mem.Allocator,
    plan: ClockTemplatePlan,
    async_plan: *const async_model.AsyncFunctionPlan,
) ![]u8 {
    if (plan.body == .two_await) return emit_two_await_core_wat(allocator, plan, async_plan);
    if (plan.body != .cancel and (async_plan.frame.resume_states.len != 1 or async_plan.frame.cleanup_state != 2 or
        async_plan.layout.waitable_set_offset != 4)) return error.UnsupportedP3WaitForComponent;
    if (plan.body == .await and plan.parameter_storage == .i64) {
        if (plan.post_await) |post_await| {
            return emit_post_compute_frame_core_wat(allocator, plan, async_plan, post_await);
        }
        return emit_single_frame_core_wat(allocator, plan, async_plan);
    }
    if (plan.body == .cancel and plan.parameter_storage == .i64) {
        return emit_cancel_frame_core_wat(allocator, plan, async_plan);
    }
    const core_param = async_model.frame_slot_storage_core_wasm_type(plan.parameter_storage) orelse return error.UnsupportedP3WaitForComponent;

    const async_lower_type = try std.fmt.allocPrint(
        allocator,
        "(type $async-lower-wait-for (func (param {s}) (result i32))",
        .{core_param},
    );
    defer allocator.free(async_lower_type);
    const async_run_type = try std.fmt.allocPrint(
        allocator,
        "(type $async-run (func (param {s}) (result i32))",
        .{core_param},
    );
    defer allocator.free(async_run_type);
    const async_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ plan.descriptor.canonical.async_import_module, plan.descriptor.canonical.async_import_name },
    );
    defer allocator.free(async_import);
    const task_return_export = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{plan.export_name});
    defer allocator.free(task_return_export);
    const async_lift_export = try std.fmt.allocPrint(allocator, "[async-lift]{s}", .{plan.export_name});
    defer allocator.free(async_lift_export);
    const async_callback_export = try std.fmt.allocPrint(allocator, "[callback][async-lift]{s}", .{plan.export_name});
    defer allocator.free(async_callback_export);

    var wat = try allocator.dupe(u8, core_wat);
    if (plan.body == .cancel) {
        wat = try replace_between(
            allocator,
            wat,
            "  (func (export \"[async-lift]run\")",
            "  (func (export \"cabi_realloc\")",
            cancel_async_body,
        );
    }
    wat = try replace_and_free(allocator, wat, "(type $async-lower-wait-for (func (param i64) (result i32))", async_lower_type);
    wat = try replace_and_free(allocator, wat, "(type $async-run (func (param i64) (result i32))", async_run_type);
    wat = try replace_and_free(allocator, wat, "(import \"wasi:clocks/monotonic-clock@0.3.0\" \"[async-lower]wait-for\"", async_import);
    wat = try replace_and_free(allocator, wat, "$wait-for", "$async-host-call");
    wat = try replace_and_free(allocator, wat, "[task-return]run", task_return_export);
    wat = try replace_and_free(allocator, wat, "[async-lift]run", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]run", async_callback_export);
    return wat;
}

fn emit_cancel_frame_core_wat(
    allocator: std.mem.Allocator,
    plan: ClockTemplatePlan,
    async_plan: *const async_model.AsyncFunctionPlan,
) ![]u8 {
    var framed_plan = plan;
    framed_plan.second_descriptor = plan.descriptor;
    framed_plan.second_argument_name = plan.first_argument_name;
    framed_plan.second_argument = plan.first_argument;
    framed_plan.body = .two_await;
    var wat = try emit_two_await_core_wat(allocator, framed_plan, null);
    const second_import = try std.fmt.allocPrint(allocator, "  (import \"{s}\" \"{s}\" (func $second-host-call (type $async-lower)))\n", .{ plan.descriptor.canonical.async_import_module, plan.descriptor.canonical.async_import_name });
    defer allocator.free(second_import);
    wat = try replace_and_free(allocator, wat, second_import, "");
    wat = try replace_and_free(allocator, wat, "$second-host-call", "$first-host-call");
    wat = try replace_and_free(allocator, wat, "  (import \"$root\" \"[context-set-0]\" (func $context-set-0 (param i32)))\n", "  (import \"$root\" \"[context-set-0]\" (func $context-set-0 (param i32)))\n  (import \"$root\" \"[subtask-drop]\" (func $subtask-drop (param i32)))\n  (import \"$root\" \"[subtask-cancel]\" (func $subtask-cancel (param i32) (result i32)))\n");
    var cleanup = std.ArrayList(u8).empty;
    defer cleanup.deinit(allocator);
    try codegen_emit_async.emit_async_terminal_cleanup(allocator, &cleanup, async_plan.frame, .cancelled);
    const body = try std.fmt.allocPrint(
        allocator,
        "  (func (export \"[async-lift]run\") (type $async-run) (local $frame i32) (local $subtask i32)\n    i32.const 1\n    call $waitable-set-new\n    i32.const 0\n    i32.const 0\n    local.get 0\n    struct.new $async-frame\n    call $frame-alloc\n    local.tee $frame\n    call $context-set-0\n    local.get 0\n    call $first-host-call\n    local.set $subtask\n    local.get $subtask\n    i32.const 2\n    i32.eq\n    if (result i32)\n      i32.const 0\n      call $context-set-0\n{s}      call $task-return\n      i32.const 0\n    else\n      local.get $subtask\n      i32.const 4\n      i32.shr_u\n      call $subtask-cancel\n      i32.const 4\n      i32.ne\n      if unreachable end\n      local.get $subtask\n      i32.const 4\n      i32.shr_u\n      call $subtask-drop\n      i32.const 0\n      call $context-set-0\n{s}      call $task-return\n      i32.const 0\n    end\n  )\n\n",
        .{ cleanup.items, cleanup.items },
    );
    defer allocator.free(body);
    return replace_between(allocator, wat, "  (func (export \"[async-lift]run\")", "  (func (export \"[callback][async-lift]run\")", body);
}

fn emit_single_frame_core_wat(
    allocator: std.mem.Allocator,
    plan: ClockTemplatePlan,
    async_plan: *const async_model.AsyncFunctionPlan,
) ![]u8 {
    var framed_plan = plan;
    framed_plan.second_descriptor = plan.descriptor;
    framed_plan.second_argument_name = plan.first_argument_name;
    framed_plan.second_argument = plan.first_argument;
    framed_plan.body = .two_await;
    var wat = try emit_two_await_core_wat(allocator, framed_plan, async_plan);
    const second_import = try std.fmt.allocPrint(
        allocator,
        "  (import \"{s}\" \"{s}\" (func $second-host-call (type $async-lower)))\n",
        .{ plan.descriptor.canonical.async_import_module, plan.descriptor.canonical.async_import_name },
    );
    defer allocator.free(second_import);
    wat = try replace_and_free(
        allocator,
        wat,
        second_import,
        "",
    );
    wat = try replace_and_free(allocator, wat, "$second-host-call", "$first-host-call");
    wat = try replace_and_free(
        allocator,
        wat,
        "    i32.const 1\n    call $waitable-set-new",
        "    i32.const 2\n    call $waitable-set-new",
    );
    var cleanup = std.ArrayList(u8).empty;
    defer cleanup.deinit(allocator);
    try codegen_emit_async.emit_async_terminal_cleanup(allocator, &cleanup, async_plan.frame, .returned);
    const terminal = try std.fmt.allocPrint(
        allocator,
        "        i32.const 0\n        call $context-set-0\n{s}        call $task-return\n        i32.const 0",
        .{cleanup.items},
    );
    defer allocator.free(terminal);
    wat = try replace_and_free(
        allocator,
        wat,
        "        i32.const 0\n        call $context-set-0\n        local.get $frame\n        call $frame-free\n        call $task-return\n        i32.const 0",
        terminal,
    );
    wat = try replace_and_free(
        allocator,
        wat,
        "    local.get $subtask\n    i32.const 4\n    i32.shr_u\n    local.get $frame\n",
        "    local.get $subtask\n    i32.const 2\n    i32.eq\n    if (result i32)\n      i32.const 0\n      call $context-set-0\n      local.get $frame\n      call $frame-free\n      call $task-return\n      i32.const 0\n    else\n    local.get $subtask\n    i32.const 4\n    i32.shr_u\n    local.get $frame\n",
    );
    wat = try replace_and_free(
        allocator,
        wat,
        "    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame $waitable-set\n    call $waitable-join\n    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame $waitable-set\n    i32.const 4\n    i32.shl\n    i32.const 2\n    i32.or\n  )",
        "    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame $waitable-set\n    call $waitable-join\n    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame $waitable-set\n    i32.const 4\n    i32.shl\n    i32.const 2\n    i32.or\n    end\n  )",
    );
    return wat;
}

fn emit_post_compute_frame_core_wat(
    allocator: std.mem.Allocator,
    plan: ClockTemplatePlan,
    async_plan: *const async_model.AsyncFunctionPlan,
    post_await: component_async_plan.PostAwaitComputation,
) ![]u8 {
    if (plan.parameter_storage != .i64 or async_plan.frame.resume_states.len != 1) return error.UnsupportedP3WaitForComponent;
    var has_source_slot = false;
    for (async_plan.layout.slots) |slot| {
        if (slot.storage == .i64 and std.mem.eql(u8, slot.name, post_await.source_name)) {
            has_source_slot = true;
            break;
        }
    }
    if (!has_source_slot) return error.UnsupportedP3WaitForComponent;

    var base_plan = plan;
    base_plan.post_await = null;
    var wat = try emit_single_frame_core_wat(allocator, base_plan, async_plan);

    var cleanup = std.ArrayList(u8).empty;
    defer cleanup.deinit(allocator);
    try codegen_emit_async.emit_async_terminal_cleanup(allocator, &cleanup, async_plan.frame, .returned);
    const terminal = try std.fmt.allocPrint(
        allocator,
        "        local.get $frame-ref\n        i32.const 2\n        struct.set $async-frame $state\n        local.get $frame-ref\n        struct.get $async-frame $slot-{s}\n        i64.const {d}\n        i64.add\n        drop\n        i32.const 0\n        call $context-set-0\n{s}        call $task-return\n        i32.const 0\n",
        .{ post_await.source_name, post_await.addend, cleanup.items },
    );
    defer allocator.free(terminal);
    wat = try replace_between(
        allocator,
        wat,
        "        local.get $frame-ref\n        i32.const 2\n        struct.set $async-frame $state\n",
        "      else\n",
        terminal,
    );
    const immediate_terminal = try std.fmt.allocPrint(
        allocator,
        "      i32.const 0\n      call $context-set-0\n      local.get $frame\n      table.get $async-frames\n      ref.as_non_null\n      struct.get $async-frame $slot-{s}\n      i64.const {d}\n      i64.add\n      drop\n{s}      call $task-return\n      i32.const 0",
        .{ post_await.source_name, post_await.addend, cleanup.items },
    );
    defer allocator.free(immediate_terminal);
    wat = try replace_and_free(
        allocator,
        wat,
        "      i32.const 0\n      call $context-set-0\n      local.get $frame\n      call $frame-free\n      call $task-return\n      i32.const 0",
        immediate_terminal,
    );
    if (std.mem.count(u8, wat, "call $first-host-call") != 1) return error.UnsupportedP3WaitForComponent;
    return wat;
}

fn emit_two_await_core_wat(
    allocator: std.mem.Allocator,
    plan: ClockTemplatePlan,
    async_plan: ?*const async_model.AsyncFunctionPlan,
) ![]u8 {
    const second = plan.second_descriptor orelse return error.UnsupportedP3WaitForComponent;
    if (plan.parameter_storage != .i64) return error.UnsupportedP3WaitForComponent;

    var synthetic_frame: ?async_model.FrameModel = null;
    var synthetic_layout: ?async_model.FrameLayout = null;
    defer {
        if (synthetic_layout) |*layout| layout.deinit(allocator);
        if (synthetic_frame) |*frame| frame.deinit(allocator);
    }
    const layout = if (async_plan) |actual| actual.layout else blk: {
        const live_slots = [_]async_model.FrameSlot{.{ .name = plan.parameter_name, .storage = plan.parameter_storage }};
        const await_sites = [_]async_model.AwaitSite{
            .{ .token_index = 0, .live_slots = &live_slots },
            .{ .token_index = 1, .live_slots = &.{} },
        };
        const frame = try async_model.FrameModel.collect(allocator, &await_sites);
        synthetic_frame = frame;
        const generated = try async_model.FrameLayout.collect(allocator, frame);
        synthetic_layout = generated;
        break :blk generated;
    };
    if (layout.slots.len == 0 or
        !std.mem.eql(u8, layout.slots[0].name, plan.parameter_name) or
        layout.slots[0].storage != .i64)
        return error.UnsupportedP3WaitForComponent;
    const parameter_field = try std.fmt.allocPrint(allocator, "$slot-{s}", .{layout.slots[0].name});
    defer allocator.free(parameter_field);
    const frame_slot_initializers = try emit_frame_slot_initializers(allocator, layout, plan.first_argument_name, plan.first_argument);
    defer allocator.free(frame_slot_initializers);
    const first_argument = try alloc_initial_argument_wat(allocator, plan.first_argument);
    defer allocator.free(first_argument);
    const second_argument = try alloc_resumed_argument_wat(
        allocator,
        plan.second_argument,
        plan.second_argument_name,
        async_plan,
        parameter_field,
    );
    defer allocator.free(second_argument);

    var gc_frame_runtime = std.ArrayList(u8).empty;
    defer gc_frame_runtime.deinit(allocator);
    try gc_async_frame.emit_frame_table_layout(allocator, &gc_frame_runtime, layout);
    try gc_async_frame.emit_frame_table_allocator_with_bytes(allocator, &gc_frame_runtime, layout.size);

    const first_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ plan.descriptor.canonical.async_import_module, plan.descriptor.canonical.async_import_name },
    );
    defer allocator.free(first_import);
    const second_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ second.canonical.async_import_module, second.canonical.async_import_name },
    );
    defer allocator.free(second_import);
    const task_return_export = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{plan.export_name});
    defer allocator.free(task_return_export);
    const async_lift_export = try std.fmt.allocPrint(allocator, "[async-lift]{s}", .{plan.export_name});
    defer allocator.free(async_lift_export);
    const async_callback_export = try std.fmt.allocPrint(allocator, "[callback][async-lift]{s}", .{plan.export_name});
    defer allocator.free(async_callback_export);

    var wat = try allocator.dupe(u8, two_await_core_wat);
    wat = try replace_and_free(allocator, wat, "[gc-frame-runtime]", gc_frame_runtime.items);
    wat = try replace_and_free(allocator, wat, "[parameter-field]", parameter_field);
    wat = try replace_and_free(allocator, wat, "[frame-slot-initializers]", frame_slot_initializers);
    wat = try replace_and_free(allocator, wat, "[first-argument]", first_argument);
    wat = try replace_and_free(allocator, wat, "[second-argument]", second_argument);
    wat = try replace_and_free(allocator, wat, "(import \"wasi:clocks/monotonic-clock@0.3.0\" \"[async-lower]wait-for\"", first_import);
    wat = try replace_and_free(allocator, wat, "(import \"wasi:clocks/monotonic-clock@0.3.0\" \"[async-lower]wait-until\"", second_import);
    wat = try replace_and_free(allocator, wat, "[task-return]run", task_return_export);
    wat = try replace_and_free(allocator, wat, "[async-lift]run", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]run", async_callback_export);
    return wat;
}

fn emit_frame_slot_initializers(
    allocator: std.mem.Allocator,
    layout: async_model.FrameLayout,
    initial_slot_name: []const u8,
    initial_argument: component_async_plan.ScalarArgument,
) ![]u8 {
    if (layout.slots.len == 0) {
        return error.UnsupportedP3WaitForComponent;
    }

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    // Locals live at the first await are seeded from the first operation; later
    // locals are replayed by their resume expression until general body lowering.
    for (layout.slots[1..]) |slot| {
        if (slot.storage == .i64 and std.mem.eql(u8, slot.name, initial_slot_name)) {
            const value = try alloc_initial_argument_wat(allocator, initial_argument);
            defer allocator.free(value);
            try out.appendSlice(allocator, "    ");
            try out.appendSlice(allocator, value);
            try out.appendSlice(allocator, "\n");
            continue;
        }
        switch (slot.storage) {
            .i32 => try out.appendSlice(allocator, "    i32.const 0\n"),
            .i64 => try out.appendSlice(allocator, "    i64.const 0\n"),
            .f32 => try out.appendSlice(allocator, "    f32.const 0\n"),
            .f64 => try out.appendSlice(allocator, "    f64.const 0\n"),
            .waitable, .unsupported => return error.UnsupportedP3WaitForComponent,
        }
    }
    return out.toOwnedSlice(allocator);
}

fn emit_if_eq_component_core_wat(
    allocator: std.mem.Allocator,
    shared: *const component_async_plan.ComponentAsyncFunctionPlan,
) ![]u8 {
    const condition = switch (shared.control) {
        .if_eq_parameter_literal => |value| value,
        .linear, .loop_countdown => return error.UnsupportedP3WaitForComponent,
    };
    const has_join = shared.operations.len == 3;
    if ((shared.operations.len != 2 and !has_join) or shared.terminal != .await or shared.parameter.storage != .i64 or shared.async_plan == null or shared.async_plan.?.frame.resume_states.len != shared.operations.len) return error.UnsupportedP3WaitForComponent;

    const template = ClockTemplatePlan{
        .descriptor = shared.operations[0].descriptor,
        .second_descriptor = shared.operations[1].descriptor,
        .export_name = shared.export_name,
        .parameter_name = shared.parameter.name,
        .first_argument_name = shared.operations[0].argument_name,
        .second_argument_name = shared.operations[1].argument_name,
        .parameter_storage = shared.parameter.storage,
        .first_argument = shared.operations[0].argument,
        .second_argument = shared.operations[1].argument,
        .body = .two_await,
    };
    var wat = try emit_two_await_core_wat(allocator, template, &shared.async_plan.?);
    if (has_join) {
        const third = shared.operations[2];
        const third_import = try std.fmt.allocPrint(
            allocator,
            "  (import \"{s}\" \"{s}\" (func $third-host-call (type $async-lower)))\n",
            .{ third.descriptor.canonical.async_import_module, third.descriptor.canonical.async_import_name },
        );
        defer allocator.free(third_import);
        const root_import = "  (import \"$root\" \"[waitable-set-new]\"";
        const imports_with_root = try std.fmt.allocPrint(allocator, "{s}{s}", .{ third_import, root_import });
        defer allocator.free(imports_with_root);
        wat = try replace_and_free(allocator, wat, root_import, imports_with_root);
    }

    const async_lift = try std.fmt.allocPrint(allocator, "  (func (export \"[async-lift]{s}\")", .{shared.export_name});
    defer allocator.free(async_lift);
    const callback_lift = try std.fmt.allocPrint(allocator, "  (func (export \"[callback][async-lift]{s}\")", .{shared.export_name});
    defer allocator.free(callback_lift);
    const lifted = try std.fmt.allocPrint(
        allocator,
        "  (func (export \"[async-lift]{s}\") (type $async-run) (local $frame i32) (local $subtask i32)\n    i32.const 1\n    call $waitable-set-new\n    i32.const 0\n    i32.const 0\n    local.get 0\n    struct.new $async-frame\n    call $frame-alloc\n    local.tee $frame\n    call $context-set-0\n    local.get 0\n    i64.const {d}\n    i64.eq\n    if (result i32)\n      local.get $frame\n      table.get $async-frames\n      ref.as_non_null\n      i32.const 1\n      struct.set $async-frame $state\n      local.get 0\n      call $first-host-call\n    else\n      local.get $frame\n      table.get $async-frames\n      ref.as_non_null\n      i32.const 2\n      struct.set $async-frame $state\n      local.get 0\n      call $second-host-call\n    end\n    local.set $subtask\n    local.get $subtask\n    i32.const 4\n    i32.shr_u\n    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame $waitable-set\n    call $waitable-join\n    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame $waitable-set\n    i32.const 4\n    i32.shl\n    i32.const 2\n    i32.or\n  )\n\n",
        .{ shared.export_name, condition },
    );
    defer allocator.free(lifted);
    wat = try replace_between(allocator, wat, async_lift, callback_lift, lifted);

    const parameter_field = try std.fmt.allocPrint(allocator, "$slot-{s}", .{shared.parameter.name});
    defer allocator.free(parameter_field);
    const callback = if (has_join)
        try emit_if_join_callback(allocator, shared.export_name, parameter_field)
    else
        try std.fmt.allocPrint(
            allocator,
            "  (func (export \"[callback][async-lift]{s}\") (type $async-run-callback) (local $frame i32) (local $frame-ref (ref $async-frame))\n    call $context-get-0\n    local.set $frame\n    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    local.set $frame-ref\n    local.get 0\n    i32.const 1\n    i32.eq\n    local.get 2\n    i32.const 2\n    i32.eq\n    i32.and\n    if (result i32)\n      local.get $frame-ref\n      struct.get $async-frame $state\n      i32.const 1\n      i32.eq\n      if (result i32)\n        i32.const 0\n        call $context-set-0\n        local.get $frame\n        call $frame-free\n        call $task-return\n        i32.const 0\n      else\n        local.get $frame-ref\n        struct.get $async-frame $state\n        i32.const 2\n        i32.eq\n        if (result i32)\n          i32.const 0\n          call $context-set-0\n          local.get $frame\n          call $frame-free\n          call $task-return\n          i32.const 0\n        else\n          unreachable\n        end\n      end\n    else\n      local.get $frame-ref\n      struct.get $async-frame $waitable-set\n      i32.const 4\n      i32.shl\n      i32.const 2\n      i32.or\n    end\n  )\n",
            .{shared.export_name},
        );
    defer allocator.free(callback);
    const cabi_realloc = "  (func (export \"cabi_realloc\")";
    return replace_between(allocator, wat, callback_lift, cabi_realloc, callback);
}

fn emit_loop_countdown_component_core_wat(
    allocator: std.mem.Allocator,
    shared: *const component_async_plan.ComponentAsyncFunctionPlan,
) ![]u8 {
    const countdown = switch (shared.control) {
        .loop_countdown => |value| value,
        .linear, .if_eq_parameter_literal => return error.UnsupportedP3WaitForComponent,
    };
    const async_plan = shared.async_plan orelse return error.UnsupportedP3WaitForComponent;
    if (shared.operations.len != 1 or shared.terminal != .await or shared.parameter.storage != .i64 or
        async_plan.frame.resume_states.len != 1 or async_plan.layout.slots.len != 2 or
        !std.mem.eql(u8, async_plan.layout.slots[0].name, shared.parameter.name) or
        async_plan.layout.slots[0].storage != .i64 or
        !std.mem.eql(u8, async_plan.layout.slots[1].name, countdown.counter_name) or
        async_plan.layout.slots[1].storage != .i64)
        return error.UnsupportedP3WaitForComponent;

    const operation = shared.operations[0];
    var gc_frame_runtime = std.ArrayList(u8).empty;
    defer gc_frame_runtime.deinit(allocator);
    try gc_async_frame.emit_frame_table_layout(allocator, &gc_frame_runtime, async_plan.layout);
    try gc_async_frame.emit_frame_table_allocator_with_bytes(allocator, &gc_frame_runtime, async_plan.layout.size);

    const host_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ operation.descriptor.canonical.async_import_module, operation.descriptor.canonical.async_import_name },
    );
    defer allocator.free(host_import);
    const parameter_field = try std.fmt.allocPrint(allocator, "$slot-{s}", .{shared.parameter.name});
    defer allocator.free(parameter_field);
    const counter_field = try std.fmt.allocPrint(allocator, "$slot-{s}", .{countdown.counter_name});
    defer allocator.free(counter_field);
    const wit_export = try wit_identifier(allocator, shared.export_name);
    defer allocator.free(wit_export);
    const task_return_export = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{wit_export});
    defer allocator.free(task_return_export);
    const async_lift_export = try std.fmt.allocPrint(allocator, "[async-lift]{s}", .{wit_export});
    defer allocator.free(async_lift_export);
    const async_callback_export = try std.fmt.allocPrint(allocator, "[callback][async-lift]{s}", .{wit_export});
    defer allocator.free(async_callback_export);
    const lifted = try emit_loop_countdown_lifted(allocator, shared.export_name, countdown.initial, countdown.host_argument, countdown.pre_guard, counter_field);
    defer allocator.free(lifted);
    const callback = try emit_loop_countdown_callback(allocator, shared.export_name, countdown.host_argument, parameter_field, counter_field);
    defer allocator.free(callback);

    var wat = try allocator.dupe(u8, two_await_core_wat);
    wat = try replace_and_free(allocator, wat, "[gc-frame-runtime]", gc_frame_runtime.items);
    wat = try replace_and_free(allocator, wat, "(import \"wasi:clocks/monotonic-clock@0.3.0\" \"[async-lower]wait-for\"", host_import);
    wat = try replace_and_free(allocator, wat, "  (import \"wasi:clocks/monotonic-clock@0.3.0\" \"[async-lower]wait-until\" (func $second-host-call (type $async-lower)))\n", "");
    wat = try replace_and_free(allocator, wat, "[task-return]run", task_return_export);
    wat = try replace_and_free(allocator, wat, "[async-lift]run", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]run", async_callback_export);
    const async_lift = try std.fmt.allocPrint(allocator, "  (func (export \"[async-lift]{s}\")", .{shared.export_name});
    defer allocator.free(async_lift);
    const callback_lift = try std.fmt.allocPrint(allocator, "  (func (export \"[callback][async-lift]{s}\")", .{shared.export_name});
    defer allocator.free(callback_lift);
    wat = try replace_between(allocator, wat, async_lift, callback_lift, lifted);
    const cabi_realloc = "  (func (export \"cabi_realloc\")";
    return replace_between(allocator, wat, callback_lift, cabi_realloc, callback);
}

fn emit_loop_countdown_lifted(
    allocator: std.mem.Allocator,
    export_name: []const u8,
    initial: component_async_plan.LoopCountdownInitial,
    host_argument: component_async_plan.LoopCountdownHostArgument,
    pre_guard: bool,
    counter_field: []const u8,
) ![]u8 {
    const initial_wat = switch (initial) {
        .u64_literal => |value| try std.fmt.allocPrint(allocator, "i64.const {d}", .{value}),
        .parameter => try allocator.dupe(u8, "local.get 0"),
        .parameter_add_u64_literal => |value| try std.fmt.allocPrint(allocator, "local.get 0\n    i64.const {d}\n    i64.add", .{value}),
    };
    defer allocator.free(initial_wat);
    const host_argument_wat = switch (host_argument) {
        .parameter => try allocator.dupe(u8, "local.get 0"),
        .counter => try std.fmt.allocPrint(allocator, "local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame {s}", .{counter_field}),
    };
    defer allocator.free(host_argument_wat);
    const launch_wat = try std.fmt.allocPrint(
        allocator,
        "    {s}\n    call $first-host-call\n    local.set $subtask\n    local.get $subtask\n    i32.const 4\n    i32.shr_u\n    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame $waitable-set\n    call $waitable-join\n    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame $waitable-set\n    i32.const 4\n    i32.shl\n    i32.const 2\n    i32.or\n",
        .{host_argument_wat},
    );
    defer allocator.free(launch_wat);
    const guarded_launch_wat = if (pre_guard)
        try std.fmt.allocPrint(
            allocator,
            "    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    struct.get $async-frame {s}\n    i64.eqz\n    if (result i32)\n      i32.const 0\n      call $context-set-0\n      local.get $frame\n      call $frame-free\n      call $task-return\n      i32.const 0\n    else\n{s}    end\n",
            .{ counter_field, launch_wat },
        )
    else
        try allocator.dupe(u8, launch_wat);
    defer allocator.free(guarded_launch_wat);
    return std.fmt.allocPrint(
        allocator,
        "  (func (export \"[async-lift]{s}\") (type $async-run) (local $frame i32) (local $subtask i32)\n    i32.const 1\n    call $waitable-set-new\n    i32.const 0\n    i32.const 0\n    local.get 0\n    {s}\n    struct.new $async-frame\n    call $frame-alloc\n    local.tee $frame\n    call $context-set-0\n{s}  )\n\n",
        .{ export_name, initial_wat, guarded_launch_wat },
    );
}

fn emit_loop_countdown_callback(
    allocator: std.mem.Allocator,
    export_name: []const u8,
    host_argument: component_async_plan.LoopCountdownHostArgument,
    parameter_field: []const u8,
    counter_field: []const u8,
) ![]u8 {
    const host_argument_field = switch (host_argument) {
        .parameter => parameter_field,
        .counter => counter_field,
    };
    return std.fmt.allocPrint(
        allocator,
        "  (func (export \"[callback][async-lift]{s}\") (type $async-run-callback) (local $frame i32) (local $frame-ref (ref $async-frame)) (local $subtask i32)\n    call $context-get-0\n    local.set $frame\n    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    local.set $frame-ref\n    local.get 0\n    i32.const 1\n    i32.eq\n    local.get 2\n    i32.const 2\n    i32.eq\n    i32.and\n    if (result i32)\n      local.get $frame-ref\n      struct.get $async-frame $state\n      i32.const 1\n      i32.ne\n      if unreachable end\n      local.get $frame-ref\n      local.get $frame-ref\n      struct.get $async-frame {s}\n      i64.const 1\n      i64.sub\n      struct.set $async-frame {s}\n      local.get $frame-ref\n      struct.get $async-frame {s}\n      i64.eqz\n      if (result i32)\n        i32.const 0\n        call $context-set-0\n        local.get $frame\n        call $frame-free\n        call $task-return\n        i32.const 0\n      else\n        local.get $frame-ref\n        struct.get $async-frame {s}\n        call $first-host-call\n        local.set $subtask\n        local.get $subtask\n        i32.const 4\n        i32.shr_u\n        local.get $frame-ref\n        struct.get $async-frame $waitable-set\n        call $waitable-join\n        local.get $frame-ref\n        struct.get $async-frame $waitable-set\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or\n      end\n    else\n      local.get $frame-ref\n      struct.get $async-frame $waitable-set\n      i32.const 4\n      i32.shl\n      i32.const 2\n      i32.or\n    end\n  )\n",
        .{ export_name, counter_field, counter_field, counter_field, host_argument_field },
    );
}

fn emit_if_join_callback(
    allocator: std.mem.Allocator,
    export_name: []const u8,
    parameter_field: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "  (func (export \"[callback][async-lift]{s}\") (type $async-run-callback) (local $frame i32) (local $frame-ref (ref $async-frame)) (local $subtask i32)\n    call $context-get-0\n    local.set $frame\n    local.get $frame\n    table.get $async-frames\n    ref.as_non_null\n    local.set $frame-ref\n    local.get 0\n    i32.const 1\n    i32.eq\n    local.get 2\n    i32.const 2\n    i32.eq\n    i32.and\n    if (result i32)\n      local.get $frame-ref\n      struct.get $async-frame $state\n      i32.const 1\n      i32.eq\n      local.get $frame-ref\n      struct.get $async-frame $state\n      i32.const 2\n      i32.eq\n      i32.or\n      if (result i32)\n        local.get $frame-ref\n        i32.const 3\n        struct.set $async-frame $state\n        local.get $frame-ref\n        struct.get $async-frame {s}\n        call $third-host-call\n        local.set $subtask\n        local.get $subtask\n        i32.const 4\n        i32.shr_u\n        local.get $frame-ref\n        struct.get $async-frame $waitable-set\n        call $waitable-join\n        local.get $frame-ref\n        struct.get $async-frame $waitable-set\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or\n      else\n        local.get $frame-ref\n        struct.get $async-frame $state\n        i32.const 3\n        i32.ne\n        if unreachable end\n        i32.const 0\n        call $context-set-0\n        local.get $frame\n        call $frame-free\n        call $task-return\n        i32.const 0\n      end\n    else\n      local.get $frame-ref\n      struct.get $async-frame $waitable-set\n      i32.const 4\n      i32.shl\n      i32.const 2\n      i32.or\n    end\n  )\n",
        .{ export_name, parameter_field },
    );
}

fn emit_sequential_component_core_wat(
    allocator: std.mem.Allocator,
    shared: *const component_async_plan.ComponentAsyncFunctionPlan,
) ![]u8 {
    if (shared.operations.len < 3 or shared.terminal != .await or
        shared.parameter.storage != .i64 or
        shared.async_plan == null or
        shared.async_plan.?.frame.resume_states.len != shared.operations.len)
        return error.UnsupportedP3WaitForComponent;

    const template = ClockTemplatePlan{
        .descriptor = shared.operations[0].descriptor,
        .second_descriptor = shared.operations[1].descriptor,
        .export_name = shared.export_name,
        .parameter_name = shared.parameter.name,
        .first_argument_name = shared.operations[0].argument_name,
        .second_argument_name = shared.operations[1].argument_name,
        .parameter_storage = shared.parameter.storage,
        .first_argument = shared.operations[0].argument,
        .second_argument = shared.operations[1].argument,
        .body = .two_await,
    };
    var wat = try emit_two_await_core_wat(allocator, template, &shared.async_plan.?);

    var extra_imports = std.ArrayList(u8).empty;
    defer extra_imports.deinit(allocator);
    var operation_index: usize = 2;
    while (operation_index < shared.operations.len) : (operation_index += 1) {
        const operation = shared.operations[operation_index];
        try append_fmt(
            allocator,
            &extra_imports,
            "  (import \"{s}\" \"{s}\" (func ",
            .{ operation.descriptor.canonical.async_import_module, operation.descriptor.canonical.async_import_name },
        );
        try append_host_call_symbol(allocator, &extra_imports, operation_index);
        try extra_imports.appendSlice(allocator, " (type $async-lower)))\n");
    }
    const root_import = "  (import \"$root\" \"[waitable-set-new]\"";
    const imports_with_root = try std.fmt.allocPrint(allocator, "{s}{s}", .{ extra_imports.items, root_import });
    defer allocator.free(imports_with_root);
    wat = try replace_and_free(allocator, wat, root_import, imports_with_root);

    const parameter_field = try std.fmt.allocPrint(allocator, "$slot-{s}", .{shared.parameter.name});
    defer allocator.free(parameter_field);
    var tail = std.ArrayList(u8).empty;
    defer tail.deinit(allocator);
    try emit_extra_resume_tail(allocator, &tail, 2, shared.operations, &shared.async_plan.?, parameter_field);
    wat = try replace_and_free(allocator, wat, two_await_terminal_tail, tail.items);
    return wat;
}

fn emit_extra_resume_tail(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: usize,
    operations: []const component_async_plan.Operation,
    async_plan: *const async_model.AsyncFunctionPlan,
    parameter_field: []const u8,
) !void {
    if (state < operations.len) {
        try append_fmt(
            allocator,
            out,
            "        local.get $frame-ref\n        struct.get $async-frame $state\n        i32.const {d}\n        i32.eq\n        if (result i32)\n          local.get $frame-ref\n          i32.const {d}\n          struct.set $async-frame $state\n",
            .{ state, state + 1 },
        );
        try append_resumed_argument_wat(
            allocator,
            out,
            operations[state].argument,
            operations[state].argument_name,
            async_plan,
            parameter_field,
            "          ",
        );
        try out.appendSlice(allocator, "          call ");
        try append_host_call_symbol(allocator, out, state);
        try out.appendSlice(allocator, "\n          local.set $subtask\n          local.get $subtask\n          i32.const 4\n          i32.shr_u\n          local.get $frame-ref\n          struct.get $async-frame $waitable-set\n          call $waitable-join\n          local.get $frame-ref\n          struct.get $async-frame $waitable-set\n          i32.const 4\n          i32.shl\n          i32.const 2\n          i32.or\n        else\n");
        try emit_extra_resume_tail(allocator, out, state + 1, operations, async_plan, parameter_field);
        try out.appendSlice(allocator, "        end\n");
        return;
    }
    try append_fmt(
        allocator,
        out,
        "        local.get $frame-ref\n        struct.get $async-frame $state\n        i32.const {d}\n        i32.ne\n        if unreachable end\n        i32.const 0\n        call $context-set-0\n        local.get $frame\n        call $frame-free\n        call $task-return\n        i32.const 0\n",
        .{state},
    );
}

fn alloc_initial_argument_wat(allocator: std.mem.Allocator, argument: component_async_plan.ScalarArgument) ![]u8 {
    return switch (argument) {
        .parameter => allocator.dupe(u8, "local.get 0"),
        .u64_literal => |value| std.fmt.allocPrint(allocator, "i64.const {d}", .{value}),
        .u64_add_parameter_literal => |value| std.fmt.allocPrint(allocator, "local.get 0\n    i64.const {d}\n    i64.add", .{value}),
    };
}

fn alloc_resumed_argument_wat(
    allocator: std.mem.Allocator,
    argument: component_async_plan.ScalarArgument,
    argument_name: []const u8,
    async_plan: ?*const async_model.AsyncFunctionPlan,
    parameter_field: []const u8,
) ![]u8 {
    if (async_plan) |plan| {
        if (first_resume_state_contains(plan, argument_name)) {
            const field = try std.fmt.allocPrint(allocator, "$slot-{s}", .{argument_name});
            defer allocator.free(field);
            return std.fmt.allocPrint(allocator, "local.get $frame-ref\n        struct.get $async-frame {s}", .{field});
        }
    }
    return switch (argument) {
        .parameter => std.fmt.allocPrint(allocator, "local.get $frame-ref\n        struct.get $async-frame {s}", .{parameter_field}),
        .u64_literal => |value| std.fmt.allocPrint(allocator, "i64.const {d}", .{value}),
        .u64_add_parameter_literal => |value| std.fmt.allocPrint(allocator, "local.get $frame-ref\n        struct.get $async-frame {s}\n        i64.const {d}\n        i64.add", .{ parameter_field, value }),
    };
}

fn append_resumed_argument_wat(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    argument: component_async_plan.ScalarArgument,
    argument_name: []const u8,
    async_plan: *const async_model.AsyncFunctionPlan,
    parameter_field: []const u8,
    indent: []const u8,
) !void {
    if (first_resume_state_contains(async_plan, argument_name)) {
        try append_fmt(
            allocator,
            out,
            "{s}local.get $frame-ref\n{s}struct.get $async-frame $slot-{s}\n",
            .{ indent, indent, argument_name },
        );
        return;
    }
    switch (argument) {
        .parameter => try append_fmt(
            allocator,
            out,
            "{s}local.get $frame-ref\n{s}struct.get $async-frame {s}\n",
            .{ indent, indent, parameter_field },
        ),
        .u64_literal => |value| try append_fmt(allocator, out, "{s}i64.const {d}\n", .{ indent, value }),
        .u64_add_parameter_literal => |value| try append_fmt(
            allocator,
            out,
            "{s}local.get $frame-ref\n{s}struct.get $async-frame {s}\n{s}i64.const {d}\n{s}i64.add\n",
            .{ indent, indent, parameter_field, indent, value, indent },
        ),
    }
}

fn first_resume_state_contains(plan: *const async_model.AsyncFunctionPlan, name: []const u8) bool {
    if (name.len == 0 or plan.frame.resume_states.len == 0) return false;
    for (plan.frame.resume_states[0].live_slots) |slot| {
        if (std.mem.eql(u8, slot.name, name)) return true;
    }
    return false;
}

fn append_host_call_symbol(allocator: std.mem.Allocator, out: *std.ArrayList(u8), operation_index: usize) !void {
    switch (operation_index) {
        0 => try out.appendSlice(allocator, "$first-host-call"),
        1 => try out.appendSlice(allocator, "$second-host-call"),
        2 => try out.appendSlice(allocator, "$third-host-call"),
        else => try append_fmt(allocator, out, "$host-call-{d}", .{operation_index}),
    }
}

const two_await_terminal_tail =
    "        local.get $frame-ref\n" ++
    "        struct.get $async-frame $state\n" ++
    "        i32.const 2\n" ++
    "        i32.ne\n" ++
    "        if unreachable end\n" ++
    "        i32.const 0\n" ++
    "        call $context-set-0\n" ++
    "        local.get $frame\n" ++
    "        call $frame-free\n" ++
    "        call $task-return\n" ++
    "        i32.const 0\n";

fn emit_cli_result_core_wat(allocator: std.mem.Allocator, plan: CliResultPlan) ![]u8 {
    const await_sites = [_]async_model.AwaitSite{.{ .token_index = 0, .live_slots = &.{} }};
    var frame = try async_model.FrameModel.collect(allocator, &await_sites);
    defer frame.deinit(allocator);
    var layout = try async_model.FrameLayout.collect(allocator, frame);
    defer layout.deinit(allocator);
    if (layout.state_offset != 0 or
        layout.waitable_set_offset != 4 or
        layout.cleanup_flags_offset != 8 or
        layout.completion_value_offset != 12 or
        layout.slots.len != 0 or
        layout.size != 16) return error.UnsupportedP3WaitForComponent;

    const frame_size = try std.fmt.allocPrint(allocator, "{d}", .{layout.size});
    defer allocator.free(frame_size);
    const waitable_set_offset = try std.fmt.allocPrint(allocator, "{d}", .{layout.waitable_set_offset});
    defer allocator.free(waitable_set_offset);
    const completion_value_offset = try std.fmt.allocPrint(allocator, "{d}", .{layout.completion_value_offset});
    defer allocator.free(completion_value_offset);
    const task_return_export = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{plan.export_name});
    defer allocator.free(task_return_export);
    const async_lift_export = try std.fmt.allocPrint(allocator, "[async-lift]{s}", .{plan.export_name});
    defer allocator.free(async_lift_export);
    const async_callback_export = try std.fmt.allocPrint(allocator, "[callback][async-lift]{s}", .{plan.export_name});
    defer allocator.free(async_callback_export);
    const async_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ plan.descriptor.canonical.async_import_module, plan.descriptor.canonical.async_import_name },
    );
    defer allocator.free(async_import);

    var wat = try allocator.dupe(u8, cli_result_core_wat);
    wat = try replace_and_free(allocator, wat, "[frame-size]", frame_size);
    wat = try replace_and_free(allocator, wat, "[waitable-set-offset]", waitable_set_offset);
    wat = try replace_and_free(allocator, wat, "[completion-value-offset]", completion_value_offset);
    wat = try replace_and_free(allocator, wat, "[completion-transform]", switch (plan.completion_behavior) {
        .passthrough => "",
        .invert_ok => "i32.eqz\n      ",
    });
    wat = try replace_and_free(allocator, wat, "(import \"wasi:cli/run@0.3.0\" \"[async-lower]run\"", async_import);
    wat = try replace_and_free(allocator, wat, "[task-return]run", task_return_export);
    wat = try replace_and_free(allocator, wat, "[async-lift]run", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]run", async_callback_export);
    return wat;
}

fn emit_scalar_result_core_wat(
    allocator: std.mem.Allocator,
    shared: *const component_async_plan.ComponentAsyncFunctionPlan,
) ![]u8 {
    if (shared.control != .linear or shared.operations.len != 1 or
        (shared.terminal != .return_await and shared.terminal != .cancel)) return error.UnsupportedP3WaitForComponent;
    const operation = shared.operations[0];
    const payload = operation.result_payload orelse return error.UnsupportedP3WaitForComponent;
    const descriptor = operation.descriptor;
    if (payload.tag.len == 0 or payload.ok.len != 1 or payload.err.len != 1 or
        !std.mem.eql(u8, payload.tag, "i32") or
        !std.mem.eql(u8, payload.ok[0], "i32") or
        !std.mem.eql(u8, payload.err[0], "i32") or
        descriptor.canonical.core_params.len != 2 or
        descriptor.canonical.core_results.len != 1 or
        descriptor.canonical.completion_params.len != 2 or
        !all_i32(descriptor.canonical.core_params) or
        !all_i32(descriptor.canonical.core_results) or
        !all_i32(descriptor.canonical.completion_params) or
        p3_async_manifest.source_scalar_core_type(descriptor.params[0]) == null or
        !std.mem.eql(u8, p3_async_manifest.source_scalar_core_type(descriptor.params[0]).?, descriptor.canonical.core_params[0]))
    {
        return error.UnsupportedP3WaitForComponent;
    }

    const wit_export = try wit_identifier(allocator, shared.export_name);
    defer allocator.free(wit_export);
    const task_return_export = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{wit_export});
    defer allocator.free(task_return_export);
    const async_lift_export = try std.fmt.allocPrint(allocator, "[async-lift]{s}", .{wit_export});
    defer allocator.free(async_lift_export);
    const async_callback_export = try std.fmt.allocPrint(allocator, "[callback][async-lift]{s}", .{wit_export});
    defer allocator.free(async_callback_export);
    const async_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ descriptor.canonical.async_import_module, descriptor.canonical.async_import_name },
    );
    defer allocator.free(async_import);

    var wat = try allocator.dupe(u8, scalar_result_core_wat);
    const frame_bytes = try std.fmt.allocPrint(allocator, "{d}", .{scalar_result_frame_bytes});
    defer allocator.free(frame_bytes);
    wat = try replace_and_free(allocator, wat, "[scalar-result-frame-bytes]", frame_bytes);
    wat = try replace_and_free(allocator, wat, "[scalar-result-budget-runtime]", scalar_result_budget_runtime);
    wat = try replace_and_free(allocator, wat, "(import \"do:result-probe/run@0.1.0\" \"[async-lower]run\"", async_import);
    if (shared.terminal == .cancel) {
        wat = try replace_and_free(allocator, wat, "(type $task-return (func (param i32 i32)))", "(type $task-return (func))");
    }
    wat = try replace_and_free(allocator, wat, "[terminal-body]", if (shared.terminal == .cancel) scalar_result_cancel_body else scalar_result_await_body);
    wat = try replace_and_free(allocator, wat, "[callback-body]", if (shared.terminal == .cancel) scalar_result_cancel_callback_body else scalar_result_await_callback_body);
    wat = try replace_and_free(allocator, wat, "[task-return]run", task_return_export);
    wat = try replace_and_free(allocator, wat, "[async-lift]run", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]run", async_callback_export);
    return wat;
}

fn emit_scalar_result_wit_for_plan(
    allocator: std.mem.Allocator,
    shared: *const component_async_plan.ComponentAsyncFunctionPlan,
) ![]u8 {
    if (shared.operations.len != 1 or
        (shared.terminal != .return_await and shared.terminal != .cancel)) return error.UnsupportedP3WaitForComponent;
    const descriptor = shared.operations[0].descriptor;
    const payload = shared.operations[0].result_payload orelse return error.UnsupportedP3WaitForComponent;
    if (payload.ok.len != 1 or payload.err.len != 1 or
        !std.mem.eql(u8, payload.ok[0], "i32") or !std.mem.eql(u8, payload.err[0], "i32") or
        descriptor.params.len != 1) return error.UnsupportedP3WaitForComponent;
    const source = p3_async_manifest.scalar_result_source_types(descriptor.result) orelse return error.UnsupportedP3WaitForComponent;
    const parameter_type = wit_scalar_type(descriptor.params[0]) orelse return error.UnsupportedP3WaitForComponent;
    const result_type = try wit_result_type(allocator, source);
    defer allocator.free(result_type);
    const wit_export = try wit_identifier(allocator, shared.export_name);
    defer allocator.free(wit_export);
    const import_result_suffix = try std.fmt.allocPrint(allocator, " -> {s}", .{result_type});
    defer allocator.free(import_result_suffix);
    const export_result_suffix = if (shared.terminal == .cancel) "" else import_result_suffix;
    return std.fmt.allocPrint(
        allocator,
        "package {s};\n\ninterface {s} {{\n  {s}: async func({s}: {s}){s};\n}}\n\nworld {s} {{\n  import {s};\n  export {s}: async func({s}: {s}){s};\n}}\n",
        .{
            descriptor.wit.package,
            descriptor.wit.interface,
            descriptor.wit.operation,
            descriptor.wit.parameter,
            parameter_type,
            import_result_suffix,
            descriptor.wit.world,
            descriptor.wit.interface,
            wit_export,
            descriptor.wit.parameter,
            parameter_type,
            export_result_suffix,
        },
    );
}

fn wit_result_type(allocator: std.mem.Allocator, source: p3_async_manifest.ScalarResultSource) ![]u8 {
    const ok = if (std.mem.eql(u8, source.ok, "nil")) null else wit_scalar_type(source.ok) orelse return error.UnsupportedP3WaitForComponent;
    const err = if (std.mem.eql(u8, source.err, "nil")) null else wit_scalar_type(source.err) orelse return error.UnsupportedP3WaitForComponent;
    if (ok) |ok_type| {
        if (err) |err_type| return std.fmt.allocPrint(allocator, "result<{s}, {s}>", .{ ok_type, err_type });
        return std.fmt.allocPrint(allocator, "result<{s}>", .{ok_type});
    }
    if (err) |err_type| return std.fmt.allocPrint(allocator, "result<_, {s}>", .{err_type});
    return error.UnsupportedP3WaitForComponent;
}

fn wit_scalar_type(value: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, value, "i32")) return "s32";
    if (std.mem.eql(u8, value, "i8")) return "s8";
    if (std.mem.eql(u8, value, "i16")) return "s16";
    if (std.mem.eql(u8, value, "u8")) return "u8";
    if (std.mem.eql(u8, value, "u16")) return "u16";
    if (std.mem.eql(u8, value, "u32")) return "u32";
    if (std.mem.eql(u8, value, "i64")) return "s64";
    if (std.mem.eql(u8, value, "u64")) return "u64";
    if (std.mem.eql(u8, value, "f32")) return "float32";
    if (std.mem.eql(u8, value, "f64")) return "float64";
    if (std.mem.eql(u8, value, "bool")) return "bool";
    return null;
}

fn all_i32(values: []const []const u8) bool {
    for (values) |value| {
        if (!std.mem.eql(u8, value, "i32")) return false;
    }
    return true;
}

fn emit_component_wit_for_plan(allocator: std.mem.Allocator, plan: ClockTemplatePlan) ![]u8 {
    const wit_export = try wit_identifier(allocator, plan.export_name);
    defer allocator.free(wit_export);
    if (plan.second_descriptor) |second| {
        return std.fmt.allocPrint(
            allocator,
            "package {s};\n\ninterface {s} {{\n  {s}: async func({s}: {s});\n  {s}: async func({s}: {s});\n}}\n\nworld {s} {{\n  import {s};\n  export {s}: async func({s}: {s});\n}}\n",
            .{
                plan.descriptor.wit.package,
                plan.descriptor.wit.interface,
                plan.descriptor.wit.operation,
                plan.descriptor.wit.parameter,
                plan.descriptor.params[0],
                second.wit.operation,
                second.wit.parameter,
                second.params[0],
                plan.descriptor.wit.world,
                plan.descriptor.wit.interface,
                wit_export,
                plan.descriptor.wit.parameter,
                plan.descriptor.params[0],
            },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "package {s};\n\ninterface {s} {{\n  {s}: async func({s}: {s});\n}}\n\nworld {s} {{\n  import {s};\n  export {s}: async func({s}: {s});\n}}\n",
        .{
            plan.descriptor.wit.package,
            plan.descriptor.wit.interface,
            plan.descriptor.wit.operation,
            plan.descriptor.wit.parameter,
            plan.descriptor.params[0],
            plan.descriptor.wit.world,
            plan.descriptor.wit.interface,
            wit_export,
            plan.descriptor.wit.parameter,
            plan.descriptor.params[0],
        },
    );
}

fn emit_component_wit_for_shared_plan(
    allocator: std.mem.Allocator,
    shared: *const component_async_plan.ComponentAsyncFunctionPlan,
) ![]u8 {
    if (shared.operations.len == 0) return error.UnsupportedP3WaitForComponent;
    const first = shared.operations[0].descriptor;
    const wit_export = try wit_identifier(allocator, shared.export_name);
    defer allocator.free(wit_export);

    var wit = std.ArrayList(u8).empty;
    errdefer wit.deinit(allocator);
    try append_fmt(allocator, &wit, "package {s};\n\ninterface {s} {{\n", .{ first.wit.package, first.wit.interface });
    for (shared.operations, 0..) |operation, index| {
        if (has_prior_wit_operation(shared.operations[0..index], operation.descriptor)) continue;
        try append_fmt(
            allocator,
            &wit,
            "  {s}: async func({s}: {s});\n",
            .{ operation.descriptor.wit.operation, operation.descriptor.wit.parameter, operation.descriptor.params[0] },
        );
    }
    try append_fmt(
        allocator,
        &wit,
        "}}\n\nworld {s} {{\n  import {s};\n  export {s}: async func({s}: {s});\n}}\n",
        .{ first.wit.world, first.wit.interface, wit_export, first.wit.parameter, first.params[0] },
    );
    return wit.toOwnedSlice(allocator);
}

fn has_prior_wit_operation(
    previous: []const component_async_plan.Operation,
    descriptor: p3_async_manifest.Descriptor,
) bool {
    for (previous) |operation| {
        const prior = operation.descriptor;
        if (std.mem.eql(u8, prior.wit.operation, descriptor.wit.operation) and
            std.mem.eql(u8, prior.wit.parameter, descriptor.wit.parameter) and
            std.mem.eql(u8, prior.params[0], descriptor.params[0])) return true;
    }
    return false;
}

fn emit_cli_result_wit_for_plan(allocator: std.mem.Allocator, plan: CliResultPlan) ![]u8 {
    const wit_export = try wit_identifier(allocator, plan.export_name);
    defer allocator.free(wit_export);
    return std.fmt.allocPrint(
        allocator,
        "package {s};\n\ninterface {s} {{\n  {s}: async func() -> result;\n}}\n\nworld {s} {{\n  import {s};\n  export {s}: async func() -> result;\n}}\n",
        .{
            plan.descriptor.wit.package,
            plan.descriptor.wit.interface,
            plan.descriptor.wit.operation,
            plan.descriptor.wit.world,
            plan.descriptor.wit.interface,
            wit_export,
        },
    );
}

fn wit_identifier(allocator: std.mem.Allocator, source_name: []const u8) ![]u8 {
    const rendered = try allocator.dupe(u8, source_name);
    for (rendered) |*ch| {
        if (ch.* == '_') ch.* = '-';
    }
    return rendered;
}

fn replace_and_free(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const replaced = try replace_all(allocator, input, needle, replacement);
    allocator.free(input);
    return replaced;
}

fn replace_between(
    allocator: std.mem.Allocator,
    input: []u8,
    start: []const u8,
    end: []const u8,
    replacement: []const u8,
) ![]u8 {
    const start_idx = std.mem.indexOf(u8, input, start) orelse return error.UnsupportedP3WaitForComponent;
    const tail_start = start_idx + start.len;
    const end_relative = std.mem.indexOf(u8, input[tail_start..], end) orelse return error.UnsupportedP3WaitForComponent;
    const output = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        input[0..start_idx],
        replacement,
        input[tail_start + end_relative ..],
    });
    allocator.free(input);
    return output;
}

fn replace_all(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return error.UnsupportedP3WaitForComponent;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var remainder = input;
    while (std.mem.indexOf(u8, remainder, needle)) |idx| {
        try out.appendSlice(allocator, remainder[0..idx]);
        try out.appendSlice(allocator, replacement);
        remainder = remainder[idx + needle.len ..];
    }
    try out.appendSlice(allocator, remainder);
    return out.toOwnedSlice(allocator);
}

fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

const two_await_core_wat =
    \\(module
    \\  (type $async-lower (func (param i64) (result i32)))
    \\  (type $task-return (func))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $async-run (func (param i64) (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\
    \\  (import "wasi:clocks/monotonic-clock@0.3.0" "[async-lower]wait-for" (func $first-host-call (type $async-lower)))
    \\  (import "wasi:clocks/monotonic-clock@0.3.0" "[async-lower]wait-until" (func $second-host-call (type $async-lower)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (result i32)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (param i32)))
    \\  (import "[export]$root" "[task-return]run" (func $task-return (type $task-return)))
    \\
    \\  (memory (export "memory") 1)
    \\[gc-frame-runtime]
    \\
    \\  (func (export "[async-lift]run") (type $async-run) (local $frame i32) (local $subtask i32)
    \\    i32.const 1
    \\    call $waitable-set-new
    \\    i32.const 0
    \\    i32.const 0
    \\    local.get 0
    \\[frame-slot-initializers]
    \\    struct.new $async-frame
    \\    call $frame-alloc
    \\    local.tee $frame
    \\    call $context-set-0
    \\    [first-argument]
    \\    call $first-host-call
    \\    local.set $subtask
    \\    local.get $subtask
    \\    i32.const 4
    \\    i32.shr_u
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    struct.get $async-frame $waitable-set
    \\    call $waitable-join
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    struct.get $async-frame $waitable-set
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\
    \\  (func (export "[callback][async-lift]run") (type $async-run-callback) (local $frame i32) (local $frame-ref (ref $async-frame)) (local $subtask i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    local.set $frame-ref
    \\    local.get 0
    \\    i32.const 1
    \\    i32.eq
    \\    local.get 2
    \\    i32.const 2
    \\    i32.eq
    \\    i32.and
    \\    if (result i32)
    \\      local.get $frame-ref
    \\      struct.get $async-frame $state
    \\      i32.const 1
    \\      i32.eq
    \\      if (result i32)
    \\        local.get $frame-ref
    \\        i32.const 2
    \\        struct.set $async-frame $state
    \\        [second-argument]
    \\        call $second-host-call
    \\        local.set $subtask
    \\        local.get $subtask
    \\        i32.const 4
    \\        i32.shr_u
    \\        local.get $frame-ref
    \\        struct.get $async-frame $waitable-set
    \\        call $waitable-join
    \\        local.get $frame-ref
    \\        struct.get $async-frame $waitable-set
    \\        i32.const 4
    \\        i32.shl
    \\        i32.const 2
    \\        i32.or
    \\      else
    \\        local.get $frame-ref
    \\        struct.get $async-frame $state
    \\        i32.const 2
    \\        i32.ne
    \\        if unreachable end
    \\        i32.const 0
    \\        call $context-set-0
    \\        local.get $frame
    \\        call $frame-free
    \\        call $task-return
    \\        i32.const 0
    \\      end
    \\    else
    \\      local.get $frame-ref
    \\      struct.get $async-frame $waitable-set
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end
    \\  )
    \\  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
    \\  (func (export "_initialize"))
    \\)
;

const core_wat =
    \\;; Generated only for the pinned do wait-for lowering probe.
    \\;; This is Core WAT. Embed its pinned WIT metadata with `wasm-tools
    \\;; component embed`, then run `wasm-tools component new` before passing
    \\;; it to a Component host.
    \\(module
    \\  (type $async-lower-wait-for (func (param i64) (result i32)))
    \\  (type $task-return (func))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $async-run (func (param i64) (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\
    \\  (import "wasi:clocks/monotonic-clock@0.3.0" "[async-lower]wait-for"
    \\    (func $wait-for (type $async-lower-wait-for)))
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel))
    \\  (import "$root" "[backpressure-inc]" (func $backpressure-inc))
    \\  (import "$root" "[backpressure-dec]" (func $backpressure-dec))
    \\  (import "$root" "[waitable-set-new]"
    \\    (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (param i32 i32) (result i32)))
    \\  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (param i32 i32) (result i32)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (param i32)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[thread-yield]" (func $thread-yield (result i32)))
    \\  (import "$root" "[subtask-drop]" (func $subtask-drop (param i32)))
    \\  (import "$root" "[subtask-cancel]" (func $subtask-cancel (param i32) (result i32)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (result i32)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (param i32)))
    \\  (import "[export]$root" "[task-return]run"
    \\    (func $task-return (type $task-return)))
    \\
    \\  (memory (export "memory") 0)
    \\
    \\  (func (export "[async-lift]run") (type $async-run) (local $subtask i32) (local $waitable-set i32)
    \\    call $waitable-set-new
    \\    local.tee $waitable-set
    \\    call $context-set-0
    \\    local.get 0
    \\    call $wait-for
    \\    local.set $subtask
    \\    local.get $subtask
    \\    i32.const 4
    \\    i32.shr_u
    \\    local.get $waitable-set
    \\    call $waitable-join
    \\    local.get $waitable-set
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\  (func (export "[callback][async-lift]run") (type $async-run-callback) (local $waitable-set i32)
    \\    call $context-get-0
    \\    local.set $waitable-set
    \\    local.get 0
    \\    i32.const 1
    \\    i32.eq
    \\    local.get 2
    \\    i32.const 2
    \\    i32.eq
    \\    i32.and
    \\    if (result i32)
    \\      call $task-return
    \\      i32.const 0
    \\    else
    \\      local.get $waitable-set
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end
    \\  )
    \\  (func (export "cabi_realloc") (type $cabi-realloc)
    \\    unreachable
    \\  )
    \\  (func (export "_initialize"))
    \\)
;

const cancel_async_body =
    \\  (func (export "[async-lift]run") (type $async-run) (local $subtask i32)
    \\    local.get 0
    \\    call $wait-for
    \\    local.tee $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      i32.const 0
    \\      call $context-set-0
    \\      call $task-return
    \\      i32.const 0
    \\    else
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      local.set $subtask
    \\      local.get $subtask
    \\      call $subtask-cancel
    \\      i32.const 4
    \\      i32.ne
    \\      if
    \\        unreachable
    \\      end
    \\      local.get $subtask
    \\      call $subtask-drop
    \\      call $task-return
    \\      i32.const 0
    \\    end
    \\  )
    \\  (func (export "[callback][async-lift]run") (type $async-run-callback)
    \\    unreachable
    \\  )
;

const scalar_result_frame_bytes: u64 = async_byte_budget.bytes_for_task_frame(16, 4) catch unreachable;

const scalar_result_budget_runtime =
    \\  (global $async-byte-budget-used (mut i64) (i64.const 0))
    \\  (global $async-byte-budget-limit (mut i64) (i64.const -1))
    \\  (func $async-byte-budget-limit (export "[async-config]byte-budget-limit") (param $limit i64) (result i32)
    \\    local.get $limit
    \\    i64.const -1
    \\    i64.eq
    \\    if (result i32)
    \\      local.get $limit
    \\      global.set $async-byte-budget-limit
    \\      i32.const 1
    \\    else
    \\      local.get $limit
    \\      i64.const 0
    \\      i64.lt_s
    \\      if (result i32)
    \\        i32.const 0
    \\      else
    \\        global.get $async-byte-budget-used
    \\        local.get $limit
    \\        i64.gt_u
    \\        if (result i32)
    \\          i32.const 0
    \\        else
    \\          local.get $limit
    \\          global.set $async-byte-budget-limit
    \\          i32.const 1
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func (export "byte-budget-limit") (param $limit i64) (result i32)
    \\    local.get $limit
    \\    call $async-byte-budget-limit)
    \\  (func $async-byte-budget-reserve (param $bytes i64) (result i32)
    \\    (local $next i64)
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.add
    \\    local.tee $next
    \\    global.get $async-byte-budget-used
    \\    i64.lt_u
    \\    if (result i32)
    \\      i32.const 0
    \\    else
    \\      global.get $async-byte-budget-limit
    \\      i64.const -1
    \\      i64.eq
    \\      if (result i32)
    \\        i32.const 1
    \\      else
    \\        local.get $next
    \\        global.get $async-byte-budget-limit
    \\        i64.le_u
    \\      end
    \\      if (result i32)
    \\        local.get $next
    \\        global.set $async-byte-budget-used
    \\        i32.const 1
    \\      else
    \\        i32.const 0
    \\      end
    \\    end
    \\  )
    \\  (func $async-byte-budget-release (param $bytes i64)
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.lt_u
    \\    if unreachable end
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.sub
    \\    global.set $async-byte-budget-used
    \\  )
;

const scalar_result_core_wat =
    \\;; Generated for a registered scalar Result async descriptor.
    \\(module
    \\  ;; [result-tag] offset=0, [result-payload] offset=4
    \\  (type $async-lower (func (param i32 i32) (result i32)))
    \\  (type $task-return (func (param i32 i32)))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $async-run (func (param i32) (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\
    \\  (import "do:result-probe/run@0.1.0" "[async-lower]run"
    \\    (func $result-run (type $async-lower)))
    \\  (import "$root" "[waitable-set-new]"
    \\    (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-join]"
    \\    (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[subtask-cancel]"
    \\    (func $subtask-cancel (param i32) (result i32)))
    \\  (import "$root" "[subtask-drop]"
    \\    (func $subtask-drop (param i32)))
    \\  (import "$root" "[context-get-0]"
    \\    (func $context-get-0 (result i32)))
    \\  (import "$root" "[context-set-0]"
    \\    (func $context-set-0 (param i32)))
    \\  (import "[export]$root" "[task-return]run"
    \\    (func $task-return (type $task-return)))
    \\
    \\  (memory (export "memory") 1)
    \\  ;; [async-frame-budget-bytes] [scalar-result-frame-bytes]
    \\  ;; [async-byte-budget-limit] -1
    \\[scalar-result-budget-runtime]
    \\  (global $frame-next (mut i32) (i32.const 1024))
    \\
    \\  (func $frame-alloc (result i32) (local $frame i32) (local $frame-next-next i32)
    \\    i64.const [scalar-result-frame-bytes]
    \\    call $async-byte-budget-reserve
    \\    i32.eqz
    \\    if unreachable end
    \\    global.get $frame-next
    \\    local.set $frame
    \\    global.get $frame-next
    \\    i32.const [scalar-result-frame-bytes]
    \\    i32.add
    \\    local.tee $frame-next-next
    \\    global.get $frame-next
    \\    i32.lt_u
    \\    if
    \\      i64.const [scalar-result-frame-bytes]
    \\      call $async-byte-budget-release
    \\      unreachable
    \\    end
    \\    local.get $frame-next-next
    \\    memory.size
    \\    i32.const 16
    \\    i32.shl
    \\    i32.gt_u
    \\    if
    \\      i64.const [scalar-result-frame-bytes]
    \\      call $async-byte-budget-release
    \\      unreachable
    \\    end
    \\    local.get $frame-next-next
    \\    global.set $frame-next
    \\    local.get $frame
    \\  )
    \\  (func $frame-free (param $frame i32)
    \\    local.get $frame
    \\    drop
    \\    i64.const [scalar-result-frame-bytes]
    \\    call $async-byte-budget-release
    \\  )
    \\
    \\  (func (export "[async-lift]run") (type $async-run)
    \\    (local $frame i32) (local $set i32) (local $subtask i32)
    \\    call $frame-alloc
    \\    local.set $frame
    \\    local.get $frame
    \\    i32.const 0
    \\    i32.store offset=0
    \\    call $waitable-set-new
    \\    local.set $set
    \\    local.get $frame
    \\    local.get $set
    \\    i32.store offset=16
    \\    local.get $frame
    \\    call $context-set-0
    \\    local.get 0
    \\    local.get $frame
    \\    call $result-run
    \\    local.set $subtask
    \\    [terminal-body]
    \\  )
    \\
    \\  (func (export "[callback][async-lift]run") (type $async-run-callback)
    \\    (local $frame i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get 0
    \\    i32.const 1
    \\    i32.eq
    \\    local.get 2
    \\    i32.const 2
    \\    i32.eq
    \\    i32.and
    \\    if (result i32)
    \\      [callback-body]
    \\    else
    \\      local.get $frame
    \\      i32.load offset=16
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end
    \\  )
    \\
    \\  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
    \\  (func (export "_initialize"))
    \\)
;

const scalar_result_await_body =
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      i32.load offset=0
    \\      local.get $frame
    \\      i32.load offset=4
    \\      i32.const 0
    \\      call $context-set-0
    \\      call $task-return
    \\      local.get $frame
    \\      call $frame-free
    \\      i32.const 0
    \\    else
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      local.get $set
    \\      call $waitable-join
    \\      local.get $set
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end
;

const scalar_result_cancel_body =
    \\    local.get $subtask
    \\    i32.const 4
    \\    i32.shr_u
    \\    call $subtask-cancel
    \\    i32.const 4
    \\    i32.ne
    \\    if
    \\      unreachable
    \\    end
    \\    local.get $subtask
    \\    i32.const 4
    \\    i32.shr_u
    \\    call $subtask-drop
    \\    i32.const 0
    \\    call $context-set-0
    \\    ;; [async-terminal] cancelled
    \\    call $task-return
    \\    local.get $frame
    \\    call $frame-free
    \\    i32.const 0
;

const scalar_result_await_callback_body =
    \\      ;; [result-payload] is shared by the Ok and Err arms.
    \\      local.get $frame
    \\      i32.load offset=0
    \\      local.get $frame
    \\      i32.load offset=4
    \\      i32.const 0
    \\      call $context-set-0
    \\      ;; [async-terminal] returned
    \\      call $task-return
    \\      local.get $frame
    \\      call $frame-free
    \\      i32.const 0
;

const scalar_result_cancel_callback_body =
    \\      unreachable
;

const component_wit =
    \\package wasi:clocks@0.3.0;
    \\
    \\interface monotonic-clock {
    \\  wait-for: async func(how-long: u64);
    \\}
    \\
    \\world probe {
    \\  import monotonic-clock;
    \\  export run: async func(how-long: u64);
    \\}
;

const cli_result_core_wat = @embedFile("p3_cli_result_probe.wat");

test "component planning accepts one registered scalar unit await" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    var plan = try component_async_plan.ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("monotonic-clock.wait-for", plan.operations[0].descriptor.member);
    try std.testing.expectEqualStrings("run", plan.export_name);
}

test "component planning rejects an await with unsupported arguments" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    await(pending, 1)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedP3WaitForComponent, component_async_plan.ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry));
}

test "component planning accepts source aliases while preserving data flow" {
    const source =
        \\clock_wait = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(duration u64) -> nil {
        \\    waiting Future<nil> = clock_wait(duration)
        \\    await(waiting)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    var plan = try component_async_plan.ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("duration", plan.parameter.name);
}

test "component lowering accepts a scalar parameter alias before a single await" {
    const source =
        \\clock_wait = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async tick(deadline u64) -> nil {
        \\    forwarded u64 = deadline
        \\    pending Future<nil> = clock_wait(forwarded)
        \\    await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]tick") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]wait-until") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "$frame-alloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $slot-deadline (mut i64))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $slot-forwarded (mut i64))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $async-frame $slot-forwarded") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.store") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-terminal] returned") != null);

    const wit = try emit_component_wit_for_tokens(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export tick: async func(when: u64)") != null);
}

test "component lowering accepts an explicit return after a scalar await" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    await(pending)
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-terminal] returned") != null);
}

test "component lowering resumes a second clocks await from a per-call frame" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(deadline u64) -> nil {
        \\    first Future<nil> = wait_for(deadline)
        \\    await(first)
        \\    second Future<nil> = wait_until(deadline)
        \\    await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]wait-for") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]wait-until") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "$frame-alloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $context-set-0") != null);

    const wit = try emit_component_wit_for_tokens(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "wait-for: async func(how-long: u64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "wait-until: async func(when: u64)") != null);
}

test "component lowering binds async frame metadata to the emitted body" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(deadline u64) -> nil {
        \\    first Future<nil> = wait_for(deadline)
        \\    await(first)
        \\    second Future<nil> = wait_until(deadline)
        \\    await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [async-frame] run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [async-state] 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [async-state] 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [async-cleanup] 3") != null);
}

test "component lowering resumes three sequential clocks awaits from one frame" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(deadline u64) -> nil {
        \\    first Future<nil> = wait_for(deadline)
        \\    await(first)
        \\    second Future<nil> = wait_until(deadline)
        \\    await(second)
        \\    third Future<nil> = wait_for(deadline)
        \\    await(third)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $third-host-call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 3\n          struct.set $async-frame $state") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(table $async-frames 0 (ref null $async-frame))") != null);
}

test "component lowering roots two-await frames in a GC table" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(deadline u64) -> nil {
        \\    first Future<nil> = wait_for(deadline)
        \\    await(first)
        \\    second Future<nil> = wait_until(deadline)
        \\    await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $async-frame (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(table $async-frames 0 (ref null $async-frame))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $async-frame") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "table.get $async-frames") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "global $frame-next") == null);

    const clear = std.mem.indexOf(u8, wat, "ref.null $async-frame\n    table.set $async-frames").?;
    const recycle = clear + std.mem.indexOf(u8, wat[clear..], "global.set $async-frame-free-head").?;
    try std.testing.expect(clear < recycle);
}

test "component lowering preserves scalar aliases across two clocks awaits" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(deadline u64) -> nil {
        \\    first_deadline u64 = deadline
        \\    first Future<nil> = wait_for(first_deadline)
        \\    await(first)
        \\    second_deadline u64 = first_deadline
        \\    second Future<nil> = wait_until(second_deadline)
        \\    await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]wait-until") != null);
}

test "component lowering replays a u64 literal local for sequential awaits" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    delay u64 = 41
        \\    first Future<nil> = wait_for(delay)
        \\    await(first)
        \\    second Future<nil> = wait_until(delay)
        \\    await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 41\n    call $first-host-call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $async-frame $slot-delay\n        call $second-host-call") != null);
}

test "component lowering carries scalar locals into the async frame layout" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    delay u64 = 41
        \\    first Future<nil> = wait_for(delay)
        \\    await(first)
        \\    second Future<nil> = wait_until(delay)
        \\    await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $slot-delay (mut i64))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 41\n\n    struct.new $async-frame") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $async-frame $slot-delay\n        call $second-host-call") != null);
}

test "component lowering replays a u64 parameter addition for sequential awaits" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    delay u64 = @add(input, 41)
        \\    first Future<nil> = wait_for(delay)
        \\    await(first)
        \\    second Future<nil> = wait_until(delay)
        \\    await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get 0\n    i64.const 41\n    i64.add\n    call $first-host-call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $async-frame $slot-delay\n        call $second-host-call") != null);
}

test "component lowering dispatches a scalar if branch to its selected await" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    if @eq(input, 41) {
        \\        first Future<nil> = wait_for(input)
        \\        await(first)
        \\        return
        \\    } else {
        \\        second Future<nil> = wait_until(input)
        \\        await(second)
        \\        return
        \\    }
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 41\n    i64.eq\n    if") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $first-host-call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $second-host-call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 1\n      struct.set $async-frame $state") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 2\n      struct.set $async-frame $state") != null);
}

test "component lowering joins scalar if branches at a shared await" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    if @eq(input, 27815) {
        \\        first Future<nil> = wait_for(input)
        \\        await(first)
        \\    } else {
        \\        second Future<nil> = wait_until(input)
        \\        await(second)
        \\    }
        \\    joined Future<nil> = wait_for(input)
        \\    await(joined)
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $third-host-call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 3\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $third-host-call") != null);
}

test "component lowering repeats a scalar await from an updating loop frame slot" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    remaining u64 = 2
        \\    loop {
        \\        pending Future<nil> = wait_for(input)
        \\        await(pending)
        \\        remaining = @sub(remaining, 1)
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\    }
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $slot-remaining (mut i64))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.sub") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.set $async-frame $slot-remaining") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $first-host-call") != null);
}

test "component lowering initializes a countdown loop frame slot from its parameter" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    remaining u64 = input
        \\    loop {
        \\        pending Future<nil> = wait_for(input)
        \\        await(pending)
        \\        remaining = @sub(remaining, 1)
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\    }
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get 0\n    local.get 0\n    struct.new $async-frame") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.set $async-frame $slot-remaining") != null);
}

test "component lowering initializes a countdown loop frame slot from a parameter addition" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    remaining u64 = @add(input, 1)
        \\    loop {
        \\        pending Future<nil> = wait_for(input)
        \\        await(pending)
        \\        remaining = @sub(remaining, 1)
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\    }
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get 0\n    i64.const 1\n    i64.add\n    struct.new $async-frame") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.set $async-frame $slot-remaining") != null);
}

test "component lowering feeds a countdown loop's updated frame slot to the next host await" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    remaining u64 = input
        \\    loop {
        \\        pending Future<nil> = wait_for(remaining)
        \\        await(pending)
        \\        remaining = @sub(remaining, 1)
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\    }
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $async-frame $slot-remaining\n    call $first-host-call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.set $async-frame $slot-remaining") != null);
}

test "component lowering terminates a guarded zero countdown before its first host await" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    remaining u64 = 0
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending Future<nil> = wait_for(remaining)
        \\        await(pending)
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    return
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $async-frame $slot-remaining\n    i64.eqz\n    if (result i32)\n      i32.const 0\n      call $context-set-0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $task-return") != null);
}

test "pinned cancellation lowering emits a terminal subtask cancellation state machine" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    @cancel(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[subtask-cancel]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $subtask\n    i32.const 2\n    i32.eq\n    if (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-cancel") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-drop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-terminal] cancelled") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "operation_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "request_cancel") == null);
}

test "component planning resolves a registered scalar unit descriptor" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"example:timers@0.1.0","member":"delay.sleep","effect":"async","params":["u32"],"result":"nil","resource":null,"canonical":{"core_params":["i32"],"core_results":[],"completion":"task-return","async_import_module":"example:async/delay@0.1.0","async_import_name":"[async-lower]sleep"},"wit":{"package":"example:async@0.1.0","interface":"timer-host","operation":"sleep-later","world":"timers","parameter":"milliseconds"}}
        \\]}
    ;
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);
    const source =
        \\sleep = @host_async_func("example:timers@0.1.0", "delay.sleep", (u32) -> nil)
        \\async run(delay u32) -> nil {
        \\    pending Future<nil> = sleep(delay)
        \\    await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var shared = try component_async_plan.ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer shared.deinit(std.testing.allocator);
    const plan = try clock_template_plan_from_shared(&shared);
    try std.testing.expectEqualStrings("delay.sleep", plan.descriptor.member);
    try std.testing.expectEqualStrings("run", plan.export_name);
    try std.testing.expectEqualStrings("delay", plan.parameter_name);
    try std.testing.expectEqual(.i32, plan.parameter_storage);

    const wat = try emit_component_core_wat(std.testing.allocator, plan, &shared.async_plan.?);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "\"example:async/delay@0.1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]sleep") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $async-run (func (param i32) (result i32)))") != null);

    const wit = try emit_component_wit_for_plan(std.testing.allocator, plan);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package example:async@0.1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "sleep-later: async func(milliseconds: u32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world timers") != null);
}

test "pinned wait-for lowering emits a Core async callback state machine" {
    try std.testing.expect(std.mem.startsWith(u8, core_wat, ";; Generated only"));
    try std.testing.expect(std.mem.indexOf(u8, core_wat, "(module") != null);
    try std.testing.expect(std.mem.indexOf(u8, core_wat, "[async-lower]wait-for") != null);
    try std.testing.expect(std.mem.indexOf(u8, core_wat, "[waitable-set-new]") != null);
    try std.testing.expect(std.mem.indexOf(u8, core_wat, "[callback][async-lift]run") != null);
    try std.testing.expect(std.mem.indexOf(u8, core_wat, "component-type") == null);
    try std.testing.expect(std.mem.indexOf(u8, core_wat, "\n(component") == null);
}

test "pinned wait-for lowering exposes its assembly WIT" {
    try std.testing.expect(std.mem.indexOf(u8, component_wit, "package wasi:clocks@0.3.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, component_wit, "wait-for: async func(how-long: u64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, component_wit, "export run: async func(how-long: u64)") != null);
}

test "pinned cli run result lowering exposes its assembly WIT" {
    const source =
        \\cli_run = @host_async_func("wasi:cli@0.3.0", "run.run", () -> Result<nil, nil>)
        \\async run() -> Result<nil, nil> {
        \\    pending Future<Result<nil, nil>> = cli_run()
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const wit = try emit_component_wit_for_tokens(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package wasi:cli@0.3.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "run: async func() -> result") != null);
}

test "cli result lowering derives exports from a structured source program" {
    const source =
        \\command = @host_async_func("wasi:cli@0.3.0", "run.run", () -> Result<nil, nil>)
        \\async launch() -> Result<nil, nil> {
        \\    outcome Future<Result<nil, nil>> = command()
        \\    return await(outcome)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]launch") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]launch") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "$frame-alloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 12") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $subtask i32.const 2 i32.eq") != null);

    const wit = try emit_component_wit_for_tokens(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export launch: async func() -> result") != null);
}

test "cli result lowering permits an awaited unit Result Ok branch" {
    const source =
        \\cli_run = @host_async_func("wasi:cli@0.3.0", "run.run", () -> Result<nil, nil>)
        \\async run() -> Result<nil, nil> {
        \\    pending Future<Result<nil, nil>> = cli_run()
        \\    replied Result<nil, nil> = await(pending)
        \\    if @is(replied, Ok) {
        \\        return Err()
        \\    }
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.eqz") != null);
}

test "cli result lowering rejects a direct future return" {
    const source =
        \\cli_run = @host_async_func("wasi:cli@0.3.0", "run.run", () -> Result<nil, nil>)
        \\async other() -> Result<nil, nil> {
        \\    pending Future<Result<nil, nil>> = cli_run()
        \\    return pending
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3WaitForComponent, emit_component_wit_for_tokens(std.testing.allocator, tokens));
}

test "scalar Result lowering emits canonical payload words" {
    try std.testing.expect(std.mem.indexOf(u8, scalar_result_core_wat, "i64.const [scalar-result-frame-bytes]") != null);
    try std.testing.expect(std.mem.indexOf(u8, scalar_result_core_wat, "i32.const [scalar-result-frame-bytes]") != null);
    try std.testing.expect(std.mem.indexOf(u8, scalar_result_budget_runtime, "(func (export \"byte-budget-limit\")") != null);

    const source =
        \\result_run = @host_async_func("do:result-probe@0.1.0", "run", (i32) -> Result<i32, i32>)
        \\async run(value i32) -> Result<i32, i32> {
        \\    pending Future<Result<i32, i32>> = result_run(value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $task-return (func (param i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[result-tag]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.load offset=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[result-payload]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $task-return") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [async-frame-budget-bytes] 20") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "global $async-byte-budget-used") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 20\n    call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 20\n    call $async-byte-budget-release") != null);

    const wit = try emit_component_wit_for_tokens(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "run: async func(value: s32) -> result<s32, s32>") != null);
}

test "scalar Result WIT type follows source Result arms" {
    const source = p3_async_manifest.scalar_result_source_types("Result<u8,u8>") orelse return error.TestUnexpectedResult;
    const wit = try wit_result_type(std.testing.allocator, source);
    defer std.testing.allocator.free(wit);
    try std.testing.expectEqualStrings("result<u8, u8>", wit);
}

test "scalar Result lowering checks immediate host completion before joining" {
    const source =
        \\result_run = @host_async_func("do:result-probe@0.1.0", "run", (i32) -> Result<i32, i32>)
        \\async run(value i32) -> Result<i32, i32> {
        \\    pending Future<Result<i32, i32>> = result_run(value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $subtask\n    i32.const 2\n    i32.eq\n    if (result i32)") != null);
}

test "scalar Result cancellation emits terminal ack cleanup" {
    const source =
        \\result_run = @host_async_func("do:result-probe@0.1.0", "run", (i32) -> Result<i32, i32>)
        \\async run(value i32) -> nil {
        \\    pending Future<Result<i32, i32>> = result_run(value)
        \\    @cancel(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[subtask-cancel]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-cancel") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-drop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $task-return (func))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $task-return") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-terminal] cancelled") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $context-set-0") != null);

    const wit = try emit_component_wit_for_tokens(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export run: async func(value: s32);") != null);
}

test "scalar Result cancellation rejects a non-nil root result" {
    const source =
        \\result_run = @host_async_func("do:result-probe@0.1.0", "run", (i32) -> Result<i32, i32>)
        \\async run(value i32) -> Result<i32, i32> {
        \\    pending Future<Result<i32, i32>> = result_run(value)
        \\    @cancel(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3WaitForComponent, emit_component_wit_for_tokens(std.testing.allocator, tokens));
}
