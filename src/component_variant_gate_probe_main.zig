const probe = @import("build/component_variant_gate_probe.zig");

pub fn main(init: @import("std").process.Init) !void {
    return probe.main(init);
}
