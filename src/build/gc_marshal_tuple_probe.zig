//! Manifest-backed Tuple byte-list lift compiler route probe.

const std = @import("std");
const emitter = @import("codegen_gc_wit_marshal.zig");
const lexer = @import("lexer.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3 and args.len != 4) return error.InvalidTupleMarshalProbeArgs;
    const is_list_tuple_lower = std.mem.indexOf(u8, args[1], "list-tuple-lower") != null;
    const is_list_tuple_lift = std.mem.indexOf(u8, args[1], "list-tuple-lift") != null;
    const is_u32_list = std.mem.indexOf(u8, args[1], "tuple-u32-list-lift") != null;
    const source = if (is_list_tuple_lower)
        @embedFile("test/compile_ok/686_gc_wit_list_tuple_lower_host_boundary.do")
    else if (is_list_tuple_lift)
        @embedFile("test/compile_ok/687_gc_wit_list_tuple_lift_host_boundary.do")
    else if (is_u32_list)
        @embedFile("test/compile_ok/685_gc_wit_tuple_u32_list_lift_host_boundary.do")
    else
        @embedFile("test/compile_ok/684_gc_wit_tuple_byte_list_lift_host_boundary.do");
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    const wat = try emitter.emit_module(
        init.io,
        allocator,
        if (args.len == 4) args[3] else ".",
        if (is_list_tuple_lower)
            emitter.list_tuple_lower_descriptor
        else if (is_list_tuple_lift)
            emitter.list_tuple_lift_descriptor
        else if (is_u32_list)
            emitter.tuple_u32_list_lift_descriptor
        else
            emitter.tuple_byte_list_lift_descriptor,
        tokens,
    );
    defer allocator.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = wat });
}
