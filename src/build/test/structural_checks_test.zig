const std = @import("std");
const checks = @import("structural_checks.zig");

test "module boundary checker rejects legacy facade and peer import" {
    const source =
        \\const legacy = @import("sema_control.zig");
        \\const peer = @import("sema_field_checks.zig");
    ;
    try std.testing.expectEqual(
        checks.ModuleViolation.legacy_facade_import,
        checks.check_module_source("src/build/sema_control_flow.zig", source),
    );
}

test "module boundary checker accepts leaf-owned imports" {
    const source =
        \\const tokens = @import("sema_tokens.zig");
        \\const support = @import("sema_function_support.zig");
    ;
    try std.testing.expectEqual(
        @as(?checks.ModuleViolation, null),
        checks.check_module_source("src/build/sema_control_flow.zig", source),
    );
}

test "generated text checker rejects positional placeholders" {
    const source =
        \\try generated_text.append_fmt(allocator, "i32.const {d}", .{value});
    ;
    try std.testing.expectEqual(
        checks.GeneratedTextViolation.unindexed_placeholder,
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker accepts named placeholders" {
    const source =
        \\try generated_text.append_fmt(allocator, "i32.const {[value]d}", .{ .value = value });
    ;
    try std.testing.expectEqual(
        @as(?checks.GeneratedTextViolation, null),
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker accepts escaped raw template braces" {
    const source =
        \\try generated_text.append_fmt_block(allocator, out, 0,
        \\    \\use types.{{error-code}};
        \\    \\  record value {{ field: u32 }};
        \\    \\
        \\    , .{ .value = value });
    ;
    try std.testing.expectEqual(
        @as(?checks.GeneratedTextViolation, null),
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker accepts an escaped backslash in a single-line format" {
    const source = "try generated_text.alloc_fmt(allocator, \"\\\\\\\\{[value]X:0>2}\", .{ .value = value });";
    try std.testing.expectEqual(
        @as(?checks.GeneratedTextViolation, null),
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker rejects a raw multiline formatter" {
    const source =
        \\try generated_text.append_fmt(allocator, out, format,
        \\    \\i32.const {[value]d}
        \\    \\
        \\    , .{ .value = value });
    ;
    try std.testing.expectEqual(
        checks.GeneratedTextViolation.raw_template_formatter,
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker bounds trailing-comma formatter calls" {
    const source =
        \\const name = switch (flag) {
        \\    .a => generated_text.alloc_fmt(
        \\        allocator,
        \\        "name={[value]d}",
        \\        .{ .value = value },
        \\    ),
        \\};
        \\const body = generated_text.alloc_fmt_block(
        \\    allocator,
        \\    2,
        \\    \\\\  ;; generated body
        \\    \\\\  ;; still a block
        \\    \\\\
        \\    ,
        \\    .{ .value = value },
        \\);
    ;
    try std.testing.expectEqual(
        @as(?checks.GeneratedTextViolation, null),
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker ignores parentheses inside raw block lines" {
    const source =
        \\try generated_text.append_block(allocator, out, 4,
        \\    \\    i32.const 27815)
        \\    \\)
        \\);
    ;
    try std.testing.expectEqual(
        @as(?checks.GeneratedTextViolation, null),
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker ignores unrelated allocPrint" {
    const source =
        \\const value = std.fmt.allocPrint(allocator, "{s}", .{ .value = "x" });
        \\fn append_fmt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) !void {
        \\    try generated_text.append_fmt(allocator, out, format, args);
        \\}
    ;
    try std.testing.expectEqual(
        @as(?checks.GeneratedTextViolation, null),
        checks.check_generated_text_source("src/wit/emit_do.zig", source),
    );
}

test "generated text checker rejects formatter implementation" {
    const source =
        \\fn append_fmt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) !void {
        \\    return std.fmt.allocPrint(allocator, format, args);
        \\}
    ;
    try std.testing.expectEqual(
        checks.GeneratedTextViolation.duplicate_formatter,
        checks.check_generated_text_source("src/wit/emit_do.zig", source),
    );
}

test "generated text checker accepts formatted block templates" {
    const source =
        \\const metadata = try generated_text.alloc_fmt_block(
        \\    allocator,
        \\    2,
        \\    \\\\
        \\    \\\\  ;; value={[value]d}
        \\    \\\\
        \\    ,
        \\    .{ .value = value },
        \\);
    ;
    try std.testing.expectEqual(
        @as(?checks.GeneratedTextViolation, null),
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker accepts allocated block string templates" {
    const source =
        \\const body = try generated_text.alloc_fmt_block(allocator, 0, "one line {[value]d}", .{ .value = value });
    ;
    try std.testing.expectEqual(
        @as(?checks.GeneratedTextViolation, null),
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker rejects adjacent escaped newlines in appendSlice" {
    const source =
        \\try out.appendSlice(allocator, "first\n\nsecond");
    ;
    try std.testing.expectEqual(
        checks.GeneratedTextViolation.multi_line_append_slice,
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}

test "generated text checker accepts spaced escaped newlines in appendSlice" {
    const source =
        \\try out.appendSlice(allocator, "first\\n  second\\n");
    ;
    try std.testing.expectEqual(
        @as(?checks.GeneratedTextViolation, null),
        checks.check_generated_text_source("src/build/example.zig", source),
    );
}
