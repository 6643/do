const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const async_model = @import("codegen_async_model.zig");
const component_async_plan = @import("codegen_component_async_plan.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

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
    const plan = try require_stream_plan(tokens, registry);
    return emit_stream_wat(allocator, plan);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try require_stream_plan(tokens, registry);
    return emit_stream_wit(allocator, plan);
}

fn require_stream_plan(
    tokens: []const lexer.Token,
    registry: p3_async_manifest.Registry,
) !component_async_plan.StreamU8AcquirePlan {
    const plan = component_async_plan.StreamU8AcquirePlan.analyze(tokens, registry) catch return error.UnsupportedP3AsyncComponent;
    if (plan.read_count == 0 or plan.read_count > component_async_plan.max_stream_u8_reads) {
        return error.UnsupportedP3AsyncComponent;
    }
    const reader_shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3AsyncComponent) {
        .stream_reader_acquire => |shape| shape,
        else => return error.UnsupportedP3AsyncComponent,
    };
    if (!std.mem.eql(u8, reader_shape.element, "u8")) return error.UnsupportedP3AsyncComponent;
    validate_completion_lifecycle() catch return error.UnsupportedP3AsyncComponent;
    return plan;
}

fn emit_stream_wat(
    allocator: std.mem.Allocator,
    plan: component_async_plan.StreamU8AcquirePlan,
) ![]u8 {
    const eof_count = try std.fmt.allocPrint(allocator, "{d}", .{plan.read_count - 1});
    defer allocator.free(eof_count);
    const read_count = try std.fmt.allocPrint(allocator, "{d}", .{plan.read_count});
    defer allocator.free(read_count);
    const wit_export = try stream_wit_identifier(allocator, plan.export_name);
    defer allocator.free(wit_export);
    const task_return_export = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{wit_export});
    defer allocator.free(task_return_export);
    const async_lift_export = try std.fmt.allocPrint(allocator, "[async-lift]{s}", .{wit_export});
    defer allocator.free(async_lift_export);
    const async_callback_export = try std.fmt.allocPrint(allocator, "[callback][async-lift]{s}", .{wit_export});
    defer allocator.free(async_callback_export);
    const reader_shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3AsyncComponent) {
        .stream_reader_acquire => |shape| shape,
        else => return error.UnsupportedP3AsyncComponent,
    };

    var wat = try allocator.dupe(u8, cli_stream_stdin_core_wat);
    wat = try replace_and_free(allocator, wat, "[stream-eof-count]", eof_count);
    wat = try replace_and_free(allocator, wat, "[stream-read-count]", read_count);
    wat = try replace_and_free(allocator, wat, "[stream-module]", plan.descriptor.canonical.async_import_module);
    wat = try replace_and_free(allocator, wat, "[stream-acquire-name]", plan.descriptor.canonical.async_import_name);
    wat = try replace_and_free(allocator, wat, "[stream-read-name]", reader_shape.read.import_name);
    wat = try replace_and_free(allocator, wat, "[stream-drop-name]", reader_shape.drop_readable.import_name);
    wat = try replace_and_free(allocator, wat, "[future-drop-name]", reader_shape.future_drop_readable.import_name);
    wat = try replace_and_free(allocator, wat, "[task-return]run", task_return_export);
    wat = try replace_and_free(allocator, wat, "[async-lift]run", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]run", async_callback_export);
    return wat;
}

fn emit_stream_wit(
    allocator: std.mem.Allocator,
    plan: component_async_plan.StreamU8AcquirePlan,
) ![]u8 {
    const export_name = try stream_wit_identifier(allocator, plan.export_name);
    defer allocator.free(export_name);
    return std.fmt.allocPrint(
        allocator,
        "package {s};\n\ninterface types {{\n  enum error-code {{ io, illegal-byte-sequence, pipe }}\n}}\n\ninterface {s} {{\n  use types.{{error-code}};\n  {s}: func() -> tuple<stream<u8>, future<result<_, error-code>>>;\n}}\n\nworld {s} {{\n  import {s};\n  export {s}: async func();\n}}\n",
        .{ plan.descriptor.wit.package, plan.descriptor.wit.interface, plan.descriptor.wit.operation, plan.descriptor.wit.world, plan.descriptor.wit.interface, export_name },
    );
}

fn validate_completion_lifecycle() !void {
    var pending = async_model.FutureReadLifecycle{};
    try pending.begin_read();
    try pending.observe_read(.pending);
    try pending.request_cancel(.pending);
    try pending.observe_cancel();
    try pending.drop();

    var ready = async_model.FutureReadLifecycle{};
    try ready.begin_read();
    try ready.observe_read(.ready);
    try ready.drop();

    var reader = async_model.StreamReaderLifecycle{};
    try reader.begin_read();
    try reader.observe_read(.pending);
    try reader.observe_read(.item);
    try reader.consume_item();
    try reader.begin_read();
    try reader.observe_read(.eof);
    try reader.drop();
}

fn stream_wit_identifier(allocator: std.mem.Allocator, source_name: []const u8) ![]u8 {
    const rendered = try allocator.dupe(u8, source_name);
    for (rendered) |*ch| {
        if (ch.* == '_') ch.* = '-';
    }
    return rendered;
}

fn replace_and_free(
    allocator: std.mem.Allocator,
    input: []u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    const replaced = try replace_all(allocator, input, needle, replacement);
    allocator.free(input);
    return replaced;
}

fn replace_all(
    allocator: std.mem.Allocator,
    input: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, input);
    var count: usize = 0;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, cursor, needle)) |index| {
        count += 1;
        cursor = index + needle.len;
    }
    if (count == 0) return allocator.dupe(u8, input);
    const removed = count * needle.len;
    const added = count * replacement.len;
    const size = if (added >= removed)
        input.len + (added - removed)
    else
        input.len - (removed - added);
    var output = try allocator.alloc(u8, size);
    var input_cursor: usize = 0;
    var output_cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, input_cursor, needle)) |index| {
        const prefix = input[input_cursor..index];
        @memcpy(output[output_cursor .. output_cursor + prefix.len], prefix);
        output_cursor += prefix.len;
        @memcpy(output[output_cursor .. output_cursor + replacement.len], replacement);
        output_cursor += replacement.len;
        input_cursor = index + needle.len;
    }
    const suffix = input[input_cursor..];
    @memcpy(output[output_cursor .. output_cursor + suffix.len], suffix);
    return output;
}

// This covers the registered scalar-u8 reader with a bounded source read plan.
// A blocked read joins the reader handle itself; the callback receives the
// delivered copy-result code and resumes from the frame rather than reissuing
// that read.
const cli_stream_stdin_core_wat =
    \\(module
    \\  (type $stdin-read-via-stream (func (param i32)))
    \\  (type $stream-read (func (param i32 i32 i32) (result i32)))
    \\  (type $resource-drop (func (param i32)))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $waitable-set-drop (func (param i32)))
    \\  (type $async-run (func (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $task-return (func))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  ;; [stream-acquire]read-via-stream
    \\  (import "[stream-module]" "[stream-acquire-name]" (func $stdin-read (type $stdin-read-via-stream)))
    \\  ;; stream.read
    \\  (import "[stream-module]" "[stream-read-name]" (func $stream-read (type $stream-read)))
    \\  ;; [stream-drop-readable]
    \\  (import "[stream-module]" "[stream-drop-name]" (func $stream-drop-readable (type $resource-drop)))
    \\  (import "[stream-module]" "[future-drop-name]" (func $future-drop-readable (type $resource-drop)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (param i32 i32) (result i32)))
    \\  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (param i32 i32) (result i32)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-set-drop)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (result i32)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (param i32)))
    \\  (import "[export]$root" "[task-return]run" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 1)
    \\  ;; [async-frame-budget-bytes] 32
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
    \\    i64.const 32
    \\    call $async-byte-budget-reserve
    \\    i32.eqz
    \\    if unreachable end
    \\    global.get $frame-free
    \\    local.tee $frame
    \\    i32.eqz
    \\    if (result i32)
    \\      global.get $frame-next
    \\      local.set $frame
    \\      global.get $frame-next
    \\      i32.const 32
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
    \\    i64.const 32
    \\    call $async-byte-budget-release
    \\    local.get $frame
    \\    global.get $frame-free
    \\    i32.store
    \\    local.get $frame
    \\    global.set $frame-free
    \\  )
    \\  (func $wait-on-reader (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-join
    \\    local.get $frame
    \\    i32.load
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\  (func $cleanup (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    call $future-drop-readable
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    call $stream-drop-readable
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-set-drop
    \\    i32.const 0
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $frame-free
    \\    call $task-return
    \\    i32.const 0
    \\  )
    \\  (func $finish (param $frame i32) (result i32)
    \\    local.get $frame
    \\    call $cleanup
    \\  )
    \\  (func $start-read (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.const 16
    \\    i32.add
    \\    i32.const 1
    \\    call $stream-read
    \\    local.tee $code
    \\    i32.const -1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $wait-on-reader
    \\    else
    \\      local.get $frame
    \\      local.get $code
    \\      call $accept-read
    \\    end
    \\  )
    \\  (func $accept-read (param $frame i32) (param $code i32) (result i32)
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.load
    \\    i32.const [stream-eof-count]
    \\    i32.eq
    \\    if
    \\      ;; [stream-eof]Err(nil)
    \\      local.get $code
    \\      i32.const 1
    \\      i32.ne
    \\      if unreachable end
    \\      local.get $frame
    \\      call $finish
    \\      return
    \\    end
    \\    local.get $code
    \\    i32.const 16
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.load
    \\    i32.const 1
    \\    i32.add
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.load
    \\    i32.const [stream-read-count]
    \\    i32.eq
    \\    if
    \\      local.get $frame
    \\      call $finish
    \\      return
    \\    end
    \\    local.get $frame
    \\    call $start-read
    \\  )
    \\  (func (export "[async-lift]run") (type $async-run) (result i32) (local $frame i32)
    \\    call $frame-alloc
    \\    local.tee $frame
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $waitable-set-new
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    call $stdin-read
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    call $start-read
    \\  )
    \\  (func (export "[callback][async-lift]run") (type $async-run-callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get $event
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      local.get $payload
    \\      call $accept-read
    \\    else
    \\      local.get $event
    \\      i32.const 4
    \\      i32.eq
    \\      if (result i32)
    \\        local.get $frame
    \\        call $cleanup
    \\      else
    \\        unreachable
    \\      end
    \\    end
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

test "stream reader lowering derives the bounded read count and export name" {
    const source =
        \\stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
        \\StdinError error = Io | IllegalByteSequence | Pipe
        \\read_once() -> nil {
        \\    handles Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
        \\    reader Stream<u8> = @get(handles, 0)
        \\    completion Future<Result<nil, StdinError>> = @get(handles, 1)
        \\    pending Future<Result<u8, nil>> = @next(reader)
        \\    item Result<u8, nil> = @await(pending)
        \\    _ = item
        \\    @cancel(completion)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"[async-lift]read-once\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [async-frame-budget-bytes] 32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [async-byte-budget-limit] -1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $async-byte-budget-limit (export \"[async-config]byte-budget-limit\") (param $limit i64) (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"byte-budget-limit\") (param $limit i64) (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 32\n    call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 32\n    call $async-byte-budget-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-read-limit]") == null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export read-once: async func()") != null);
}

test "stream reader realloc accounts byte budget transactionally" {
    const source =
        \\stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
        \\StdinError error = Io | IllegalByteSequence | Pipe
        \\read_once() -> nil {
        \\    handles Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
        \\    reader Stream<u8> = @get(handles, 0)
        \\    completion Future<Result<nil, StdinError>> = @get(handles, 1)
        \\    pending Future<Result<u8, nil>> = @next(reader)
        \\    item Result<u8, nil> = @await(pending)
        \\    _ = item
        \\    @cancel(completion)
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
}
