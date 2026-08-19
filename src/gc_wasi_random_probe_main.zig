const probe = @import("build/gc_wasi_random_probe.zig");

pub fn main(init: @import("std").process.Init) !void {
    return probe.main(init);
}
