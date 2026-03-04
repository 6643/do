const std = @import("std");
const parser = @import("parser.zig");

pub fn emitWat(allocator: std.mem.Allocator, program: parser.Program) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\(module
        \\  ;; do compiler bootstrap output
        \\  ;; source_len={d}
        \\  ;; token_count={d}
        \\  ;; top_level_count={d}
        \\)
        \\
    ,
        .{
            program.source_len,
            program.token_count,
            program.top_level_count,
        },
    );
}
