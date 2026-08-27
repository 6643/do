const std = @import("std");
const generated_text = @import("codegen_text.zig");
const plan_mod = @import("codegen_component_async_host_arg_plan.zig");

const canonical_wat = @embedFile("async_host_scalar_argument_component_template.wat");

pub fn emit_component_wat(allocator: std.mem.Allocator, plan: plan_mod.AsyncHostScalarArgPlan) ![]u8 {
    try plan.shape.validate();
    if (!std.mem.eql(u8, plan.root_name, "run") or
        !std.mem.eql(u8, plan.helper_name, "helper") or
        !std.mem.eql(u8, plan.host_locator, "do:async-call-arg-probe/host@0.1.0") or
        !std.mem.eql(u8, plan.host_member, "work") or
        !std.mem.eql(u8, plan.async_import_module, "do:async-call-arg-probe/host@0.1.0") or
        !std.mem.eql(u8, plan.async_import_name, "[async-lower]work") or
        plan.argument_value != 7) return error.UnsupportedP3AsyncHostArgComponent;
    return generated_text.alloc_block(allocator, 0, canonical_wat);
}

pub fn emit_component_wit(allocator: std.mem.Allocator) ![]u8 {
    return generated_text.alloc_block(allocator, 0,
                \\package do:async-call-arg-probe@0.1.0;
        \\
        \\interface host {
        \\  work: async func(value: u32);
        \\}
        \\
        \\world probe {
        \\  import host;
        \\  export run: async func();
        \\}
        \\
        ,
    );
}
