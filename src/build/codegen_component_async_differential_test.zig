const std = @import("std");
const lexer = @import("lexer.zig");
const bounded_shape = @import("codegen_component_async_shape.zig");
const call_plan = @import("codegen_component_async_call_plan.zig");
const call_emitter = @import("codegen_component_async_call.zig");
const host_plan = @import("codegen_component_async_host_arg_plan.zig");
const host_emitter = @import("codegen_component_async_host_arg.zig");

const Kind = enum { call, host };

const Case = struct {
    source: []const u8,
    kind: Kind,
    mode: bounded_shape.BoundedAsyncMode,
    frame_size: u32,
    argument_offset: ?u32,
    wat_sha256: []const u8,
    wit_sha256: []const u8,
    markers: []const []const u8,
};

const child_unit_markers = [_][]const u8{
    "[guest-async-parent-resume]",
    "[guest-async-child-drop]",
    "[guest-async-root-terminal]",
    "[guest-async-child]",
};

const child_scalar_markers = [_][]const u8{
    "[guest-async-parent-resume]",
    "[guest-async-arg-load]",
    "[guest-async-child-drop]",
    "[guest-async-root-terminal]",
    "[guest-async-child]",
    "[guest-async-arg-store]",
};

const inline_unit_markers = [_][]const u8{
    "[guest-async-parent-resume]",
    "[guest-async-child-drop]",
    "[guest-async-root-terminal]",
    "[guest-async-root-cancel]",
    "[guest-async-cancel-child]",
    "[guest-async-child]",
    "[guest-inline-resume]",
    "[guest-inline-helper]",
};

const inline_scalar_markers = [_][]const u8{
    "[guest-async-parent-resume]",
    "[guest-async-child-drop]",
    "[guest-async-root-terminal]",
    "[guest-async-root-cancel]",
    "[guest-async-cancel-child]",
    "[guest-async-child]",
    "[guest-async-arg-store]",
    "[guest-async-arg-load]",
    "[guest-inline-resume]",
    "[guest-inline-arg-load]",
    "[guest-inline-helper]",
    "[guest-inline-arg-store]",
};

const host_scalar_markers = [_][]const u8{
    "[guest-async-child-drop]",
    "[guest-async-child-drop]",
    "[guest-async-waitable-drop]",
    "[guest-async-context-clear]",
    "[guest-async-frame-free]",
    "[guest-async-parent-resume]",
    "[guest-async-arg-load]",
    "[guest-async-arg-store]",
    "[guest-async-host-arg]",
    "[guest-async-parent-resume]",
};

const inline_unit_source =
    \\work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
    \\helper() -> nil {
    \\    pending Future<nil> = work()
    \\    @await(pending)
    \\}
    \\run() -> nil {
    \\    helper()
    \\    child Future<nil> = @async(helper())
    \\    @await(child)
    \\}
    \\start() {}
;

const child_unit_case = Case{
    .source = @embedFile("test/check/441_async_call_component.do"),
    .kind = .call,
    .mode = .child,
    .frame_size = 16,
    .argument_offset = null,
    .wat_sha256 = "bec944caece221821f43a79041e2989281f9f9b90d59547f9348ef641e1b2e03",
    .wit_sha256 = "ecf47e1e33b3a0d14761a1341f3b749f4ba072051c018083db2d5cda356c101f",
    .markers = child_unit_markers[0..],
};

const child_scalar_case = Case{
    .source = @embedFile("test/compile_ok/466_async_call_scalar_argument_component.do"),
    .kind = .call,
    .mode = .child,
    .frame_size = 20,
    .argument_offset = 12,
    .wat_sha256 = "7402916ce09060ca63e792498dc1523923b6a1545004d91c61f1a037496f2fc1",
    .wit_sha256 = "ecf47e1e33b3a0d14761a1341f3b749f4ba072051c018083db2d5cda356c101f",
    .markers = child_scalar_markers[0..],
};

const inline_unit_case = Case{
    .source = inline_unit_source,
    .kind = .call,
    .mode = .inline_call,
    .frame_size = 16,
    .argument_offset = null,
    .wat_sha256 = "0e362d90a30c38de5e5900783b7474ddac05292f50c402a20786c0a940598dcc",
    .wit_sha256 = "ecf47e1e33b3a0d14761a1341f3b749f4ba072051c018083db2d5cda356c101f",
    .markers = inline_unit_markers[0..],
};

const inline_scalar_case = Case{
    .source = @embedFile("test/compile_ok/477_async_call_inline_scalar_argument_component.do"),
    .kind = .call,
    .mode = .inline_call,
    .frame_size = 20,
    .argument_offset = 12,
    .wat_sha256 = "7edf6a66095c3c24b8c5440ebcad5a7f5dfcc5fea3c943a8e4d28453bb96fe83",
    .wit_sha256 = "ecf47e1e33b3a0d14761a1341f3b749f4ba072051c018083db2d5cda356c101f",
    .markers = inline_scalar_markers[0..],
};

const host_scalar_case = Case{
    .source = @embedFile("test/compile_ok/490_async_host_scalar_argument_component.do"),
    .kind = .host,
    .mode = .host_scalar,
    .frame_size = 20,
    .argument_offset = 12,
    .wat_sha256 = "e9e2330a75430b569b538d15d676d92492c952f89c5cc135a38343670da01553",
    .wit_sha256 = "b9f5f8355e87231317ec05cccf692ee465c6f339bd509640aedc196e58f81e61",
    .markers = host_scalar_markers[0..],
};

test "bounded async differential output remains pinned" {
    try verify_case(child_unit_case);
    try verify_case(child_scalar_case);
    try verify_case(inline_unit_case);
    try verify_case(inline_scalar_case);
    try verify_case(host_scalar_case);
}

fn verify_case(case: Case) !void {
    const tokens = try lexer.tokenize(std.testing.allocator, case.source);
    defer std.testing.allocator.free(tokens);

    switch (case.kind) {
        .call => {
            var plan = try call_plan.analyze(std.testing.allocator, tokens);
            defer plan.deinit(std.testing.allocator);
            try expect_shape(plan.shape, case);
            const wat = try call_emitter.emit_component_wat(std.testing.allocator, plan);
            defer std.testing.allocator.free(wat);
            const wit = try call_emitter.emit_component_wit(std.testing.allocator);
            defer std.testing.allocator.free(wit);
            try expect_output(wat, wit, case);
        },
        .host => {
            var plan = try host_plan.analyze(std.testing.allocator, tokens);
            defer plan.deinit(std.testing.allocator);
            try expect_shape(plan.shape, case);
            const wat = try host_emitter.emit_component_wat(std.testing.allocator, plan);
            defer std.testing.allocator.free(wat);
            const wit = try host_emitter.emit_component_wit(std.testing.allocator);
            defer std.testing.allocator.free(wit);
            try expect_output(wat, wit, case);
        },
    }
}

fn expect_shape(shape: bounded_shape.BoundedAsyncShape, case: Case) !void {
    try shape.validate();
    try std.testing.expectEqual(case.mode, shape.mode);
    try std.testing.expectEqual(@as(u32, 4), shape.frame.alignment);
    try std.testing.expectEqual(@as(u32, 0), shape.frame.waitable_set_offset);
    try std.testing.expectEqual(@as(u32, 4), shape.frame.active_subtask_offset);
    try std.testing.expectEqual(@as(u32, 8), shape.frame.phase_offset);
    try std.testing.expectEqual(case.frame_size, shape.frame.size);
    try std.testing.expectEqual(case.argument_offset, shape.frame.u32_argument_offset);
}

fn expect_output(wat: []const u8, wit: []const u8, case: Case) !void {
    const wat_hash = sha256_hex(wat);
    const wit_hash = sha256_hex(wit);
    try std.testing.expectEqualStrings(case.wat_sha256, &wat_hash);
    try std.testing.expectEqualStrings(case.wit_sha256, &wit_hash);

    var actual_markers: [32][]const u8 = undefined;
    const actual_count = try collect_guest_markers(wat, &actual_markers);
    try std.testing.expectEqual(case.markers.len, actual_count);
    for (case.markers, 0..) |expected, index| {
        try std.testing.expectEqualStrings(expected, actual_markers[index]);
    }
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]helper") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]helper") == null);
}

fn collect_guest_markers(wat: []const u8, output: *[32][]const u8) !usize {
    var count: usize = 0;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, wat, cursor, "[guest-")) |start| {
        const end = std.mem.indexOfPos(u8, wat, start, "]") orelse return error.MissingMarkerEnd;
        if (count == output.len) return error.TooManyMarkers;
        output[count] = wat[start .. end + 1];
        count += 1;
        cursor = end + 1;
    }
    return count;
}

fn sha256_hex(bytes: []const u8) [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var encoded: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 = undefined;
    for (digest, 0..) |byte, index| {
        encoded[index * 2] = hex_digit(byte >> 4);
        encoded[index * 2 + 1] = hex_digit(byte & 0x0f);
    }
    return encoded;
}

fn hex_digit(value: u8) u8 {
    return if (value < 10) '0' + value else 'a' + (value - 10);
}
