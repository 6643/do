const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const component_async_plan = @import("codegen_component_async_plan.zig");
const codegen_emit_async = @import("codegen_emit_async.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const async_byte_budget = @import("async_byte_budget.zig");

pub const StreamMirrorFrameLayout = struct {
    source_reader: u32 = 64,
    source_completion: u32 = 68,
    source_pending: u32 = 72,
    source_result_tag: u32 = 76,
    source_result_payload: u32 = 80,
    remaining: u32 = 88,
    size: u32 = 96,
};

const QueueEntry = struct {
    value: i32,
    allocation: ?async_byte_budget.Allocation = null,
};

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = component_async_plan.StreamWriterPlan.analyze(tokens, registry) catch return error.UnsupportedP3StreamWriterComponent;
    return emit_writer_wat(allocator, plan);
}

pub fn emit_stream_mirror_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = component_async_plan.StreamMirrorPlan.analyze(tokens, registry) catch
        return error.UnsupportedP3StreamMirrorComponent;
    const source_shape = switch (p3_async_manifest.lowering_shape(plan.source_descriptor) orelse return error.UnsupportedP3StreamMirrorComponent) {
        .stream_reader_acquire => |shape| shape,
        else => return error.UnsupportedP3StreamMirrorComponent,
    };
    const sink_shape = switch (p3_async_manifest.lowering_shape(plan.sink_descriptor) orelse return error.UnsupportedP3StreamMirrorComponent) {
        .stream_writer => |shape| shape,
        else => return error.UnsupportedP3StreamMirrorComponent,
    };
    return emit_stream_mirror_wat(allocator, plan, source_shape, sink_shape);
}

fn emit_stream_mirror_wat(
    allocator: std.mem.Allocator,
    plan: component_async_plan.StreamMirrorPlan,
    source_shape: p3_async_manifest.StreamReaderShape,
    sink_shape: p3_async_manifest.StreamWriterShape,
) ![]u8 {
    const frame = StreamMirrorFrameLayout{};
    const wit_export = try writer_wit_identifier(allocator, plan.export_name);
    defer allocator.free(wit_export);
    const task_return_export = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{wit_export});
    defer allocator.free(task_return_export);
    const async_lift_export = try std.fmt.allocPrint(allocator, "[async-lift]{s}", .{wit_export});
    defer allocator.free(async_lift_export);
    const async_callback_export = try std.fmt.allocPrint(allocator, "[callback][async-lift]{s}", .{wit_export});
    defer allocator.free(async_callback_export);

    const root_stream_new = try root_stream_import_name(allocator, sink_shape.new.import_name, wit_export);
    defer allocator.free(root_stream_new);
    const root_stream_cancel_read = try root_stream_import_name(allocator, sink_shape.cancel_read.import_name, wit_export);
    defer allocator.free(root_stream_cancel_read);
    const root_stream_cancel_write = try root_stream_import_name(allocator, sink_shape.cancel_write.import_name, wit_export);
    defer allocator.free(root_stream_cancel_write);
    const root_stream_drop_readable = try root_stream_import_name(allocator, sink_shape.drop_readable.import_name, wit_export);
    defer allocator.free(root_stream_drop_readable);
    const root_stream_drop_writable = try root_stream_import_name(allocator, sink_shape.drop_writable.import_name, wit_export);
    defer allocator.free(root_stream_drop_writable);
    const root_stream_read = try root_stream_import_name(allocator, sink_shape.read.import_name, wit_export);
    defer allocator.free(root_stream_read);
    const root_stream_write = try root_stream_import_name(allocator, sink_shape.write.import_name, wit_export);
    defer allocator.free(root_stream_write);

    const metadata = try std.fmt.allocPrint(
        allocator,
        "  ;; [writer-result-tag-offset] 0\n  ;; [writer-result-payload-offset] 1\n  ;; Frame layout: writer queue head/count/capacity at 20/24/28; pending producer at 32; terminal/error at 36/40.\n  ;; [writer-capacity] {d}\n  ;; [writer-frame-size] {d}\n  ;; [stream-mirror-source-reader-offset] {d}\n  ;; [stream-mirror-source-completion-offset] {d}\n  ;; [stream-mirror-source-pending-offset] {d}\n  ;; [stream-mirror-source-result-tag-offset] {d}\n  ;; [stream-mirror-source-result-payload-offset] {d}\n  ;; [stream-mirror-remaining-offset] {d}\n  ;; [stream-mirror-frame-size] {d}\n",
        .{ plan.capacity, frame.size, frame.source_reader, frame.source_completion, frame.source_pending, frame.source_result_tag, frame.source_result_payload, frame.remaining, frame.size },
    );
    defer allocator.free(metadata);

    const boundary = "  ;; [stream-mirror] bounded source-to-writer pump\n  ;; [stream-mirror-max-reads] 3\n  ;; [stream-mirror-source-cancel] future-drop-readable\n";
    const source_imports = try std.fmt.allocPrint(
        allocator,
        "  (type $source-acquire (func (param i32)))\n  (import \"{s}\" \"{s}\" (func $source-acquire (type $source-acquire)))\n  (import \"{s}\" \"{s}\" (func $source-stream-read (type $stream-io)))\n  (import \"{s}\" \"{s}\" (func $source-stream-drop-readable (type $stream-drop)))\n  (import \"{s}\" \"{s}\" (func $source-future-drop-readable (type $stream-drop)))\n",
        .{ plan.source_descriptor.canonical.async_import_module, plan.source_descriptor.canonical.async_import_name, plan.source_descriptor.canonical.async_import_module, source_shape.read.import_name, plan.source_descriptor.canonical.async_import_module, source_shape.drop_readable.import_name, plan.source_descriptor.canonical.async_import_module, source_shape.future_drop_readable.import_name },
    );
    defer allocator.free(source_imports);

    var wat = try allocator.dupe(u8, writer_core_wat);
    wat = try remove_forwarded_writer_root(allocator, wat);
    wat = try replace_and_free(allocator, wat, "i64.const 64", "i64.const 96");
    wat = try replace_and_free(allocator, wat, "i32.const 64", "i32.const 96");
    wat = try replace_and_free(allocator, wat, "[writer-frame-layout]", metadata);
    wat = try replace_and_free(allocator, wat, "[writer-boundary]", boundary);
    wat = try replace_and_free(allocator, wat, "[producer-data]", "");
    wat = try replace_and_free(allocator, wat, "[async-import-module]", plan.sink_descriptor.canonical.async_import_module);
    wat = try replace_and_free(allocator, wat, "[async-import-name]", plan.sink_descriptor.canonical.async_import_name);
    wat = try replace_and_free(allocator, wat, "[stream-new]", sink_shape.new.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-cancel-read]", sink_shape.cancel_read.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-cancel-write]", sink_shape.cancel_write.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-drop-readable]", sink_shape.drop_readable.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-drop-writable]", sink_shape.drop_writable.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-read]", sink_shape.read.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-write]", sink_shape.write.import_name);
    wat = try replace_and_free(allocator, wat, "[task-return]write-via-stream", task_return_export);
    wat = try replace_and_free(allocator, wat, "[async-lift]write-via-stream", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]write-via-stream", async_callback_export);
    wat = try replace_and_free(allocator, wat, "[root-stream-new]", root_stream_new);
    wat = try replace_and_free(allocator, wat, "[root-stream-cancel-read]", root_stream_cancel_read);
    wat = try replace_and_free(allocator, wat, "[root-stream-cancel-write]", root_stream_cancel_write);
    wat = try replace_and_free(allocator, wat, "[root-stream-drop-readable]", root_stream_drop_readable);
    wat = try replace_and_free(allocator, wat, "[root-stream-drop-writable]", root_stream_drop_writable);
    wat = try replace_and_free(allocator, wat, "[root-stream-read]", root_stream_read);
    wat = try replace_and_free(allocator, wat, "[root-stream-write]", root_stream_write);
    const mirror_entry = try stream_mirror_entry_wat(allocator, frame, async_lift_export);
    defer allocator.free(mirror_entry);
    wat = try replace_and_free(allocator, wat, "[guest-entry]", mirror_entry);
    const mirror_callback = try stream_mirror_callback_body(allocator);
    defer allocator.free(mirror_callback);
    wat = try replace_and_free(allocator, wat, "[guest-callback-body]", mirror_callback);
    const source_import_insertion = try std.fmt.allocPrint(allocator, "{s}  (import \"[export]$root\" \"[task-cancel]", .{source_imports});
    defer allocator.free(source_import_insertion);
    wat = try replace_and_free(allocator, wat, "  (import \"[export]$root\" \"[task-cancel]", source_import_insertion);
    wat = try strip_guest_root_stream_imports(allocator, wat, sink_shape, wit_export);
    return wat;
}

pub fn emit_stream_mirror_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    _ = component_async_plan.StreamMirrorPlan.analyze(tokens, registry) catch return error.UnsupportedP3StreamMirrorComponent;
    return allocator.dupe(
        u8,
        "package do:stream-probe@0.1.0;\n\ninterface types {\n  enum error-code { io, illegal-byte-sequence, pipe }\n}\n\ninterface source {\n  use types.{error-code};\n  read-via-stream: func() -> tuple<stream<u8>, future<result<_, error-code>>>;\n}\n\ninterface sink {\n  use types.{error-code};\n  write-via-stream: async func(data: stream<u8>) -> result<_, error-code>;\n}\n\nworld stream-mirror-probe {\n  import source;\n  import sink;\n  use types.{error-code};\n  export produce: async func() -> result<_, error-code>;\n}\n",
    );
}

fn remove_forwarded_writer_root(allocator: std.mem.Allocator, input: []u8) ![]u8 {
    const start = std.mem.indexOf(u8, input, "  (func (export \"[async-lift]write-via-stream\"") orelse
        return error.UnsupportedP3StreamMirrorComponent;
    const marker = std.mem.indexOfPos(u8, input, start, "[guest-entry]") orelse
        return error.UnsupportedP3StreamMirrorComponent;
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator, input[0..start]);
    try output.appendSlice(allocator, input[marker..]);
    allocator.free(input);
    return output.toOwnedSlice(allocator);
}

fn stream_mirror_entry_wat(
    allocator: std.mem.Allocator,
    frame: StreamMirrorFrameLayout,
    export_name: []const u8,
) ![]u8 {
    _ = frame;
    const format =
        \\  ;; [stream-mirror-source-read]
        \\  (func $mirror-drop-writable (param $frame i32) (local $endpoint i32)
        \\    local.get $frame
        \\    i32.const 16
        \\    i32.add
        \\    i32.load
        \\    local.tee $endpoint
        \\    i32.eqz
        \\    if
        \\    else
        \\      local.get $endpoint
        \\      call $stream-drop-writable
        \\      local.get $frame
        \\      i32.const 16
        \\      i32.add
        \\      i32.const 0
        \\      i32.store
        \\    end
        \\  )
        \\  (func $mirror-finish-source (param $frame i32) (local $handle i32)
        \\    local.get $frame
        \\    i32.const 68
        \\    i32.add
        \\    i32.load
        \\    local.tee $handle
        \\    i32.eqz
        \\    if
        \\    else
        \\      local.get $handle
        \\      call $source-future-drop-readable
        \\      local.get $frame
        \\      i32.const 68
        \\      i32.add
        \\      i32.const 0
        \\      i32.store
        \\    end
        \\    local.get $frame
        \\    i32.const 64
        \\    i32.add
        \\    i32.load
        \\    local.tee $handle
        \\    i32.eqz
        \\    if
        \\    else
        \\      local.get $handle
        \\      call $source-stream-drop-readable
        \\      local.get $frame
        \\      i32.const 64
        \\      i32.add
        \\      i32.const 0
        \\      i32.store
        \\    end
        \\  )
        \\  (func $mirror-complete (param $frame i32) (result i32) (local $subtask i32)
        \\    local.get $frame
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    local.tee $subtask
        \\    i32.eqz
        \\    if
        \\    else
        \\      local.get $subtask
        \\      i32.const 2
        \\      i32.eq
        \\      if
        \\      else
        \\        local.get $subtask
        \\        i32.const 4
        \\        i32.shr_u
        \\        call $subtask-drop
        \\      end
        \\      local.get $frame
        \\      i32.const 4
        \\      i32.add
        \\      i32.const 0
        \\      i32.store
        \\    end
        \\    local.get $frame
        \\    i32.load8_u offset=0
        \\    local.get $frame
        \\    i32.const 1
        \\    i32.add
        \\    i32.load8_u
        \\    local.get $frame
        \\    call $mirror-finish-source
        \\    local.get $frame
        \\    call $mirror-drop-writable
        \\    local.get $frame
        \\    call $writer-finalize
        \\    drop
        \\    call $task-return
        \\    local.get $frame
        \\    i32.const 8
        \\    i32.add
        \\    i32.load
        \\    call $waitable-set-drop
        \\    local.get $frame
        \\    call $frame-free
        \\    i32.const 0
        \\  )
        \\  (func $mirror-wait-sink (param $frame i32) (result i32) (local $subtask i32)
        \\    local.get $frame
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    local.tee $subtask
        \\    i32.const 2
        \\    i32.eq
        \\    if (result i32)
        \\      local.get $frame
        \\      call $mirror-complete
        \\    else
        \\      local.get $subtask
        \\      i32.const 4
        \\      i32.shr_u
        \\      local.get $frame
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $waitable-join
        \\      local.get $frame
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      i32.const 4
        \\      i32.shl
        \\      i32.const 2
        \\      i32.or
        \\    end
        \\  )
        \\  (func $mirror-start-read (param $frame i32) (result i32) (local $code i32)
        \\    local.get $frame
        \\    i32.const 64
        \\    i32.add
        \\    i32.load
        \\    i32.const 512
        \\    i32.const 1
        \\    call $source-stream-read
        \\    local.tee $code
        \\    i32.const -1
        \\    i32.eq
        \\    if (result i32)
        \\      local.get $frame
        \\      i32.const 64
        \\      i32.add
        \\      i32.load
        \\      local.get $frame
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $waitable-join
        \\      local.get $frame
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      i32.const 4
        \\      i32.shl
        \\      i32.const 2
        \\      i32.or
        \\    else
        \\      local.get $frame
        \\      local.get $code
        \\      call $mirror-accept-read
        \\    end
        \\  )
        \\  (func $mirror-accept-read (param $frame i32) (param $code i32) (result i32) (local $status i32)
        \\    local.get $code
        \\    i32.const 1
        \\    i32.eq
        \\    if (result i32)
        \\      local.get $frame
        \\      call $mirror-finish-source
        \\      local.get $frame
        \\      call $mirror-drop-writable
        \\      local.get $frame
        \\      call $mirror-wait-sink
        \\    else
        \\      local.get $code
        \\      i32.const 16
        \\      i32.ne
        \\      if unreachable end
        \\      local.get $frame
        \\      i32.const 512
        \\      i32.const 1
        \\      call $writer-enqueue
        \\      local.tee $status
        \\      i32.eqz
        \\      if (result i32)
        \\        local.get $frame
        \\        i32.const 88
        \\        i32.add
        \\        local.get $frame
        \\        i32.const 88
        \\        i32.add
        \\        i64.load
        \\        i64.const 1
        \\        i64.sub
        \\        i64.store
        \\        local.get $frame
        \\        i32.const 88
        \\        i32.add
        \\        i64.load
        \\        i64.eqz
        \\        if (result i32)
        \\          local.get $frame
        \\          call $mirror-finish-source
        \\          local.get $frame
        \\          call $mirror-drop-writable
        \\          local.get $frame
        \\          call $mirror-wait-sink
        \\        else
        \\          local.get $frame
        \\          call $mirror-start-read
        \\        end
        \\      else
        \\        local.get $status
        \\        i32.const -1
        \\        i32.eq
        \\        if (result i32)
        \\          local.get $frame
        \\          i32.const 16
        \\          i32.add
        \\          i32.load
        \\          local.get $frame
        \\          i32.const 8
        \\          i32.add
        \\          i32.load
        \\          call $waitable-join
        \\          local.get $frame
        \\          i32.const 8
        \\          i32.add
        \\          i32.load
        \\          i32.const 4
        \\          i32.shl
        \\          i32.const 2
        \\          i32.or
        \\        else
        \\          local.get $frame
        \\          call $mirror-finish-source
        \\          local.get $frame
        \\          call $mirror-drop-writable
        \\          local.get $frame
        \\          call $mirror-wait-sink
        \\        end
        \\      end
        \\    end
        \\  )
        \\  (func $mirror-write-complete (param $frame i32) (result i32)
        \\    local.get $frame
        \\    call $writer-source-complete
        \\    local.get $frame
        \\    i32.const 88
        \\    i32.add
        \\    local.get $frame
        \\    i32.const 88
        \\    i32.add
        \\    i64.load
        \\    i64.const 1
        \\    i64.sub
        \\    i64.store
        \\    local.get $frame
        \\    i32.const 88
        \\    i32.add
        \\    i64.load
        \\    i64.eqz
        \\    if (result i32)
        \\      local.get $frame
        \\      call $mirror-finish-source
        \\      local.get $frame
        \\      call $mirror-drop-writable
        \\      local.get $frame
        \\      call $mirror-wait-sink
        \\    else
        \\      local.get $frame
        \\      call $mirror-start-read
        \\    end
        \\  )
        \\  (func (export "{s}") (type $async-run-no-param) (local $frame i32) (local $pair i64) (local $readable i32) (local $writable i32) (local $subtask i32)
        \\    call $frame-alloc
        \\    local.set $frame
        \\    local.get $frame
        \\    i32.const 8
        \\    i32.add
        \\    call $waitable-set-new
        \\    i32.store
        \\    call $stream-new
        \\    local.tee $pair
        \\    i32.wrap_i64
        \\    local.set $readable
        \\    local.get $pair
        \\    i64.const 32
        \\    i64.shr_u
        \\    i32.wrap_i64
        \\    local.set $writable
        \\    local.get $frame
        \\    i32.const 12
        \\    i32.add
        \\    local.get $readable
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 16
        \\    i32.add
        \\    local.get $writable
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 28
        \\    i32.add
        \\    i32.const 1
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 64
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 68
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 88
        \\    i32.add
        \\    i64.const 3
        \\    i64.store
        \\    local.get $frame
        \\    i32.const 64
        \\    i32.add
        \\    call $source-acquire
        \\    local.get $frame
        \\    call $context-set-0
        \\    local.get $readable
        \\    local.get $frame
        \\    call $host-call
        \\    local.set $subtask
        \\    local.get $frame
        \\    i32.const 4
        \\    i32.add
        \\    local.get $subtask
        \\    i32.store
        \\    local.get $frame
        \\    call $mirror-start-read
        \\  )
    ;
    return std.fmt.allocPrint(allocator, format, .{export_name});
}

fn stream_mirror_callback_body(allocator: std.mem.Allocator) ![]u8 {
    const format =
        \\    local.get $event
        \\    i32.const 2
        \\    i32.eq
        \\    if (result i32)
        \\      ;; [stream-mirror-source-read]
        \\      local.get $frame
        \\      local.get $payload
        \\      call $mirror-accept-read
        \\    else
        \\      local.get $event
        \\      i32.const 3
        \\      i32.eq
        \\      if (result i32)
        \\        ;; [stream-mirror-writer-write]
        \\        local.get $payload
        \\        i32.const 15
        \\        i32.and
        \\        i32.eqz
        \\        if (result i32)
        \\          local.get $frame
        \\          call $mirror-write-complete
        \\        else
        \\          local.get $frame
        \\          call $mirror-finish-source
        \\          local.get $frame
        \\          call $mirror-drop-writable
        \\          local.get $frame
        \\          call $mirror-wait-sink
        \\        end
        \\      else
        \\        local.get $event
        \\        i32.const 1
        \\        i32.eq
        \\        if (result i32)
        \\          ;; [stream-mirror-sink-result]
        \\          local.get $frame
        \\          call $mirror-complete
        \\        else
        \\          local.get $event
        \\          i32.const 4
        \\          i32.eq
        \\          if (result i32)
        \\            ;; [stream-mirror-cancel]
        \\            local.get $frame
        \\            call $mirror-finish-source
        \\            local.get $frame
        \\            call $mirror-drop-writable
        \\            local.get $frame
        \\            i32.const 8
        \\            i32.add
        \\            i32.load
        \\            call $waitable-set-drop
        \\            local.get $frame
        \\            call $frame-free
        \\            i32.const 0
        \\          else
        \\            unreachable
        \\          end
        \\        end
        \\      end
        \\    end
    ;
    return allocator.dupe(u8, format);
}

fn emit_writer_wat(
    allocator: std.mem.Allocator,
    plan: component_async_plan.StreamWriterPlan,
) ![]u8 {
    const shape = plan.stream;
    const wit_export = try writer_wit_identifier(allocator, plan.export_name);
    defer allocator.free(wit_export);
    const task_return_export = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{wit_export});
    defer allocator.free(task_return_export);
    const async_lift_export = try std.fmt.allocPrint(allocator, "[async-lift]{s}", .{wit_export});
    defer allocator.free(async_lift_export);
    const async_callback_export = try std.fmt.allocPrint(allocator, "[callback][async-lift]{s}", .{wit_export});
    defer allocator.free(async_callback_export);
    const root_stream_new = try root_stream_import_name(allocator, shape.new.import_name, wit_export);
    defer allocator.free(root_stream_new);
    const root_stream_cancel_read = try root_stream_import_name(allocator, shape.cancel_read.import_name, wit_export);
    defer allocator.free(root_stream_cancel_read);
    const root_stream_cancel_write = try root_stream_import_name(allocator, shape.cancel_write.import_name, wit_export);
    defer allocator.free(root_stream_cancel_write);
    const root_stream_drop_readable = try root_stream_import_name(allocator, shape.drop_readable.import_name, wit_export);
    defer allocator.free(root_stream_drop_readable);
    const root_stream_drop_writable = try root_stream_import_name(allocator, shape.drop_writable.import_name, wit_export);
    defer allocator.free(root_stream_drop_writable);
    const root_stream_read = try root_stream_import_name(allocator, shape.read.import_name, wit_export);
    defer allocator.free(root_stream_read);
    const root_stream_write = try root_stream_import_name(allocator, shape.write.import_name, wit_export);
    defer allocator.free(root_stream_write);

    var frame_metadata = std.ArrayList(u8).empty;
    defer frame_metadata.deinit(allocator);
    const frame_layout = codegen_emit_async.stream_writer_frame_layout;
    try codegen_emit_async.emit_stream_writer_frame_metadata(
        allocator,
        &frame_metadata,
        frame_layout,
        plan.queue_capacity,
    );
    const endpoint_mode = switch (plan.endpoint_mode) {
        .forwarded_reader => "forwarded-reader",
        .guest_producer => "guest-producer",
    };
    const lease_transfer = if (plan.producer_helper_name != null) "async-helper" else "direct";
    const terminal_metadata = try writer_terminal_metadata(allocator, plan.producer_terminal);
    defer allocator.free(terminal_metadata);
    const boundary_metadata = try std.fmt.allocPrint(
        allocator,
        "  ;; [writer-endpoint-mode] {s}\n  ;; [writer-lease-transfer] {s}\n  ;; [writer-queue-capacity] {d}\n{s}",
        .{ endpoint_mode, lease_transfer, plan.queue_capacity, terminal_metadata },
    );
    defer allocator.free(boundary_metadata);
    const producer_data = switch (plan.endpoint_mode) {
        .forwarded_reader => try allocator.dupe(u8, ""),
        .guest_producer => switch (plan.producer_mode) {
            .fixed_sequence => try producer_data_wat(allocator, plan.producer_values[0..plan.producer_write_count]),
            .countdown => if (plan.producer_value_name != null)
                try producer_data_wat(allocator, &[_]u8{0})
            else
                try producer_data_wat(allocator, &[_]u8{plan.producer_value orelse return error.UnsupportedP3StreamWriterComponent}),
        },
    };
    defer allocator.free(producer_data);

    var wat = try allocator.dupe(u8, writer_core_wat);
    wat = try replace_and_free(allocator, wat, "[writer-frame-layout]", frame_metadata.items);
    const result_tag_offset = try std.fmt.allocPrint(allocator, "{d}", .{frame_layout.result_tag});
    defer allocator.free(result_tag_offset);
    const result_payload_offset = try std.fmt.allocPrint(allocator, "{d}", .{frame_layout.result_payload});
    defer allocator.free(result_payload_offset);
    wat = try replace_and_free(allocator, wat, "[writer-result-tag-offset-value]", result_tag_offset);
    wat = try replace_and_free(allocator, wat, "[writer-result-payload-offset-value]", result_payload_offset);
    wat = try replace_and_free(allocator, wat, "[writer-boundary]", boundary_metadata);
    wat = try replace_and_free(allocator, wat, "[producer-data]", producer_data);
    wat = try replace_and_free(allocator, wat, "[async-import-module]", plan.descriptor.canonical.async_import_module);
    wat = try replace_and_free(allocator, wat, "[async-import-name]", plan.descriptor.canonical.async_import_name);
    wat = try replace_and_free(allocator, wat, "[stream-new]", shape.new.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-cancel-read]", shape.cancel_read.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-cancel-write]", shape.cancel_write.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-drop-readable]", shape.drop_readable.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-drop-writable]", shape.drop_writable.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-read]", shape.read.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-write]", shape.write.import_name);
    wat = try replace_and_free(allocator, wat, "[task-return]write-via-stream", task_return_export);
    wat = try replace_and_free(allocator, wat, "[async-lift]write-via-stream", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]write-via-stream", async_callback_export);
    wat = try replace_and_free(allocator, wat, "[root-stream-new]", root_stream_new);
    wat = try replace_and_free(allocator, wat, "[root-stream-cancel-read]", root_stream_cancel_read);
    wat = try replace_and_free(allocator, wat, "[root-stream-cancel-write]", root_stream_cancel_write);
    wat = try replace_and_free(allocator, wat, "[root-stream-drop-readable]", root_stream_drop_readable);
    wat = try replace_and_free(allocator, wat, "[root-stream-drop-writable]", root_stream_drop_writable);
    wat = try replace_and_free(allocator, wat, "[root-stream-read]", root_stream_read);
    wat = try replace_and_free(allocator, wat, "[root-stream-write]", root_stream_write);
    const guest_entry = switch (plan.endpoint_mode) {
        .forwarded_reader => "",
        .guest_producer => switch (plan.producer_mode) {
            .fixed_sequence => try guest_producer_entry_wat(
                allocator,
                async_lift_export,
                frame_layout,
                plan.queue_capacity,
                plan.producer_write_count,
            ),
            .countdown => try guest_producer_dynamic_entry_wat(
                allocator,
                async_lift_export,
                frame_layout,
                plan.queue_capacity,
                plan.producer_value_name != null,
                plan.producer_terminal,
            ),
        },
    };
    defer if (guest_entry.len != 0) allocator.free(guest_entry);
    wat = try replace_and_free(allocator, wat, "[guest-entry]", guest_entry);
    const callback_body = switch (plan.endpoint_mode) {
        .forwarded_reader => try forwarded_writer_callback_body(allocator, frame_layout),
        .guest_producer => switch (plan.producer_mode) {
            .fixed_sequence => try guest_producer_callback_body(allocator, frame_layout),
            .countdown => try guest_producer_dynamic_callback_body(allocator, frame_layout, plan.producer_terminal),
        },
    };
    defer allocator.free(callback_body);
    wat = try replace_and_free(allocator, wat, "[guest-callback-body]", callback_body);
    if (plan.endpoint_mode == .guest_producer) {
        const forward_export = try std.fmt.allocPrint(allocator, "(func (export \"{s}\") (type $async-run)", .{async_lift_export});
        defer allocator.free(forward_export);
        const unused_export = "(func (export \"[async-lift]__forward_unused\") (type $async-run)";
        wat = try replace_and_free(allocator, wat, forward_export, unused_export);
        wat = try strip_guest_root_stream_imports(allocator, wat, shape, wit_export);
    }
    return wat;
}

fn guest_producer_entry_wat(
    allocator: std.mem.Allocator,
    async_lift_export: []const u8,
    frame_layout: codegen_emit_async.StreamWriterFrameLayout,
    queue_capacity: u32,
    producer_write_count: usize,
) ![]u8 {
    if (producer_write_count == 0) return error.UnsupportedP3StreamWriterComponent;
    const format =
        \\  ;; [writer-queue-pump] one bounded source item per resumable step.
        \\  (func $writer-pump-step (param $frame i32) (result i32) (local $status i32) (local $index i32)
        \\    block $producer-wait
        \\      loop $producer-loop
        \\        local.get $frame
        \\        i32.const {d}
        \\        i32.add
        \\        i32.load
        \\        local.tee $index
        \\        i32.const {d}
        \\        i32.ge_u
        \\        if
        \\          local.get $frame
        \\          i32.const {d}
        \\          i32.add
        \\          i32.load
        \\          call $stream-drop-writable
        \\          br $producer-wait
        \\        end
        \\        local.get $frame
        \\        i32.const 512
        \\        local.get $index
        \\        i32.add
        \\        i32.const 1
        \\        call $writer-enqueue
        \\        local.tee $status
        \\        i32.eqz
        \\        if
        \\          local.get $frame
        \\          i32.const {d}
        \\          i32.add
        \\          local.get $index
        \\          i32.const 1
        \\          i32.add
        \\          i32.store
        \\          br $producer-loop
        \\        end
        \\        local.get $status
        \\        i32.const -1
        \\        i32.eq
        \\        local.get $status
        \\        i32.const 1
        \\        i32.eq
        \\        i32.or
        \\        if
        \\          local.get $status
        \\          i32.const -1
        \\          i32.eq
        \\          if
        \\            local.get $frame
        \\            i32.const {d}
        \\            i32.add
        \\            i32.load
        \\            local.get $frame
        \\            i32.const {d}
        \\            i32.add
        \\            i32.load
        \\            call $waitable-join
        \\          end
        \\          br $producer-wait
        \\        end
        \\        local.get $frame
        \\        i32.const {d}
        \\        i32.add
        \\        i32.load
        \\        call $stream-drop-writable
        \\        br $producer-wait
        \\      end
        \\    end
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    i32.load
        \\    i32.const 4
        \\    i32.shl
        \\    i32.const 2
        \\    i32.or
        \\  )
        \\  (func (export "{s}") (type $async-run-no-param) (local $frame i32) (local $pair i64) (local $readable i32) (local $writable i32) (local $status i32) (local $subtask i32)
        \\    call $frame-alloc
        \\    local.set $frame
        \\    local.get $frame
        \\    i32.const 8
        \\    i32.add
        \\    call $waitable-set-new
        \\    i32.store
        \\    call $stream-new
        \\    local.tee $pair
        \\    i32.wrap_i64
        \\    local.set $readable
        \\    local.get $pair
        \\    i64.const 32
        \\    i64.shr_u
        \\    i32.wrap_i64
        \\    local.set $writable
        \\    local.get $frame
        \\    i32.const 12
        \\    i32.add
        \\    local.get $readable
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 16
        \\    i32.add
        \\    local.get $writable
        \\    i32.store
        \\    ;; Initialize every queue/lease slot before the first direct write.
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    i32.const {d}
        \\    i32.store
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const {d}
        \\    i32.add
        \\    ;; The first value is submitted before the host reader starts.
        \\    i32.const 1
        \\    i32.store
        \\    local.get $writable
        \\    i32.const 512
        \\    i32.const 1
        \\    call $stream-write
        \\    local.tee $status
        \\    i32.const -1
        \\    i32.eq
        \\    if (result i32)
        \\      local.get $frame
        \\      call $context-set-0
        \\      local.get $readable
        \\      local.get $frame
        \\      call $host-call
        \\      local.set $subtask
        \\      local.get $frame
        \\      i32.const 4
        \\      i32.add
        \\      local.get $subtask
        \\      i32.const 4
        \\      i32.shr_u
        \\      i32.store
        \\      local.get $writable
        \\      local.get $frame
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $waitable-join
        \\      local.get $subtask
        \\      i32.const 2
        \\      i32.eq
        \\      if
        \\      else
        \\        local.get $subtask
        \\        i32.const 4
        \\        i32.shr_u
        \\        local.get $frame
        \\        i32.const 8
        \\        i32.add
        \\        i32.load
        \\        call $waitable-join
        \\      end
        \\      local.get $frame
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      i32.const 4
        \\      i32.shl
        \\      i32.const 2
        \\      i32.or
        \\    else
        \\      unreachable
        \\    end
        \\  )
    ;
    return std.fmt.allocPrint(allocator, format, .{
        frame_layout.producer_index,
        producer_write_count,
        frame_layout.stream_writable,
        frame_layout.producer_index,
        frame_layout.stream_writable,
        frame_layout.waitable_set,
        frame_layout.stream_writable,
        frame_layout.waitable_set,
        async_lift_export,
        frame_layout.queue_head,
        frame_layout.queue_count,
        frame_layout.queue_capacity,
        queue_capacity,
        frame_layout.pending_producer,
        frame_layout.terminal_state,
        frame_layout.error_payload,
        frame_layout.pending_ptr,
        frame_layout.pending_len,
        frame_layout.producer_index,
    });
}

fn guest_producer_dynamic_entry_wat(
    allocator: std.mem.Allocator,
    async_lift_export: []const u8,
    frame_layout: codegen_emit_async.StreamWriterFrameLayout,
    queue_capacity: u32,
    parameterized_value: bool,
    terminal: component_async_plan.WriterTerminalAction,
) ![]u8 {
    const run_type = if (parameterized_value) "$async-run-i64-i32" else "$async-run-i64";
    const value_pump = if (parameterized_value)
        try std.fmt.allocPrint(allocator, "        i32.const 512\n        local.get $frame\n        i32.const {d}\n        i32.add\n        i32.load8_u\n        i32.store8\n", .{frame_layout.producer_value})
    else
        try allocator.dupe(u8, "");
    defer allocator.free(value_pump);
    const value_init = if (parameterized_value)
        try std.fmt.allocPrint(allocator, "    local.get $frame\n    i32.const {d}\n    i32.add\n    local.get 1\n    i32.store8\n", .{frame_layout.producer_value})
    else
        try allocator.dupe(u8, "");
    defer allocator.free(value_init);
    const terminal_wat = try writer_terminal_wat(allocator, frame_layout, terminal);
    defer allocator.free(terminal_wat);
    const format =
        \\  ;; [writer-queue-pump] bounded countdown source; sink starts before pumping.
        \\  (func $writer-pump-step (param $frame i32) (result i32) (local $status i32)
        \\    block $producer-wait
        \\      loop $producer-loop
        \\        local.get $frame
        \\        i32.const 52
        \\        i32.add
        \\        i64.load
        \\        i64.eqz
        \\        if
        \\{s}
        \\          local.get $frame
        \\          i32.const 16
        \\          i32.add
        \\          i32.load
        \\          call $stream-drop-writable
        \\          br $producer-wait
        \\        end
        \\{s}
        \\        local.get $frame
        \\        i32.const 512
        \\        i32.const 1
        \\        call $writer-enqueue
        \\        local.tee $status
        \\        i32.eqz
        \\        if
        \\          local.get $frame
        \\          i32.const 52
        \\          i32.add
        \\          local.get $frame
        \\          i32.const 52
        \\          i32.add
        \\          i64.load
        \\          i64.const 1
        \\          i64.sub
        \\          i64.store
        \\          br $producer-loop
        \\        end
        \\        local.get $status
        \\        i32.const -1
        \\        i32.eq
        \\        local.get $status
        \\        i32.const 1
        \\        i32.eq
        \\        i32.or
        \\        if
        \\          local.get $status
        \\          i32.const -1
        \\          i32.eq
        \\          if
        \\            local.get $frame
        \\            i32.const 16
        \\            i32.add
        \\            i32.load
        \\            local.get $frame
        \\            i32.const 8
        \\            i32.add
        \\            i32.load
        \\            call $waitable-join
        \\          end
        \\          br $producer-wait
        \\        end
        \\        local.get $frame
        \\        i32.const 16
        \\        i32.add
        \\        i32.load
        \\        call $stream-drop-writable
        \\        br $producer-wait
        \\      end
        \\    end
        \\    local.get $frame
        \\    i32.const 8
        \\    i32.add
        \\    i32.load
        \\    i32.const 4
        \\    i32.shl
        \\    i32.const 2
        \\    i32.or
        \\  )
        \\  (func (export "{s}") (type {s}) (local $frame i32) (local $pair i64) (local $readable i32) (local $writable i32) (local $subtask i32) (local $pump i32)
        \\    call $frame-alloc
        \\    local.set $frame
        \\    local.get $frame
        \\    i32.const 8
        \\    i32.add
        \\    call $waitable-set-new
        \\    i32.store
        \\    call $stream-new
        \\    local.tee $pair
        \\    i32.wrap_i64
        \\    local.set $readable
        \\    local.get $pair
        \\    i64.const 32
        \\    i64.shr_u
        \\    i32.wrap_i64
        \\    local.set $writable
        \\    local.get $frame
        \\    i32.const 12
        \\    i32.add
        \\    local.get $readable
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 16
        \\    i32.add
        \\    local.get $writable
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 20
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 24
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 28
        \\    i32.add
        \\    i32.const {d}
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 32
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 36
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 40
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 44
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 48
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $frame
        \\    i32.const 52
        \\    i32.add
        \\    local.get 0
        \\    i64.store
        \\{s}
        \\    ;; Register the sink before the first producer step, including count=0.
        \\    local.get $frame
        \\    call $context-set-0
        \\    local.get $readable
        \\    local.get $frame
        \\    call $host-call
        \\    local.set $subtask
        \\    local.get $frame
        \\    i32.const 4
        \\    i32.add
        \\    local.get $subtask
        \\    i32.const 4
        \\    i32.shr_u
        \\    i32.store
        \\    local.get $frame
        \\    call $writer-pump-step
        \\    local.set $pump
        \\    local.get $frame
        \\    i32.const 32
        \\    i32.add
        \\    i32.load
        \\    i32.eqz
        \\    if
        \\    else
        \\      local.get $writable
        \\      local.get $frame
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $waitable-join
        \\    end
        \\    local.get $subtask
        \\    i32.const 2
        \\    i32.eq
        \\    if
        \\    else
        \\      local.get $subtask
        \\      i32.const 4
        \\      i32.shr_u
        \\      local.get $frame
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $waitable-join
        \\    end
        \\    local.get $frame
        \\    i32.const 8
        \\    i32.add
        \\    i32.load
        \\    i32.const 4
        \\    i32.shl
        \\    i32.const 2
        \\    i32.or
        \\  )
    ;
    return std.fmt.allocPrint(allocator, format, .{ terminal_wat, value_pump, async_lift_export, run_type, queue_capacity, value_init });
}

fn writer_terminal_wat(
    allocator: std.mem.Allocator,
    frame_layout: codegen_emit_async.StreamWriterFrameLayout,
    terminal: component_async_plan.WriterTerminalAction,
) ![]u8 {
    return switch (terminal) {
        .close => allocator.dupe(u8, ""),
        .abort_pipe_when_value => |selector| std.fmt.allocPrint(
            allocator,
            "          local.get $frame\n          i32.const {d}\n          i32.add\n          i32.load8_u\n          i32.const {d}\n          i32.eq\n          if\n          else\n            local.get $frame\n            i32.const 2\n            call $writer-abort\n            drop\n          end\n",
            .{ frame_layout.producer_value, selector },
        ),
    };
}

fn producer_data_wat(allocator: std.mem.Allocator, values: []const u8) ![]u8 {
    if (values.len == 0) return error.UnsupportedP3StreamWriterComponent;
    var data = std.ArrayList(u8).empty;
    errdefer data.deinit(allocator);
    for (values) |value| {
        const escaped = try std.fmt.allocPrint(allocator, "\\{X:0>2}", .{value});
        defer allocator.free(escaped);
        try data.appendSlice(allocator, escaped);
    }
    return data.toOwnedSlice(allocator);
}

fn writer_terminal_metadata(
    allocator: std.mem.Allocator,
    terminal: component_async_plan.WriterTerminalAction,
) ![]u8 {
    return switch (terminal) {
        .close => allocator.dupe(u8, "  ;; [writer-terminal] close\n"),
        .abort_pipe_when_value => |selector| std.fmt.allocPrint(
            allocator,
            "  ;; [writer-terminal] branch-abort-pipe selector={d} code=2\n",
            .{selector},
        ),
    };
}

fn forwarded_writer_callback_body(
    allocator: std.mem.Allocator,
    frame_layout: codegen_emit_async.StreamWriterFrameLayout,
) ![]u8 {
    const format =
        \\    local.get $event
        \\    i32.const 1
        \\    i32.eq
        \\    local.get $payload
        \\    i32.const 2
        \\    i32.eq
        \\    i32.and
        \\    if (result i32)
        \\      ;; [writer-result-tag] result-area frame offset=0
        \\      ;; [writer-result-payload] result-area frame offset=1
        \\      i32.const 0
        \\      call $context-set-0
        \\      local.get $frame
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      call $subtask-drop
        \\      local.get $frame
        \\      i32.load8_u offset={d}
        \\      local.get $frame
        \\      i32.const {d}
        \\      i32.add
        \\      i32.load8_u offset={d}
        \\      local.get $frame
        \\      call $writer-promote
        \\      drop
        \\      local.get $frame
        \\      call $writer-finalize
        \\      drop
        \\      call $task-return
        \\      local.get $frame
        \\      i32.const {d}
        \\      i32.add
        \\      i32.load
        \\      call $waitable-set-drop
        \\      local.get $frame
        \\      call $frame-free
        \\      i32.const 0
        \\    else
        \\      local.get $frame
        \\      i32.const {d}
        \\      i32.add
        \\      i32.load
        \\      i32.const 4
        \\      i32.shl
        \\      i32.const 2
        \\      i32.or
        \\    end
    ;
    return std.fmt.allocPrint(allocator, format, .{
        frame_layout.result_tag,
        frame_layout.result_payload,
        frame_layout.result_tag,
        frame_layout.waitable_set,
        frame_layout.waitable_set,
    });
}

fn guest_producer_callback_body(
    allocator: std.mem.Allocator,
    frame_layout: codegen_emit_async.StreamWriterFrameLayout,
) ![]u8 {
    const format =
        \\    local.get $event
        \\    i32.const 3
        \\    i32.eq
        \\    if (result i32)
        \\      ;; A completed write advances the producer sequence; a
        \\      ;; dropped/cancelled write closes the guest-owned writer.
        \\      local.get $payload
        \\      i32.const 15
        \\      i32.and
        \\      i32.eqz
        \\      if (result i32)
        \\        ;; Complete the retained source item before pumping the next one.
        \\        local.get $frame
        \\        call $writer-source-complete
        \\        local.get $frame
        \\        call $writer-pump-step
        \\      else
        \\        local.get $frame
        \\        i32.const {d}
        \\        i32.add
        \\        i32.load
        \\        call $stream-drop-writable
        \\        local.get $frame
        \\        i32.const {d}
        \\        i32.add
        \\        i32.load
        \\        i32.const 4
        \\        i32.shl
        \\        i32.const 2
        \\        i32.or
        \\      end
        \\    else
        \\      local.get $event
        \\      i32.const 1
        \\      i32.eq
        \\      local.get $payload
        \\      i32.const 2
        \\      i32.eq
        \\      i32.and
        \\      if (result i32)
        \\        i32.const 0
        \\        call $context-set-0
        \\        local.get $frame
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        call $subtask-drop
        \\        local.get $frame
        \\        call $writer-finalize
        \\        drop
        \\        local.get $frame
        \\        i32.load8_u offset={d}
        \\        local.get $frame
        \\        i32.const {d}
        \\        i32.add
        \\        i32.load8_u offset={d}
        \\        call $task-return
        \\        local.get $frame
        \\        i32.const {d}
        \\        i32.add
        \\        i32.load
        \\        call $waitable-set-drop
        \\        local.get $frame
        \\        call $frame-free
        \\        i32.const 0
        \\      else
        \\        unreachable
        \\      end
        \\    end
    ;
    return std.fmt.allocPrint(allocator, format, .{
        frame_layout.stream_writable,
        frame_layout.waitable_set,
        frame_layout.result_tag,
        frame_layout.result_payload,
        frame_layout.result_tag,
        frame_layout.waitable_set,
    });
}

fn guest_producer_dynamic_callback_body(
    allocator: std.mem.Allocator,
    frame_layout: codegen_emit_async.StreamWriterFrameLayout,
    terminal: component_async_plan.WriterTerminalAction,
) ![]u8 {
    const terminal_completion = try writer_terminal_completion_wat(allocator, frame_layout, terminal);
    defer allocator.free(terminal_completion);
    const format =
        \\    local.get $event
        \\    i32.const 3
        \\    i32.eq
        \\    if (result i32)
        \\      local.get $payload
        \\      i32.const 15
        \\      i32.and
        \\      i32.eqz
        \\      if (result i32)
        \\        local.get $frame
        \\        call $writer-source-complete-countdown
        \\        local.get $frame
        \\        call $writer-pump-step
        \\      else
        \\        local.get $frame
        \\        i32.const {d}
        \\        i32.add
        \\        i32.load
        \\        call $stream-drop-writable
        \\        local.get $frame
        \\        i32.const {d}
        \\        i32.add
        \\        i32.load
        \\        i32.const 4
        \\        i32.shl
        \\        i32.const 2
        \\        i32.or
        \\      end
        \\    else
        \\      local.get $event
        \\      i32.const 1
        \\      i32.eq
        \\      local.get $payload
        \\      i32.const 2
        \\      i32.eq
        \\      i32.and
        \\      if (result i32)
        \\        i32.const 0
        \\        call $context-set-0
        \\        local.get $frame
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        call $subtask-drop
        \\{s}
        \\        local.get $frame
        \\        i32.const {d}
        \\        i32.add
        \\        i32.load
        \\        call $waitable-set-drop
        \\        local.get $frame
        \\        call $frame-free
        \\        i32.const 0
        \\      else
        \\        unreachable
        \\      end
        \\    end
    ;
    return std.fmt.allocPrint(allocator, format, .{
        frame_layout.stream_writable,
        frame_layout.waitable_set,
        terminal_completion,
        frame_layout.waitable_set,
    });
}

fn writer_terminal_completion_wat(
    allocator: std.mem.Allocator,
    frame_layout: codegen_emit_async.StreamWriterFrameLayout,
    terminal: component_async_plan.WriterTerminalAction,
) ![]u8 {
    return switch (terminal) {
        .close => std.fmt.allocPrint(
            allocator,
            "        local.get $frame\n        call $writer-finalize\n        drop\n        local.get $frame\n        i32.load8_u offset={d}\n        local.get $frame\n        i32.const {d}\n        i32.add\n        i32.load8_u offset={d}\n        call $task-return\n",
            .{ frame_layout.result_tag, frame_layout.result_payload, frame_layout.result_tag },
        ),
        .abort_pipe_when_value => |selector| blk: {
            _ = selector;
            break :blk std.fmt.allocPrint(
                allocator,
                "        local.get $frame\n        i32.const {d}\n        i32.add\n        i32.load\n        i32.const 2\n        i32.eq\n        if\n          i32.const 1\n          local.get $frame\n          i32.const {d}\n          i32.add\n          i32.load\n          call $task-return\n        else\n          local.get $frame\n          call $writer-finalize\n          drop\n          local.get $frame\n          i32.load8_u offset={d}\n          local.get $frame\n          i32.const {d}\n          i32.add\n          i32.load8_u offset={d}\n          call $task-return\n        end\n",
                .{ frame_layout.terminal_state, frame_layout.error_payload, frame_layout.result_tag, frame_layout.result_payload, frame_layout.result_tag },
            );
        },
    };
}

fn strip_guest_root_stream_imports(
    allocator: std.mem.Allocator,
    input: []u8,
    shape: p3_async_manifest.StreamWriterShape,
    wit_export: []const u8,
) ![]u8 {
    const roots = [_]struct { import_name: []const u8, func_name: []const u8, type_name: []const u8 }{
        .{ .import_name = shape.new.import_name, .func_name = "$export-stream-new", .type_name = "$stream-new" },
        .{ .import_name = shape.cancel_read.import_name, .func_name = "$export-stream-cancel-read", .type_name = "$stream-cancel" },
        .{ .import_name = shape.cancel_write.import_name, .func_name = "$export-stream-cancel-write", .type_name = "$stream-cancel" },
        .{ .import_name = shape.drop_readable.import_name, .func_name = "$export-stream-drop-readable", .type_name = "$stream-drop" },
        .{ .import_name = shape.drop_writable.import_name, .func_name = "$export-stream-drop-writable", .type_name = "$stream-drop" },
        .{ .import_name = shape.read.import_name, .func_name = "$export-stream-read", .type_name = "$stream-io" },
        .{ .import_name = shape.write.import_name, .func_name = "$export-stream-write", .type_name = "$stream-io" },
    };
    var output = input;
    for (roots) |root| {
        const rendered = try root_stream_import_name(allocator, root.import_name, wit_export);
        defer allocator.free(rendered);
        const line = try std.fmt.allocPrint(allocator, "  (import \"[export]$root\" \"{s}\" (func {s} (type {s})))\n", .{ rendered, root.func_name, root.type_name });
        defer allocator.free(line);
        output = try replace_and_free(allocator, output, line, "");
    }
    return output;
}

fn root_stream_import_name(allocator: std.mem.Allocator, import_name: []const u8, wit_export: []const u8) ![]u8 {
    const suffix_start = std.mem.lastIndexOfScalar(u8, import_name, ']') orelse return error.UnsupportedP3StreamWriterComponent;
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ import_name[0 .. suffix_start + 1], wit_export });
}

fn writer_wit_identifier(allocator: std.mem.Allocator, source_name: []const u8) ![]u8 {
    const rendered = try allocator.dupe(u8, source_name);
    for (rendered) |*ch| {
        if (ch.* == '_') ch.* = '-';
    }
    return rendered;
}

fn replace_and_free(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const replaced = try replace_all(allocator, input, needle, replacement);
    allocator.free(input);
    return replaced;
}

fn replace_all(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return error.UnsupportedP3StreamWriterComponent;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var remainder = input;
    while (std.mem.indexOf(u8, remainder, needle)) |idx| {
        try out.appendSlice(allocator, remainder[0..idx]);
        try out.appendSlice(allocator, replacement);
        remainder = remainder[idx + needle.len ..];
    }
    try out.appendSlice(allocator, remainder);
    return out.toOwnedSlice(allocator);
}

const writer_core_wat =
    \\(module
    \\  ;; Descriptor-driven stream writer wrapper. The stream operation imports
    \\  ;; are kept explicit because the Component async stream ABI owns both
    \\  ;; ends even when this first wrapper only forwards one endpoint.
    \\  (type $async-lower (func (param i32 i32) (result i32)))
    \\  (type $stream-new (func (result i64)))
    \\  (type $stream-cancel (func (param i32) (result i32)))
    \\  (type $stream-drop (func (param i32)))
    \\  (type $stream-io (func (param i32 i32 i32) (result i32)))
    \\  (type $task-cancel (func))
    \\  (type $backpressure (func))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable (func (param i32 i32)))
    \\  (type $waitable-poll (func (param i32 i32) (result i32)))
    \\  (type $waitable-drop (func (param i32)))
    \\  (type $async-run (func (param i32) (result i32)))
    \\  (type $async-run-no-param (func (result i32)))
    \\  (type $async-run-i64 (func (param i64) (result i32)))
    \\  (type $async-run-i64-i32 (func (param i64 i32) (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $task-return (func (param i32 i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\
    \\  (import "[async-import-module]" "[async-import-name]" (func $host-call (type $async-lower)))
    \\  (import "[async-import-module]" "[stream-new]" (func $stream-new (type $stream-new)))
    \\  (import "[async-import-module]" "[stream-cancel-read]" (func $stream-cancel-read (type $stream-cancel)))
    \\  (import "[async-import-module]" "[stream-cancel-write]" (func $stream-cancel-write (type $stream-cancel)))
    \\  (import "[async-import-module]" "[stream-drop-readable]" (func $stream-drop-readable (type $stream-drop)))
    \\  (import "[async-import-module]" "[stream-drop-writable]" (func $stream-drop-writable (type $stream-drop)))
    \\  (import "[async-import-module]" "[stream-read]" (func $stream-read (type $stream-io)))
    \\  (import "[async-import-module]" "[stream-write]" (func $stream-write (type $stream-io)))
    \\
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-cancel)))
    \\  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $backpressure)))
    \\  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $backpressure)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $waitable-poll)))
    \\  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $waitable-poll)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-drop)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable)))
    \\  (import "$root" "[thread-yield]" (func $thread-yield (type $waitable-set-new)))
    \\  (import "$root" "[subtask-drop]" (func $subtask-drop (type $waitable-drop)))
    \\  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $stream-cancel)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (type $waitable-set-new)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (type $stream-drop)))
    \\  (import "[export]$root" "[task-return]write-via-stream" (func $task-return (type $task-return)))
    \\  (import "[export]$root" "[root-stream-new]" (func $export-stream-new (type $stream-new)))
    \\  (import "[export]$root" "[root-stream-cancel-read]" (func $export-stream-cancel-read (type $stream-cancel)))
    \\  (import "[export]$root" "[root-stream-cancel-write]" (func $export-stream-cancel-write (type $stream-cancel)))
    \\  (import "[export]$root" "[root-stream-drop-readable]" (func $export-stream-drop-readable (type $stream-drop)))
    \\  (import "[export]$root" "[root-stream-drop-writable]" (func $export-stream-drop-writable (type $stream-drop)))
    \\  (import "[export]$root" "[root-stream-read]" (func $export-stream-read (type $stream-io)))
    \\  (import "[export]$root" "[root-stream-write]" (func $export-stream-write (type $stream-io)))
    \\
    \\  (memory (export "memory") 1)
    \\  (data (i32.const 512) "[producer-data]")
    \\  ;; [async-frame-budget-bytes] 64
    \\  ;; [async-byte-budget-limit] -1
    \\  (global $async-byte-budget-used (mut i64) (i64.const 0))
    \\  (global $async-byte-budget-limit (mut i64) (i64.const -1))
    \\  (func $async-byte-budget-limit (export "[async-config]byte-budget-limit") (param $limit i64) (result i32)
    \\    local.get $limit
    \\    i64.const -1
    \\    i64.eq
    \\    if (result i32)
    \\      local.get $limit
    \\      global.set $async-byte-budget-limit
    \\      i32.const 1
    \\    else
    \\      local.get $limit
    \\      i64.const 0
    \\      i64.lt_s
    \\      if (result i32)
    \\        i32.const 0
    \\      else
    \\        global.get $async-byte-budget-used
    \\        local.get $limit
    \\        i64.gt_u
    \\        if (result i32)
    \\          i32.const 0
    \\        else
    \\          local.get $limit
    \\          global.set $async-byte-budget-limit
    \\          i32.const 1
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func (export "byte-budget-limit") (param $limit i64) (result i32)
    \\    local.get $limit
    \\    call $async-byte-budget-limit)
    \\  (func $async-byte-budget-reserve (param $bytes i64) (result i32)
    \\    (local $next i64)
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.add
    \\    local.tee $next
    \\    global.get $async-byte-budget-used
    \\    i64.lt_u
    \\    if (result i32)
    \\      i32.const 0
    \\    else
    \\      global.get $async-byte-budget-limit
    \\      i64.const -1
    \\      i64.eq
    \\      if (result i32)
    \\        i32.const 1
    \\      else
    \\        local.get $next
    \\        global.get $async-byte-budget-limit
    \\        i64.le_u
    \\      end
    \\      if (result i32)
    \\        local.get $next
    \\        global.set $async-byte-budget-used
    \\        i32.const 1
    \\      else
    \\        i32.const 0
    \\      end
    \\    end
    \\  )
    \\  (func $async-byte-budget-release (param $bytes i64)
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.lt_u
    \\    if unreachable end
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.sub
    \\    global.set $async-byte-budget-used
    \\  )
    \\  (global $frame-free (mut i32) (i32.const 0))
    \\  (global $frame-next (mut i32) (i32.const 1024))
    \\  (global $heap-next (mut i32) (i32.const 65536))
    \\  (func $frame-alloc (result i32) (local $frame i32)
    \\    i64.const 64
    \\    call $async-byte-budget-reserve
    \\    i32.eqz
    \\    if unreachable end
    \\    global.get $frame-free
    \\    local.tee $frame
    \\    i32.eqz
    \\    if (result i32)
    \\      global.get $frame-next
    \\      local.tee $frame
    \\      i32.const 64
    \\      i32.add
    \\      global.set $frame-next
    \\      local.get $frame
    \\    else
    \\      local.get $frame
    \\      i32.load
    \\      global.set $frame-free
    \\      local.get $frame
    \\    end
    \\  )
    \\  (func $frame-free (param $frame i32)
    \\    i64.const 64
    \\    call $async-byte-budget-release
    \\    local.get $frame
    \\    global.get $frame-free
    \\    i32.store
    \\    local.get $frame
    \\    global.set $frame-free
    \\  )
    \\  (func $writer-enqueue (param $frame i32) (param $ptr i32) (param $len i32) (result i32) (local $status i32)
    \\    local.get $frame
    \\    i32.const 36
    \\    i32.add
    \\    i32.load
    \\    i32.eqz
    \\    if (result i32)
    \\      local.get $frame
    \\      i32.const 24
    \\      i32.add
    \\      i32.load
    \\      local.get $frame
    \\      i32.const 28
    \\      i32.add
    \\      i32.load
    \\      i32.lt_u
    \\      if (result i32)
    \\        local.get $frame
    \\        i32.const 16
    \\        i32.add
    \\        i32.load
    \\        local.get $ptr
    \\        local.get $len
    \\        call $stream-write
    \\        local.tee $status
    \\        i32.const 15
    \\        i32.and
    \\        i32.eqz
    \\        if (result i32)
    \\          i32.const 0
    \\        else
    \\          local.get $status
    \\          i32.const -1
    \\          i32.eq
    \\          if (result i32)
    \\            local.get $frame
    \\            i32.const 32
    \\            i32.add
    \\            local.get $status
    \\            i32.store
    \\            local.get $frame
    \\            i32.const 44
    \\            i32.add
    \\            local.get $ptr
    \\            i32.store
    \\            local.get $frame
    \\            i32.const 48
    \\            i32.add
    \\            local.get $len
    \\            i32.store
    \\            call $backpressure-inc
    \\            local.get $status
    \\          else
    \\            local.get $status
    \\          end
    \\        end
    \\      else
    \\        ;; [writer-backpressure] capacity is full; retain one producer
    \\        local.get $frame
    \\        i32.const 32
    \\        i32.add
    \\        i32.const 1
    \\        i32.store
    \\        local.get $frame
    \\        i32.const 44
    \\        i32.add
    \\        local.get $ptr
    \\        i32.store
    \\        local.get $frame
    \\        i32.const 48
    \\        i32.add
    \\        local.get $len
    \\        i32.store
    \\        call $backpressure-inc
    \\        i32.const 1
    \\      end
    \\    else
    \\      i32.const -1
    \\    end
    \\  )
    \\  (func $writer-source-complete (param $frame i32)
    \\    local.get $frame
    \\    i32.const 32
    \\    i32.add
    \\    i32.load
    \\    i32.eqz
    \\    if
    \\    else
    \\      call $backpressure-dec
    \\      local.get $frame
    \\      i32.const 32
    \\      i32.add
    \\      i32.const 0
    \\      i32.store
    \\      local.get $frame
    \\      i32.const 52
    \\      i32.add
    \\      local.get $frame
    \\      i32.const 52
    \\      i32.add
    \\      i32.load
    \\      i32.const 1
    \\      i32.add
    \\      i32.store
    \\    end
    \\  )
    \\  (func $writer-source-complete-countdown (param $frame i32)
    \\    local.get $frame
    \\    i32.const 32
    \\    i32.add
    \\    i32.load
    \\    i32.eqz
    \\    if
    \\    else
    \\      call $backpressure-dec
    \\      local.get $frame
    \\      i32.const 32
    \\      i32.add
    \\      i32.const 0
    \\      i32.store
    \\      local.get $frame
    \\      i32.const 52
    \\      i32.add
    \\      local.get $frame
    \\      i32.const 52
    \\      i32.add
    \\      i64.load
    \\      i64.const 1
    \\      i64.sub
    \\      i64.store
    \\    end
    \\  )
    \\  (func $writer-promote (param $frame i32) (result i32) (local $status i32)
    \\    local.get $frame
    \\    i32.const 32
    \\    i32.add
    \\    i32.load
    \\    i32.eqz
    \\    if (result i32)
    \\      i32.const 0
    \\    else
    \\      local.get $frame
    \\      i32.const 24
    \\      i32.add
    \\      i32.load
    \\      local.get $frame
    \\      i32.const 28
    \\      i32.add
    \\      i32.load
    \\      i32.ge_u
    \\      if (result i32)
    \\        i32.const 1
    \\      else
    \\        local.get $frame
    \\        i32.const 16
    \\        i32.add
    \\        i32.load
    \\        local.get $frame
    \\        i32.const 44
    \\        i32.add
    \\        i32.load
    \\        local.get $frame
    \\        i32.const 48
    \\        i32.add
    \\        i32.load
    \\        call $stream-write
    \\        local.tee $status
    \\        i32.const 15
    \\        i32.and
    \\        i32.eqz
    \\        if (result i32)
    \\          local.get $frame
    \\          i32.const 32
    \\          i32.add
    \\          i32.const 0
    \\          i32.store
    \\          local.get $frame
    \\          i32.const 24
    \\          i32.add
    \\          local.get $frame
    \\          i32.const 24
    \\          i32.add
    \\          i32.load
    \\          i32.const 1
    \\          i32.add
    \\          i32.store
    \\          call $backpressure-dec
    \\          i32.const 0
    \\        else
    \\          local.get $status
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func $writer-finalize (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 36
    \\    i32.add
    \\    i32.load
    \\    i32.eqz
    \\    if (result i32)
    \\      local.get $frame
    \\      i32.const 36
    \\      i32.add
    \\      i32.const 1
    \\      i32.store
    \\      local.get $frame
    \\      i32.const 32
    \\      i32.add
    \\      i32.load
    \\      i32.eqz
    \\      if
    \\      else
    \\        call $backpressure-dec
    \\      end
    \\      local.get $frame
    \\      i32.const 32
    \\      i32.add
    \\      i32.const 0
    \\      i32.store
    \\      ;; [writer-drop-deferred] endpoint drop requires a guest-created
    \\      ;; writable stream; the forwarding probe owns only its reader.
    \\      i32.const 0
    \\    else
    \\      i32.const -1
    \\    end
    \\  )
    \\  (func $writer-abort (param $frame i32) (param $code i32) (result i32)
    \\    local.get $frame
    \\    i32.const 36
    \\    i32.add
    \\    i32.load
    \\    i32.eqz
    \\    if (result i32)
    \\      local.get $frame
    \\      i32.const 36
    \\      i32.add
    \\      i32.const 2
    \\      i32.store
    \\      local.get $frame
    \\      i32.const 40
    \\      i32.add
    \\      local.get $code
    \\      i32.store
    \\      local.get $frame
    \\      i32.const 32
    \\      i32.add
    \\      i32.load
    \\      i32.eqz
    \\      if
    \\      else
    \\        call $backpressure-dec
    \\      end
    \\      local.get $frame
    \\      i32.const 32
    \\      i32.add
    \\      i32.const 0
    \\      i32.store
    \\      i32.const 0
    \\    else
    \\      i32.const -1
    \\    end
    \\  )
    \\  (func $writer-drop-readable (param $frame i32)
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.load
    \\    call $stream-drop-readable
    \\  )
    \\[writer-frame-layout]
    \\[writer-boundary]
    \\  ;; Queue slots hold a single scalar u8 payload at a time; pending data
    \\  ;; stays in linear memory until the consumer frees one bounded slot.
    \\  (func (export "[async-lift]write-via-stream") (type $async-run) (local $frame i32) (local $subtask i32)
    \\    call $frame-alloc
    \\    local.tee $frame
    \\    i32.const 8
    \\    i32.add
    \\    call $waitable-set-new
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    local.get 0
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 16
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 20
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 24
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 28
    \\    i32.add
    \\    i32.const 1
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 32
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 36
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 40
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    call $context-set-0
    \\    local.get 0
    \\    local.get $frame
    \\    call $host-call
    \\    local.set $subtask
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    local.get $subtask
    \\    i32.const 4
    \\    i32.shr_u
    \\    i32.store
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      i32.const 0
    \\      call $context-set-0
    \\      local.get $frame
    \\      i32.load8_u offset=[writer-result-tag-offset-value]
    \\      local.get $frame
    \\      i32.const [writer-result-payload-offset-value]
    \\      i32.add
    \\      i32.load8_u offset=[writer-result-tag-offset-value]
    \\      local.get $frame
    \\      call $writer-promote
    \\      drop
    \\      local.get $frame
    \\      call $writer-finalize
    \\      drop
    \\      call $task-return
    \\      local.get $frame
    \\      call $frame-free
    \\      i32.const 0
    \\    else
    \\    local.get $subtask
    \\    i32.const 4
    \\    i32.shr_u
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    call $waitable-join
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\    end
    \\  )
    \\[guest-entry]
    \\  (func (export "[callback][async-lift]write-via-stream") (type $async-run-callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\[guest-callback-body]
    \\  )
    \\  (func (export "cabi_realloc") (type $cabi-realloc) (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (result i32)
    \\    (local $ptr i32)
    \\    (local $end i32)
    \\    (local $budget-delta i64)
    \\    local.get $size
    \\    local.get $old-size
    \\    i32.gt_u
    \\    if
    \\      local.get $size
    \\      local.get $old-size
    \\      i32.sub
    \\      i64.extend_i32_u
    \\      local.tee $budget-delta
    \\      call $async-byte-budget-reserve
    \\      i32.eqz
    \\      if unreachable end
    \\    else
    \\      local.get $old-size
    \\      local.get $size
    \\      i32.gt_u
    \\      if
    \\        local.get $old-size
    \\        local.get $size
    \\        i32.sub
    \\        i64.extend_i32_u
    \\        call $async-byte-budget-release
    \\      end
    \\    end
    \\    global.get $heap-next
    \\    local.set $ptr
    \\    local.get $ptr
    \\    local.get $size
    \\    i32.add
    \\    local.set $end
    \\    local.get $end
    \\    memory.size
    \\    i32.const 16
    \\    i32.shl
    \\    i32.gt_u
    \\    if
    \\      local.get $end
    \\      i32.const 65535
    \\      i32.add
    \\      i32.const 16
    \\      i32.shr_u
    \\      memory.size
    \\      i32.sub
    \\      memory.grow
    \\      i32.const -1
    \\      i32.eq
    \\      if
    \\        local.get $budget-delta
    \\        call $async-byte-budget-release
    \\        unreachable
    \\      end
    \\    end
    \\    local.get $end
    \\    global.set $heap-next
    \\    local.get $ptr
    \\  )
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = component_async_plan.StreamWriterPlan.analyze(tokens, registry) catch return error.UnsupportedP3StreamWriterComponent;
    const descriptor = plan.descriptor;
    const shape = p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3StreamWriterComponent;
    switch (shape) {
        .stream_writer => {},
        else => return error.UnsupportedP3StreamWriterComponent,
    }
    const export_name = plan.export_name;
    const export_params = switch (plan.endpoint_mode) {
        .forwarded_reader => "(data: stream<u8>)",
        .guest_producer => switch (plan.producer_mode) {
            .fixed_sequence => "()",
            .countdown => if (plan.producer_value_name != null) "(count: u64, value: u8)" else "(count: u64)",
        },
    };
    return std.fmt.allocPrint(
        allocator,
        "package {s};\n\ninterface {s} {{\n  enum error-code {{ io, illegal-byte-sequence, pipe }}\n  write-via-stream: async func(data: stream<u8>) -> result<_, error-code>;\n}}\n\nworld {s} {{\n  import {s};\n  use {s}.{{error-code}};\n  export {s}: async func{s} -> result<_, error-code>;\n}}\n",
        .{ descriptor.wit.package, descriptor.wit.interface, descriptor.wit.world, descriptor.wit.interface, descriptor.wit.interface, export_name, export_params },
    );
}

pub const max_writer_capacity: usize = 16;

pub const PushOutcome = enum {
    enqueued,
    backpressure,
};

pub const PopOutcome = union(enum) {
    item: i32,
    empty,
    eof,
    aborted: i32,
};

pub const WriterLease = struct {
    token: u32,
    active: bool = true,
};

const QueueTerminal = enum {
    open,
    closed,
    aborted,
};

pub const StreamWriterQueue = struct {
    capacity: usize,
    byte_budget: ?*async_byte_budget.ByteBudget = null,
    slot_bytes: u64 = 0,
    items: [max_writer_capacity]QueueEntry = undefined,
    head: usize = 0,
    count: usize = 0,
    pending_items: [max_writer_capacity]QueueEntry = undefined,
    pending_head: usize = 0,
    pending_count: usize = 0,
    rendezvous_item: i32 = 0,
    rendezvous_allocation: ?async_byte_budget.Allocation = null,
    rendezvous_ready: bool = false,
    terminal: QueueTerminal = .open,
    abort_code: i32 = 0,
    owner_token: u32 = 1,
    producer_waiting: bool = false,
    producer_woken: bool = false,
    consumer_waiting: bool = false,
    consumer_woken: bool = false,

    pub fn init(capacity: usize) !StreamWriterQueue {
        if (capacity > max_writer_capacity) return error.InvalidWriterCapacity;
        return .{ .capacity = capacity };
    }

    pub fn init_with_budget(
        capacity: usize,
        byte_budget: *async_byte_budget.ByteBudget,
        slot_bytes: u64,
    ) !StreamWriterQueue {
        var queue = try init(capacity);
        queue.byte_budget = byte_budget;
        queue.slot_bytes = slot_bytes;
        return queue;
    }

    pub fn writer(self: *StreamWriterQueue) WriterLease {
        return .{ .token = self.owner_token };
    }

    pub fn push(self: *StreamWriterQueue, lease: *WriterLease, value: i32) !PushOutcome {
        try self.require_open(lease);
        if (self.capacity == 0) {
            if (self.consumer_waiting and self.pending_count == 0) {
                const allocation = try self.reserve_slot();
                self.rendezvous_item = value;
                self.rendezvous_allocation = allocation;
                self.rendezvous_ready = true;
                self.producer_waiting = false;
                self.producer_woken = true;
                self.consumer_waiting = false;
                self.consumer_woken = true;
                return .enqueued;
            }
            try self.ensure_pending_capacity();
            const allocation = try self.reserve_slot();
            try self.enqueue_pending(value, allocation);
            self.producer_waiting = true;
            self.producer_woken = false;
            return .backpressure;
        }
        if (self.pending_count != 0) {
            try self.ensure_pending_capacity();
            const allocation = try self.reserve_slot();
            try self.enqueue_pending(value, allocation);
            self.producer_waiting = true;
            self.producer_woken = false;
            return .backpressure;
        }
        if (self.count == self.capacity) {
            try self.ensure_pending_capacity();
            const allocation = try self.reserve_slot();
            try self.enqueue_pending(value, allocation);
            self.producer_waiting = true;
            self.producer_woken = false;
            return .backpressure;
        }
        if (self.count == 0) {
            self.consumer_waiting = false;
            self.consumer_woken = true;
        }
        const index = (self.head + self.count) % self.capacity;
        const allocation = try self.reserve_slot();
        self.items[index] = .{ .value = value, .allocation = allocation };
        self.count += 1;
        return .enqueued;
    }

    pub fn pop(self: *StreamWriterQueue) !PopOutcome {
        if (self.capacity == 0 and self.rendezvous_ready) {
            const value = self.rendezvous_item;
            if (self.rendezvous_allocation) |*allocation| {
                try allocation.release();
            }
            self.rendezvous_allocation = null;
            self.rendezvous_ready = false;
            self.producer_waiting = false;
            self.producer_woken = true;
            return .{ .item = value };
        }
        if (self.capacity == 0 and self.pending_count != 0) {
            var entry = self.dequeue_pending();
            try self.release_entry(&entry);
            self.producer_woken = true;
            self.producer_waiting = self.pending_count != 0;
            return .{ .item = entry.value };
        }
        if (self.count != 0) {
            var entry = self.items[self.head];
            try self.release_entry(&entry);
            self.items[self.head] = .{ .value = 0 };
            self.head = (self.head + 1) % self.capacity;
            self.count -= 1;
            if (self.producer_waiting) {
                self.promote_pending();
                self.producer_woken = true;
            }
            return .{ .item = entry.value };
        }
        return switch (self.terminal) {
            .open => blk: {
                self.consumer_waiting = true;
                break :blk .empty;
            },
            .closed => .eof,
            .aborted => .{ .aborted = self.abort_code },
        };
    }

    pub fn close(self: *StreamWriterQueue, lease: *WriterLease) !void {
        try self.require_open(lease);
        try self.clear_pending();
        self.terminal = .closed;
        lease.active = false;
        self.producer_waiting = false;
        self.producer_woken = true;
        self.consumer_waiting = false;
        self.consumer_woken = true;
    }

    pub fn abort(self: *StreamWriterQueue, lease: *WriterLease, code: i32) !void {
        try self.require_open(lease);
        try self.clear_pending();
        self.terminal = .aborted;
        self.abort_code = code;
        lease.active = false;
        self.producer_waiting = false;
        self.producer_woken = true;
        self.consumer_waiting = false;
        self.consumer_woken = true;
    }

    pub fn transfer(self: *StreamWriterQueue, lease: *WriterLease) !WriterLease {
        try self.require_open(lease);
        if (self.owner_token == std.math.maxInt(u32)) return error.WriterLeaseExhausted;
        lease.active = false;
        self.owner_token += 1;
        return .{ .token = self.owner_token };
    }

    fn require_open(self: *const StreamWriterQueue, lease: *const WriterLease) !void {
        if (!lease.active or lease.token != self.owner_token) return error.WriterLeaseInactive;
        if (self.terminal != .open) return error.WriterAlreadyFinalized;
    }

    fn ensure_pending_capacity(self: *const StreamWriterQueue) !void {
        if (self.pending_count == max_writer_capacity) return error.PendingWritesFull;
    }

    fn enqueue_pending(self: *StreamWriterQueue, value: i32, allocation: ?async_byte_budget.Allocation) !void {
        try self.ensure_pending_capacity();
        const index = (self.pending_head + self.pending_count) % max_writer_capacity;
        self.pending_items[index] = .{ .value = value, .allocation = allocation };
        self.pending_count += 1;
    }

    fn dequeue_pending(self: *StreamWriterQueue) QueueEntry {
        const index = self.pending_head;
        const entry = self.pending_items[index];
        self.pending_items[index] = .{ .value = 0 };
        self.pending_head = (self.pending_head + 1) % max_writer_capacity;
        self.pending_count -= 1;
        return entry;
    }

    fn promote_pending(self: *StreamWriterQueue) void {
        if (self.pending_count == 0 or self.count == self.capacity) return;
        const entry = self.dequeue_pending();
        const index = (self.head + self.count) % self.capacity;
        self.items[index] = entry;
        self.count += 1;
        self.producer_waiting = self.pending_count != 0;
    }

    fn clear_pending(self: *StreamWriterQueue) !void {
        var index = self.pending_head;
        var remaining = self.pending_count;
        while (remaining != 0) : (remaining -= 1) {
            try self.release_entry(&self.pending_items[index]);
            self.pending_items[index] = .{ .value = 0 };
            index = (index + 1) % max_writer_capacity;
        }
        self.pending_head = 0;
        self.pending_count = 0;
    }

    fn reserve_slot(self: *StreamWriterQueue) !?async_byte_budget.Allocation {
        const byte_budget = self.byte_budget orelse return null;
        var reservation = try byte_budget.reserve(self.slot_bytes);
        return try reservation.commit();
    }

    fn release_entry(self: *StreamWriterQueue, entry: *QueueEntry) !void {
        _ = self;
        if (entry.allocation) |*allocation| {
            try allocation.release();
            entry.allocation = null;
        }
    }
};

pub const PumpStep = enum {
    progressed,
    pending,
    finished,
};

pub const StreamWriterQueuePump = struct {
    queue: *StreamWriterQueue,
    lease: *WriterLease,
    source: []const i32,
    next_index: usize = 0,
    closed: bool = false,

    pub fn init(
        queue: *StreamWriterQueue,
        lease: *WriterLease,
        source: []const i32,
    ) StreamWriterQueuePump {
        return .{ .queue = queue, .lease = lease, .source = source };
    }

    pub fn step(self: *StreamWriterQueuePump) !PumpStep {
        if (self.closed) return error.StreamWriterPumpFinished;
        if (self.next_index < self.source.len) {
            _ = try self.queue.push(self.lease, self.source[self.next_index]);
            self.next_index += 1;
        }
        if (self.queue.pending_count != 0 or self.queue.rendezvous_ready) return .pending;
        if (self.next_index == self.source.len) return .finished;
        return .progressed;
    }

    pub fn finish(self: *StreamWriterQueuePump) !void {
        if (self.closed) return error.StreamWriterPumpFinished;
        if (self.next_index != self.source.len or self.queue.pending_count != 0 or self.queue.rendezvous_ready) {
            return error.StreamWriterPumpStillPending;
        }
        try self.queue.close(self.lease);
        self.closed = true;
    }
};

test "stream writer queue models FIFO backpressure and terminal wakeups" {
    var queue = try StreamWriterQueue.init(2);
    var writer = queue.writer();

    try std.testing.expectEqual(PushOutcome.enqueued, try queue.push(&writer, 10));
    try std.testing.expectEqual(PushOutcome.enqueued, try queue.push(&writer, 20));
    try std.testing.expectEqual(PushOutcome.backpressure, try queue.push(&writer, 30));
    try std.testing.expect(queue.producer_waiting);
    try std.testing.expectEqual(PopOutcome{ .item = 10 }, try queue.pop());
    try std.testing.expect(queue.producer_woken);
    try std.testing.expectEqual(PopOutcome{ .item = 20 }, try queue.pop());
    try std.testing.expectEqual(PopOutcome{ .item = 30 }, try queue.pop());
    try std.testing.expectEqual(PopOutcome.empty, try queue.pop());
}

test "stream writer queue admits slots transactionally" {
    var bytes = async_byte_budget.ByteBudget.init(8);
    var queue = try StreamWriterQueue.init_with_budget(1, &bytes, 4);
    var writer = queue.writer();

    try std.testing.expectEqual(PushOutcome.enqueued, try queue.push(&writer, 10));
    try std.testing.expectEqual(@as(u64, 4), bytes.committed_bytes());
    try std.testing.expectEqual(PushOutcome.backpressure, try queue.push(&writer, 20));
    try std.testing.expectEqual(@as(u64, 8), bytes.committed_bytes());
    try std.testing.expectError(error.ByteBudgetExceeded, queue.push(&writer, 30));
    try std.testing.expectEqual(@as(usize, 1), queue.pending_count);

    try std.testing.expectEqual(PopOutcome{ .item = 10 }, try queue.pop());
    try std.testing.expectEqual(@as(u64, 4), bytes.committed_bytes());
    try std.testing.expectEqual(PopOutcome{ .item = 20 }, try queue.pop());
    try std.testing.expectEqual(@as(u64, 0), bytes.committed_bytes());
    try queue.close(&writer);
}

test "stream writer queue releases pending slot reservations on close" {
    var bytes = async_byte_budget.ByteBudget.init(8);
    var queue = try StreamWriterQueue.init_with_budget(1, &bytes, 4);
    var writer = queue.writer();

    _ = try queue.push(&writer, 10);
    _ = try queue.push(&writer, 20);
    try queue.close(&writer);
    try std.testing.expectEqual(@as(u64, 4), bytes.committed_bytes());
    try std.testing.expectEqual(PopOutcome{ .item = 10 }, try queue.pop());
    try std.testing.expectEqual(@as(u64, 0), bytes.committed_bytes());
    try std.testing.expectEqual(PopOutcome.eof, try queue.pop());
}

test "stream writer queue transfers one lease and finalizes exactly once" {
    var queue = try StreamWriterQueue.init(1);
    var writer = queue.writer();
    var next = try queue.transfer(&writer);
    try std.testing.expectError(error.WriterLeaseInactive, queue.close(&writer));
    _ = try queue.push(&next, 7);
    try queue.close(&next);
    try std.testing.expectError(error.WriterLeaseInactive, queue.close(&next));
    try std.testing.expectEqual(PopOutcome{ .item = 7 }, try queue.pop());
    try std.testing.expectEqual(PopOutcome.eof, try queue.pop());
}

test "stream writer queue propagates abort and wakes the consumer" {
    var queue = try StreamWriterQueue.init(1);
    var writer = queue.writer();
    try queue.abort(&writer, -9);
    try std.testing.expect(queue.consumer_woken);
    try std.testing.expectEqual(PopOutcome{ .aborted = -9 }, try queue.pop());
    try std.testing.expectError(error.WriterLeaseInactive, queue.abort(&writer, -10));
}

test "stream writer queue supports capacity zero rendezvous" {
    var queue = try StreamWriterQueue.init(0);
    var writer = queue.writer();

    try std.testing.expectEqual(PopOutcome.empty, try queue.pop());
    try std.testing.expect(queue.consumer_waiting);
    try std.testing.expectEqual(PushOutcome.enqueued, try queue.push(&writer, 41));
    try std.testing.expect(queue.consumer_woken);
    try std.testing.expectEqual(PopOutcome{ .item = 41 }, try queue.pop());
    try std.testing.expectEqual(PopOutcome.empty, try queue.pop());

    var queued = try StreamWriterQueue.init(0);
    var queued_writer = queued.writer();
    try std.testing.expectEqual(PushOutcome.backpressure, try queued.push(&queued_writer, 42));
    try std.testing.expectEqual(PopOutcome{ .item = 42 }, try queued.pop());
}

test "stream writer queue drops pending writes on close but preserves accepted items" {
    var queue = try StreamWriterQueue.init(1);
    var writer = queue.writer();

    try std.testing.expectEqual(PushOutcome.enqueued, try queue.push(&writer, 10));
    try std.testing.expectEqual(PushOutcome.backpressure, try queue.push(&writer, 20));
    try std.testing.expectEqual(@as(usize, 1), queue.pending_count);
    try queue.close(&writer);
    try std.testing.expectEqual(@as(usize, 0), queue.pending_count);
    try std.testing.expect(queue.producer_woken);
    try std.testing.expectEqual(PopOutcome{ .item = 10 }, try queue.pop());
    try std.testing.expectEqual(PopOutcome.eof, try queue.pop());
}

test "stream writer queue drops pending writes on abort" {
    var queue = try StreamWriterQueue.init(1);
    var writer = queue.writer();

    try std.testing.expectEqual(PushOutcome.enqueued, try queue.push(&writer, 10));
    try std.testing.expectEqual(PushOutcome.backpressure, try queue.push(&writer, 20));
    try queue.abort(&writer, -4);
    try std.testing.expectEqual(PopOutcome{ .item = 10 }, try queue.pop());
    try std.testing.expectEqual(PopOutcome{ .aborted = -4 }, try queue.pop());
}

test "stream writer queue preserves multiple pending rendezvous writes" {
    var queue = try StreamWriterQueue.init(0);
    var writer = queue.writer();

    try std.testing.expectEqual(PushOutcome.backpressure, try queue.push(&writer, 41));
    try std.testing.expectEqual(PushOutcome.backpressure, try queue.push(&writer, 42));
    try std.testing.expectEqual(PopOutcome{ .item = 41 }, try queue.pop());
    try std.testing.expectEqual(PopOutcome{ .item = 42 }, try queue.pop());
    try std.testing.expectEqual(PopOutcome.empty, try queue.pop());
}

test "stream writer queue pump advances retained pending values before close" {
    var queue = try StreamWriterQueue.init(1);
    var writer = queue.writer();
    const source = [_]i32{ 10, 20, 30 };
    var pump = StreamWriterQueuePump.init(&queue, &writer, &source);

    try std.testing.expectEqual(PumpStep.progressed, try pump.step());
    try std.testing.expectEqual(PumpStep.pending, try pump.step());
    try std.testing.expectEqual(@as(usize, 1), queue.pending_count);
    try std.testing.expectError(error.StreamWriterPumpStillPending, pump.finish());

    try std.testing.expectEqual(PopOutcome{ .item = 10 }, try queue.pop());
    try std.testing.expectEqual(PumpStep.pending, try pump.step());
    try std.testing.expectEqual(@as(usize, 1), queue.pending_count);
    try std.testing.expectEqual(PopOutcome{ .item = 20 }, try queue.pop());
    try std.testing.expectEqual(PumpStep.finished, try pump.step());
    try pump.finish();
    try std.testing.expectEqual(PopOutcome{ .item = 30 }, try queue.pop());
    try std.testing.expectEqual(PopOutcome.eof, try queue.pop());
}

test "stream writer queue pump waits for each capacity zero rendezvous" {
    var queue = try StreamWriterQueue.init(0);
    var writer = queue.writer();
    const source = [_]i32{ 41, 42 };
    var pump = StreamWriterQueuePump.init(&queue, &writer, &source);

    try std.testing.expectEqual(PumpStep.pending, try pump.step());
    try std.testing.expectEqual(@as(usize, 1), queue.pending_count);
    try std.testing.expectEqual(PopOutcome{ .item = 41 }, try queue.pop());
    try std.testing.expectEqual(PumpStep.pending, try pump.step());
    try std.testing.expectEqual(PopOutcome{ .item = 42 }, try queue.pop());
    try std.testing.expectEqual(PumpStep.finished, try pump.step());
    try pump.finish();
    try std.testing.expectEqual(PopOutcome.eof, try queue.pop());
}

test "component writer lowering emits the registered stream ABI" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\async write(writer StreamWriter<u8>) -> Result<nil, StdoutError> {
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\StdoutError error = Io
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]write-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-new-0]write-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][stream-write-0]write-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-drop-writable-0]write-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]write") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 2\n    i32.eq\n    if (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "Frame layout: writer queue head/count/capacity at 20/24/28; pending producer at 32; terminal/error at 36/40.") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [async-frame-budget-bytes] 64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [async-byte-budget-limit] -1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $async-byte-budget-limit (export \"[async-config]byte-budget-limit\") (param $limit i64) (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"byte-budget-limit\") (param $limit i64) (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 64\n    call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 64\n    call $async-byte-budget-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "\"[export]$root\" \"[stream-new-0]write\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "\"[export]$root\" \"[stream-new-0]write-via-stream\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "\"[export]$root\" \"[async-lower][stream-write-0]write\"") != null);
}

test "component writer WIT follows the registered descriptor package" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\async write(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\ProbeError error = Io
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:stream-probe@0.1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "interface sink") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world stream-writer-probe") != null);
}

test "component writer lowering emits a bounded FIFO frame and stream write path" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\async write(writer StreamWriter<u8>) -> Result<nil, StdoutError> {
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\StdoutError error = Io
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "Frame layout: writer queue head/count/capacity at 20/24/28; pending producer at 32; terminal/error at 36/40.") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $writer-enqueue") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $stream-write") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-backpressure]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] forwarded-reader") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-queue-capacity] 1") != null);
    try std.testing.expect(std.mem.count(u8, wat, "call $writer-finalize") >= 2);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-result-tag-offset] 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-result-payload-offset] 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.load8_u offset=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 1\n      i32.add\n      i32.load8_u") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [writer-result-tag] result-area frame offset=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [writer-result-payload] result-area frame offset=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 4\n      i32.add\n      i32.load\n      call $subtask-drop") != null);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, wat, "i32.load8_u"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $payload\n    local.get $frame\n    i32.store offset=0") == null);
}

test "component writer WIT gives guest producers a parameterless export" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, StdoutError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    write_pending Future<Result<nil, StreamError>> = writer(65)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(66)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);

    try std.testing.expect(std.mem.indexOf(u8, wit, "export produce: async func() -> result<_, error-code>;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export produce: async func(data: stream<u8>)") == null);
}

test "component writer WIT gives dynamic producers a u64 count export" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce(count u64) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending Future<Result<nil, StreamError>> = writer(65)
        \\        result Result<nil, StreamError> = await(pending)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);

    try std.testing.expect(std.mem.indexOf(u8, wit, "export produce: async func(count: u64) -> result<_, error-code>;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export produce: async func()") == null);
}

test "component writer WIT gives parameterized dynamic producers a u64 and u8 export" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        write_pending Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(write_pending)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);

    try std.testing.expect(std.mem.indexOf(u8, wit, "export produce: async func(count: u64, value: u8) -> result<_, error-code>;") != null);
}

test "component writer WIT names the producer root after an async helper transfer" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async write_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async produce() -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    write_pending Future<Result<nil, StreamError>> = writer(65)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(66)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    pending Future<Result<nil, ProbeError>> = write_stream(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export produce: async func() -> result<_, error-code>;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export write_stream:") == null);
}

test "component writer lowering records async helper lease transfer" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async write_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async produce() -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    write_pending Future<Result<nil, StreamError>> = writer(65)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(66)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    pending Future<Result<nil, ProbeError>> = write_stream(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] guest-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\")") != null);
}

test "component writer lowering pumps values owned by the async helper" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async write_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    first u8 = 65
        \\    write_pending Future<Result<nil, StreamError>> = writer(first)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    second u8 = 66
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async produce() -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = write_stream(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(data (i32.const 512) \"\\41\\42\")") != null);
}

test "component writer lowering preserves a two-hop async helper lease" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    first u8 = 65
        \\    write_pending Future<Result<nil, StreamError>> = writer(first)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    second u8 = 66
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer)
        \\    return await(pending)
        \\}
        \\async produce() -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] guest-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(data (i32.const 512) \"\\41\\42\")") != null);
}

test "guest producer lowering waits on the writable stream event" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, StdoutError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    write_pending Future<Result<nil, StreamError>> = writer(65)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    write_pending_2 Future<Result<nil, StreamError>> = writer(66)
        \\    write_result_2 Result<nil, StreamError> = await(write_pending_2)
        \\    _ = write_result_2
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const -1\n    i32.eq") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $waitable-join") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 3\n    i32.eq") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $producer-write-next") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $writer-pump-step") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $writer-pump-step") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $writer-enqueue") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-index-offset] 52") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(data (i32.const 512) \"\\41\\42\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $stream-drop-writable") != null);

    const pump_start = std.mem.indexOf(u8, wat, "(func $writer-pump-step") orelse unreachable;
    const pump_end = std.mem.indexOfPos(u8, wat, pump_start, "  (func (export") orelse unreachable;
    const pump = wat[pump_start..pump_end];
    try std.testing.expect(std.mem.indexOf(u8, pump, "i32.const 8\n    i32.add\n    i32.load\n    i32.const 4\n    i32.shl\n    i32.const 2\n    i32.or") != null);
    try std.testing.expect(std.mem.indexOf(u8, pump, "i32.const 16\n            i32.add\n            i32.load\n            local.get $frame\n            i32.const 8\n            i32.add\n            i32.load\n            call $waitable-join") != null);

    const callback_start = std.mem.indexOf(u8, wat, "(func (export \"[callback][async-lift]produce\"") orelse unreachable;
    const callback_end = std.mem.indexOfPos(u8, wat, callback_start, "  (func (export \"cabi_realloc\")") orelse unreachable;
    const callback = wat[callback_start..callback_end];
    try std.testing.expect(std.mem.indexOf(u8, callback, "call $writer-source-complete") != null);
    try std.testing.expect(std.mem.indexOf(u8, callback, "call $writer-promote") == null);

    // A dropped/cancelled writable event must return the frame's waitable set,
    // not the writable stream handle that was just removed from the handle table.
    const callback_waitable_set_return =
        "local.get $frame\n        i32.const 8\n        i32.add\n        i32.load\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or";
    const callback_writable_return =
        "local.get $frame\n        i32.const 16\n        i32.add\n        i32.load\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or";
    try std.testing.expect(std.mem.indexOf(u8, callback, callback_waitable_set_return) != null);
    try std.testing.expect(std.mem.indexOf(u8, callback, callback_writable_return) == null);
}

test "dynamic guest producer lowering emits an i64 countdown pump" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce(count u64) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending Future<Result<nil, StreamError>> = writer(65)
        \\        result Result<nil, StreamError> = await(pending)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $async-run-i64 (func (param i64) (result i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\") (type $async-run-i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.store") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 65") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(data (i32.const 512) \"\\41\")") != null);

    const pump_start = std.mem.indexOf(u8, wat, "(func $writer-pump-step") orelse unreachable;
    const host_call = std.mem.indexOfPos(u8, wat, pump_start, "call $host-call") orelse return error.TestUnexpectedResult;
    const pump_call = std.mem.indexOfPos(u8, wat, pump_start, "call $writer-pump-step") orelse return error.TestUnexpectedResult;
    try std.testing.expect(host_call < pump_call);
}

test "parameterized dynamic producer lowering forwards the u8 value" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending Future<Result<nil, StreamError>> = writer(value)
        \\        result Result<nil, StreamError> = await(pending)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $async-run-i64-i32 (func (param i64 i32) (result i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\") (type $async-run-i64-i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.store8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 60") != null);
}

test "parameterized producer lowering emits a branch terminal abort" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        write_pending Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(write_pending)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    if @eq(value, 90) {
        \\        close(writer)
        \\    } else {
        \\        abort(writer, 2)
        \\    }
        \\    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(sink_pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-terminal] branch-abort-pipe") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $writer-abort") != null);

    const callback_start = std.mem.indexOf(u8, wat, "(func (export \"[callback][async-lift]produce\"") orelse unreachable;
    const callback_end = std.mem.indexOfPos(u8, wat, callback_start, "  (func (export \"cabi_realloc\")") orelse unreachable;
    const callback = wat[callback_start..callback_end];
    const callback_waitable_set_return =
        "i32.const 8\n        i32.add\n        i32.load\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or";
    const callback_writable_return =
        "i32.const 16\n        i32.add\n        i32.load\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or";
    try std.testing.expect(std.mem.indexOf(u8, callback, callback_waitable_set_return) != null);
    try std.testing.expect(std.mem.indexOf(u8, callback, callback_writable_return) == null);
}

test "parameterized helper producer lowering reuses the root countdown export" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending Future<Result<nil, StreamError>> = writer(value)
        \\        result Result<nil, StreamError> = await(pending)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] guest-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-index-offset] 52") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-value-offset] 60") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $async-run-i64-i32 (func (param i64 i32) (result i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\") (type $async-run-i64-i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]finish_stream") == null);
}

test "reordered parameterized helper producer lowering keeps semantic frame mapping" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(value u8, writer StreamWriter<u8>, count u64) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending_write Future<Result<nil, StreamError>> = writer(value)
        \\        result Result<nil, StreamError> = await(pending_write)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(value, writer, count)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] guest-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-index-offset] 52") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-value-offset] 60") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $async-run-i64-i32 (func (param i64 i32) (result i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\") (type $async-run-i64-i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]forward_stream") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]finish_stream") == null);
}

test "parameterized forwarding helper producer keeps one root countdown export" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) {
        \\            break
        \\        }
        \\        pending Future<Result<nil, StreamError>> = writer(value)
        \\        result Result<nil, StreamError> = await(pending)
        \\        _ = result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] guest-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-index-offset] 52") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-value-offset] 60") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $async-run-i64-i32 (func (param i64 i32) (result i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\") (type $async-run-i64-i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]forward_stream") == null);
}

test "parameterized two-hop forwarding helper producer keeps one root countdown export" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        pending_write Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(pending_write)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] guest-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-index-offset] 52") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-value-offset] 60") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\") (type $async-run-i64-i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]forward_stream") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]middle_stream") == null);
}

test "parameterized three-hop forwarding helper producer keeps one root countdown export" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        pending_write Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(pending_write)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async entry_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = entry_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] guest-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-index-offset] 52") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-value-offset] 60") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\") (type $async-run-i64-i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]entry_stream") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]forward_stream") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]middle_stream") == null);
}

test "parameterized four-hop forwarding helper producer keeps one root countdown export" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        pending_write Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(pending_write)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async entry_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async outer_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = entry_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = outer_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] guest-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-index-offset] 52") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-value-offset] 60") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\") (type $async-run-i64-i32)") != null);
    for ([_][]const u8{ "outer_stream", "entry_stream", "forward_stream", "middle_stream" }) |helper| {
        const marker = try std.fmt.allocPrint(std.testing.allocator, "[async-lift]{s}", .{helper});
        defer std.testing.allocator.free(marker);
        try std.testing.expect(std.mem.indexOf(u8, wat, marker) == null);
    }
}

test "parameterized five-hop forwarding helper producer keeps one root countdown export" {
    const source =
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    remaining u64 = count
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        pending_write Future<Result<nil, StreamError>> = writer(value)
        \\        write_result Result<nil, StreamError> = await(pending_write)
        \\        _ = write_result
        \\        remaining = @sub(remaining, 1)
        \\    }
        \\    defer close(writer)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\async inner_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = inner_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async entry_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async outer_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = entry_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\async produce(count u64, value u8) -> Result<nil, ProbeError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    pending Future<Result<nil, ProbeError>> = outer_stream(writer, count, value)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] guest-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-lease-transfer] async-helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-index-offset] 52") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-producer-value-offset] 60") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[async-lift]produce\") (type $async-run-i64-i32)") != null);
    for ([_][]const u8{ "outer_stream", "entry_stream", "forward_stream", "middle_stream", "inner_stream" }) |helper| {
        const marker = try std.fmt.allocPrint(std.testing.allocator, "[async-lift]{s}", .{helper});
        defer std.testing.allocator.free(marker);
        try std.testing.expect(std.mem.indexOf(u8, wat, marker) == null);
    }
}

test "guest producer lowering emits a bound u8 write value" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, StdoutError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    first u8 = 65
        \\    write_pending Future<Result<nil, StreamError>> = writer(first)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(data (i32.const 512) \"\\41\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(data (i32.const 512) \"\\00\")") == null);
    const callback_start = std.mem.indexOf(u8, wat, "(func (export \"[callback][async-lift]produce\"") orelse return error.TestUnexpectedResult;
    const callback_end = std.mem.indexOfPos(u8, wat, callback_start, "  (func (export \"cabi_realloc\")") orelse return error.TestUnexpectedResult;
    const callback = wat[callback_start..callback_end];
    const result_tag_load = std.mem.indexOf(u8, callback, "i32.load8_u offset=0") orelse return error.TestUnexpectedResult;
    const task_return = std.mem.indexOf(u8, callback, "call $task-return") orelse return error.TestUnexpectedResult;
    try std.testing.expect(result_tag_load < task_return);
}

test "guest producer realloc accounts byte budget transactionally" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, StdoutError> {
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    first u8 = 65
        \\    write_pending Future<Result<nil, StreamError>> = writer(first)
        \\    write_result Result<nil, StreamError> = await(write_pending)
        \\    _ = write_result
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    const realloc_start = std.mem.indexOf(u8, wat, "(func (export \"cabi_realloc\")") orelse return error.TestUnexpectedResult;
    const realloc = wat[realloc_start..];
    try std.testing.expect(std.mem.indexOf(u8, realloc, "call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, realloc, "call $async-byte-budget-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, realloc, "memory.grow") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "global $async-byte-budget-limit") != null);
}

test "stream mirror lowering emits source and writer callback states" {
    const source =
        \\probe_read = @host("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, ProbeError> {
        \\    source Tuple<Stream<u8>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    input Stream<u8> = @get(source, 0)
        \\    source_done Future<Result<nil, ProbeError>> = @get(source, 1)
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    defer close(writer)
        \\    remaining u64 = 3
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        read_pending Future<Result<u8, nil>> = @next(input)
        \\        item Result<u8, nil> = await(read_pending)
        \\        if @is(item, Ok) {
        \\            value u8 = item
        \\            write_pending Future<Result<nil, StreamError>> = writer(value)
        \\            write_result Result<nil, StreamError> = await(write_pending)
        \\            _ = write_result
        \\            remaining = @sub(remaining, 1)
        \\        } else { break }
        \\    }
        \\    @cancel(source_done)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_stream_mirror_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-mirror-source-read]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-mirror-writer-write]") != null);

    const wit = try emit_stream_mirror_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world stream-mirror-probe {\n  import source;\n  import sink;\n  use types.{error-code};") != null);

    const complete_start = std.mem.indexOf(u8, wat, "(func $mirror-complete") orelse return error.TestUnexpectedResult;
    const complete_end = std.mem.indexOfPos(u8, wat, complete_start, "  (func $mirror-wait-sink") orelse return error.TestUnexpectedResult;
    const complete = wat[complete_start..complete_end];
    const subtask_drop = std.mem.indexOf(u8, complete, "call $subtask-drop") orelse return error.TestUnexpectedResult;
    const mirror_finish = std.mem.indexOf(u8, complete, "call $mirror-finish-source") orelse return error.TestUnexpectedResult;
    try std.testing.expect(subtask_drop < mirror_finish);
}
