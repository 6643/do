const std = @import("std");
const parser = @import("parser.zig");

pub fn validateStart(program: parser.Program) !void {
    var start_count: usize = 0;
    var start_sig: ?parser.FuncSig = null;

    for (program.func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, "start")) continue;
        start_count += 1;
        if (start_sig == null) start_sig = sig;
    }

    if (start_count == 0) return error.MissingStartEntry;
    if (start_count > 1) return error.DuplicateStartEntry;
    if (start_sig == null) return error.MissingStartEntry;

    const sig = start_sig.?;
    if (sig.param_min != 0) return error.InvalidStartEntrySig;
    if (sig.param_max == null) return error.InvalidStartEntrySig;
    if (sig.param_max.? != 0) return error.InvalidStartEntrySig;
    if (sig.return_arity != 0) return error.InvalidStartEntrySig;
}
