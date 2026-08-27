const probe = @import("build/gc_marshal_u32_lift_probe.zig");

pub fn main(init: @import("std").process.Init) !void {
    return probe.main(init);
}
