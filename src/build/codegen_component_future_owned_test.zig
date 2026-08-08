const std = @import("std");
const lexer = @import("lexer.zig");
const plan = @import("codegen_component_future_owned_plan.zig");
const emitter = @import("codegen_component_future_owned.zig");

const positive_source =
    \\read = @host_func("do:future-owned-canonical/source@0.1.0", "read", () -> Future<Ticket>)
    \\Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })
    \\run(mode u32) -> nil {
    \\    pending Future<Ticket> = read()
    \\    ticket Ticket = @await(pending)
    \\}
    \\start() {}
;

const expected_wit =
    "package do:future-owned-canonical@0.1.0;\n\n" ++
    "interface source {\n  resource ticket {}\n  read: func() -> future<own<ticket>>;\n}\n\n" ++
    "interface probe {\n  run: async func(mode: u32);\n}\n\n" ++
    "world future-owned-canonical {\n  import source;\n  export probe;\n}\n";

test "future-owned emitter emits the measured private frame markers" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    var lowering = try plan.analyze(std.testing.allocator, tokens);
    defer lowering.deinit(std.testing.allocator);
    const wat = try emitter.emit_component_wat(std.testing.allocator, lowering);
    defer std.testing.allocator.free(wat);
    for ([_][]const u8{
        "[future-owned-payload]",
        "[future-owned-ticket-present]",
        "[future-owned-transfer]",
        "[future-owned-resource-drop]",
        "[future-owned-cancel]",
        "[task-return]run",
        "[resource-drop]ticket",
    }) |marker| {
        try std.testing.expect(std.mem.indexOf(u8, wat, marker) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]helper") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]helper") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "future<borrow<") == null);
}

test "future-owned emitter emits the pinned WIT sidecar" {
    const wit = try emitter.emit_component_wit(std.testing.allocator);
    defer std.testing.allocator.free(wit);
    try std.testing.expectEqualStrings(expected_wit, wit);
}
