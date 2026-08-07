const std = @import("std");
const p3_async_manifest = @import("p3_async_manifest.zig");
const future_owned_plan = @import("codegen_component_future_owned_plan.zig");

const future_owned_wat = @embedFile("future_owned_component_template.wat");

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    plan: future_owned_plan.FutureOwnedPlan,
) ![]u8 {
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3OwnedFutureComponent) {
        .future_owned_resource => |value| value,
        else => return error.UnsupportedP3OwnedFutureComponent,
    };
    if (shape.payload_offset != plan.payload_offset or
        shape.resource_offset != plan.resource_offset or
        shape.presence_offset != plan.presence_offset or
        !std.mem.eql(u8, shape.drop_import, plan.drop_import)) return error.UnsupportedP3OwnedFutureComponent;
    return allocator.dupe(u8, future_owned_wat);
}

pub fn emit_component_wit(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(u8,
        "package do:future-owned-canonical@0.1.0;\n\n" ++
            "interface source {\n  resource ticket {}\n  read: func() -> future<own<ticket>>;\n}\n\n" ++
            "interface probe {\n  run: async func(mode: u32);\n}\n\n" ++
            "world future-owned-canonical {\n  import source;\n  export probe;\n}\n",
    );
}
