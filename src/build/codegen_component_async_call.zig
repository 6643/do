const std = @import("std");
const call_plan = @import("codegen_component_async_call_plan.zig");

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    plan: call_plan.GuestAsyncCallPlan,
) ![]u8 {
    const template = if (plan.inline_helper_call)
        inline_async_call_component_wat
    else
        async_call_component_wat;
    var wat = try allocator.dupe(u8, template);
    errdefer allocator.free(wat);
    wat = try replace_all(allocator, wat, "__ASYNC_IMPORT_MODULE__", plan.async_import_module);
    wat = try replace_all(allocator, wat, "__ASYNC_IMPORT_NAME__", plan.async_import_name);
    wat = try replace_all(allocator, wat, "__ROOT__", plan.root_name);
    wat = try replace_all(allocator, wat, "__FRAME_SIZE__", if (plan.argument_value != null) "20" else "16");
    wat = try replace_all(allocator, wat, "__HELPER_ARGUMENT_PARAM__", if (plan.argument_value != null) " (param $value i32)" else "");

    const argument_store = if (plan.argument_value != null)
        "    ;; [guest-async-arg-store]\n    local.get $frame\n    i32.const 12\n    i32.add\n    local.get $value\n    i32.store\n"
    else
        "";
    wat = try replace_all(allocator, wat, "__ARGUMENT_STORE__", argument_store);

    const argument_load = if (plan.argument_value != null)
        "    ;; [guest-async-arg-load]\n    local.get $frame\n    i32.const 12\n    i32.add\n    i32.load\n    drop\n"
    else
        "";
    wat = try replace_all(allocator, wat, "__ARGUMENT_LOAD__", argument_load);

    const argument_value = if (plan.argument_value) |value|
        try std.fmt.allocPrint(allocator, "    i32.const {d}\n", .{value})
    else
        try allocator.dupe(u8, "");
    defer allocator.free(argument_value);
    wat = try replace_all(allocator, wat, "__ROOT_ARGUMENT__", argument_value);
    return wat;
}

pub fn emit_component_wit(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(
        u8,
        "package do:generic-async-call-probe@0.1.0;\n\n" ++
            "interface host {\n  work: async func();\n}\n\n" ++
            "world probe {\n  import host;\n  export run: async func();\n}\n",
    );
}

fn replace_all(
    allocator: std.mem.Allocator,
    input: []u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    if (needle.len == 0) return error.InvalidTemplate;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var remainder = input;
    while (std.mem.indexOf(u8, remainder, needle)) |idx| {
        try out.appendSlice(allocator, remainder[0..idx]);
        try out.appendSlice(allocator, replacement);
        remainder = remainder[idx + needle.len ..];
    }
    try out.appendSlice(allocator, remainder);
    allocator.free(input);
    return try out.toOwnedSlice(allocator);
}

const async_call_component_wat =
    \\(module
    \\  ;; Root-owned local continuation for one exact @async(helper()) edge.
    \\  (type $async-lower-work (func (result i32)))
    \\  (type $task-return (func))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $waitable-set-wait (func (param i32 i32) (result i32)))
    \\  (type $waitable-set-poll (func (param i32 i32) (result i32)))
    \\  (type $waitable-set-drop (func (param i32)))
    \\  (type $subtask-cancel (func (param i32) (result i32)))
    \\  (type $subtask-drop (func (param i32)))
    \\  (type $context-get (func (result i32)))
    \\  (type $context-set (func (param i32)))
    \\  (type $thread-yield (func (result i32)))
    \\  (type $async-run (func (result i32)))
    \\  (type $async-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\
    \\  (import "__ASYNC_IMPORT_MODULE__" "__ASYNC_IMPORT_NAME__"
    \\    (func $host-work (type $async-lower-work)))
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-return)))
    \\  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $task-return)))
    \\  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $task-return)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $waitable-set-wait)))
    \\  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $waitable-set-poll)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-set-drop)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[thread-yield]" (func $thread-yield (type $thread-yield)))
    \\  (import "$root" "[subtask-drop]" (func $subtask-drop (type $subtask-drop)))
    \\  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $subtask-cancel)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (type $context-get)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (type $context-set)))
    \\  (import "[export]$root" "[task-return]__ROOT__" (func $task-return-root (type $task-return)))
    \\
    \\  (memory (export "memory") 1)
    \\  ;; root frame: waitable set @0, host subtask @4, helper state @8, optional scalar @12.
    \\  (global $frame-next (mut i32) (i32.const 1024))
    \\
    \\  (func $frame-alloc (result i32) (local $frame i32)
    \\    global.get $frame-next
    \\    local.tee $frame
    \\    i32.const __FRAME_SIZE__
    \\    i32.add
    \\    global.set $frame-next
    \\    local.get $frame
    \\  )
    \\
    \\  (func $frame-free (param $frame i32)
    \\    local.get $frame
    \\    global.set $frame-next
    \\  )
    \\
    \\  (func $helper-resume (param $frame i32)
    \\    ;; [guest-async-parent-resume]
    \\__ARGUMENT_LOAD__
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    i32.const 2
    \\    i32.ne
    \\    if
    \\      ;; [guest-async-child-drop]
    \\      local.get $frame
    \\      i32.const 4
    \\      i32.add
    \\      i32.load
    \\      i32.const 4
    \\      i32.shr_u
    \\      call $subtask-drop
    \\    end
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-set-drop
    \\    i32.const 0
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $frame-free
    \\    ;; [guest-async-root-terminal]
    \\    call $task-return-root
    \\  )
    \\
    \\  (func $helper (param $frame i32)__HELPER_ARGUMENT_PARAM__ (result i32) (local $subtask i32)
    \\    ;; [guest-async-child]
    \\__ARGUMENT_STORE__
    \\    call $host-work
    \\    local.set $subtask
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    local.get $subtask
    \\    i32.store
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $helper-resume
    \\      i32.const 0
    \\    else
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      local.get $frame
    \\      i32.load
    \\      call $waitable-join
    \\      local.get $frame
    \\      i32.load
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end
    \\  )
    \\
    \\  (func (export "[async-lift]__ROOT__") (type $async-run) (local $frame i32)
    \\    call $frame-alloc
    \\    local.set $frame
    \\    local.get $frame
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $waitable-set-new
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.const 2
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.const 1
    \\    i32.store
    \\    local.get $frame
    \\__ROOT_ARGUMENT__
    \\    call $helper
    \\  )
    \\
    \\  (func (export "[callback][async-lift]__ROOT__") (type $async-callback)
    \\    (local $frame i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get 0
    \\    i32.const 1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get 2
    \\      i32.const 2
    \\      i32.eq
    \\      if (result i32)
    \\        local.get $frame
    \\        call $helper-resume
    \\        i32.const 0
    \\      else
    \\        unreachable
    \\        i32.const 0
    \\      end
    \\    else
    \\      unreachable
    \\      i32.const 0
    \\    end
    \\  )
    \\
    \\  (func (export "cabi_realloc") (type $cabi-realloc)
    \\    unreachable
    \\  )
    \\  (func (export "_initialize"))
    \\)
;

const inline_async_call_component_wat =
    \\(module
    \\  ;; Root-owned continuation for one bounded inline helper followed by one child.
    \\  (type $async-lower-work (func (result i32)))
    \\  (type $task-return (func))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $waitable-set-drop (func (param i32)))
    \\  (type $subtask-drop (func (param i32)))
    \\  (type $context-get (func (result i32)))
    \\  (type $context-set (func (param i32)))
    \\  (type $async-run (func (result i32)))
    \\  (type $async-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\
    \\  (import "__ASYNC_IMPORT_MODULE__" "__ASYNC_IMPORT_NAME__"
    \\    (func $host-work (type $async-lower-work)))
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-return)))
    \\  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $task-return)))
    \\  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $task-return)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-set-drop)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[subtask-drop]" (func $subtask-drop (type $subtask-drop)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (type $context-get)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (type $context-set)))
    \\  (import "[export]$root" "[task-return]__ROOT__" (func $task-return-root (type $task-return)))
    \\
    \\  (memory (export "memory") 1)
    \\  ;; frame: waitable set @0, current host future @4, phase @8, optional scalar @12.
    \\  (global $frame-next (mut i32) (i32.const 1024))
    \\
    \\  (func $frame-alloc (result i32) (local $frame i32)
    \\    global.get $frame-next
    \\    local.tee $frame
    \\    i32.const __FRAME_SIZE__
    \\    i32.add
    \\    global.set $frame-next
    \\    local.get $frame
    \\  )
    \\
    \\  (func $frame-free (param $frame i32)
    \\    local.get $frame
    \\    global.set $frame-next
    \\  )
    \\
    \\  (func $root-resume (param $frame i32)
    \\    ;; [guest-async-parent-resume]
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.const 3
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    i32.const 2
    \\    i32.ne
    \\    if
    \\      ;; [guest-async-child-drop]
    \\      local.get $frame
    \\      i32.const 4
    \\      i32.add
    \\      i32.load
    \\      i32.const 4
    \\      i32.shr_u
    \\      call $subtask-drop
    \\    end
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-set-drop
    \\    i32.const 0
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $frame-free
    \\    ;; [guest-async-root-terminal]
    \\    call $task-return-root
    \\  )
    \\
    \\  (func $start-child (param $frame i32) (result i32) (local $subtask i32)
    \\    ;; [guest-async-child]
    \\    call $host-work
    \\    local.set $subtask
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    local.get $subtask
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.const 2
    \\    i32.store
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $root-resume
    \\      i32.const 0
    \\    else
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      local.get $frame
    \\      i32.load
    \\      call $waitable-join
    \\      local.get $frame
    \\      i32.load
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end
    \\  )
    \\
    \\  (func $inline-resume (param $frame i32) (result i32)
    \\    ;; [guest-inline-resume]
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    i32.const 2
    \\    i32.ne
    \\    if
    \\      local.get $frame
    \\      i32.const 4
    \\      i32.add
    \\      i32.load
    \\      i32.const 4
    \\      i32.shr_u
    \\      call $subtask-drop
    \\    end
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.const 2
    \\    i32.store
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-set-drop
    \\    local.get $frame
    \\    call $waitable-set-new
    \\    i32.store
    \\    local.get $frame
    \\    call $start-child
    \\  )
    \\
    \\  (func (export "[async-lift]__ROOT__") (type $async-run) (local $frame i32) (local $subtask i32)
    \\    call $frame-alloc
    \\    local.set $frame
    \\    local.get $frame
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $waitable-set-new
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.const 2
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.const 1
    \\    i32.store
    \\    ;; [guest-inline-helper]
    \\    call $host-work
    \\    local.set $subtask
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    local.get $subtask
    \\    i32.store
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $inline-resume
    \\    else
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      local.get $frame
    \\      i32.load
    \\      call $waitable-join
    \\      local.get $frame
    \\      i32.load
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end
    \\  )
    \\
    \\  (func (export "[callback][async-lift]__ROOT__") (type $async-callback)
    \\    (local $frame i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get 0
    \\    i32.const 1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      i32.const 8
    \\      i32.add
    \\      i32.load
    \\      i32.const 1
    \\      i32.eq
    \\      if (result i32)
    \\        local.get $frame
    \\        call $inline-resume
    \\      else
    \\        local.get $frame
    \\        i32.const 8
    \\        i32.add
    \\        i32.load
    \\        i32.const 2
    \\        i32.eq
    \\        if (result i32)
    \\          local.get $frame
    \\          call $root-resume
    \\          i32.const 0
    \\        else
    \\          unreachable
    \\          i32.const 0
    \\        end
    \\      end
    \\    else
    \\      unreachable
    \\      i32.const 0
    \\    end
    \\  )
    \\
    \\  (func (export "cabi_realloc") (type $cabi-realloc)
    \\    unreachable
    \\  )
    \\  (func (export "_initialize"))
    \\)
;
