const probe = @import("build/gc_marshal_text_probe.zig");

pub fn main(init: @import("std").process.Init) !void {
    return probe.main(init);
}
