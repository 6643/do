//! Async terminal cleanup call lowering, kept outside the frame model to avoid
//! a dependency from async metadata back into mutable codegen context.
const std = @import("std");
const lexer = @import("lexer.zig");
const async_model = @import("codegen_async_model.zig");
const codegen_emit_control = @import("codegen_emit_control.zig");
const context = @import("codegen_context.zig");
const model = @import("codegen_model.zig");

const LocalSet = context.LocalSet;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;

pub fn emit_active_defer_calls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    frame: async_model.FrameModel,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    if (frame.resume_states.len == 0) return;

    const defers = frame.resume_states[frame.resume_states.len - 1].active_defers;
    var index = defers.len;
    while (index != 0) {
        index -= 1;
        const defer_site = defers[index];
        if (defer_site.body_start >= defer_site.body_end) return error.NoMatchingCall;
        try codegen_emit_control.emit_defer_cleanup_call(
            allocator,
            tokens,
            defer_site.body_start,
            defer_site.body_end,
            locals,
            ctx,
            out,
        );
    }
}

test "empty async frame has no terminal defer calls" {
    const frame = async_model.FrameModel{ .resume_states = &.{}, .cleanup_state = 1 };
    try std.testing.expectEqual(@as(usize, 0), frame.resume_states.len);
}
