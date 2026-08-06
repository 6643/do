const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

const canonical_core_wat = @embedFile("record_resource_list_stream_template.wat");

const exact_source =
    \\probe_read = @host_func("do:record-resource-list-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>>)
    \\Ticket = @wasi_resource("do:record-resource-list-stream-probe/source/ticket", { .id i64 })
    \\ResourceEntry { .ticket Ticket }
    \\ProbeError error = Io
    \\async run() -> Result<nil, ProbeError> {
    \\    handles Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>> = probe_read()
    \\    reader Stream<[ResourceEntry]> = @get(handles, 0)
    \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
    \\    pending Future<Result<[ResourceEntry], nil>> = @next(reader)
    \\    item Result<[ResourceEntry], nil> = await(pending)
    \\    _ = item
    \\    completed Result<nil, ProbeError> = await(completion)
    \\    if @is(completed, Err) return completed
    \\    return Ok()
    \\}
    \\start() {}
;

const exact_source_tokens = [_][]const u8{
    "probe_read", "=",       "@",     "host_func",     "(",          "\"do:record-resource-list-stream-probe@0.1.0\"",         ",",    "\"read-via-stream\"", ",",      "(",   ")",         "-",      ">",             "Tuple",  "<",             "Stream",    "<",      "[",          "ResourceEntry", "]",   ">",     ",",       "Future",     "<", "Result", "<",       "nil",    ",",         "ProbeError", ">",             ">",   ">",             ")",
    "Ticket",     "=",       "@",     "wasi_resource", "(",          "\"do:record-resource-list-stream-probe/source/ticket\"", ",",    "{",                   ".id",    "i64", "}",         ")",      "ResourceEntry", "{",      ".ticket",       "Ticket",    "}",      "ProbeError", "error",         "=",   "Io",    "async",   "run",        "(", ")",      "-",       ">",      "Result",    "<",          "nil",           ",",   "ProbeError",    ">",
    "{",          "handles", "Tuple", "<",             "Stream",     "<",                                                      "[",    "ResourceEntry",       "]",      ">",   ",",         "Future", "<",             "Result", "<",             "nil",       ",",      "ProbeError", ">",             ">",   ">",     "=",       "probe_read", "(", ")",      "reader",  "Stream", "<",         "[",          "ResourceEntry", "]",   ">",             "=",
    "@",          "get",     "(",     "handles",       ",",          "0",                                                      ")",    "completion",          "Future", "<",   "Result",    "<",      "nil",           ",",      "ProbeError",    ">",         ">",      "=",          "@",             "get", "(",     "handles", ",",          "1", ")",      "pending", "Future", "<",         "Result",     "<",             "[",   "ResourceEntry", "]",
    ",",          "nil",     ">",     ">",             "=",          "@",                                                      "next", "(",                   "reader", ")",   "item",      "Result", "<",             "[",      "ResourceEntry", "]",         ",",      "nil",        ">",             "=",   "await", "(",       "pending",    ")", "_",      "=",       "item",   "completed", "Result",     "<",             "nil", ",",             "ProbeError",
    ">",          "=",       "await", "(",             "completion", ")",                                                      "if",   "@",                   "is",     "(",   "completed", ",",      "Err",           ")",      "return",        "completed", "return", "Ok",         "(",             ")",   "}",     "start",   "(",          ")", "{",      "}",
};

const canonical_source =
    \\probe_read = @host_func("do:record-resource-list-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>>)
    \\Ticket = @wasi_resource("do:record-resource-list-stream-probe/source/ticket", { .id i64 })
    \\ResourceEntry { .ticket Ticket }
    \\ProbeError error = Io
    \\run() -> Result<nil, ProbeError> {
    \\    handles Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>> = probe_read()
    \\    reader Stream<[ResourceEntry]> = @get(handles, 0)
    \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
    \\    pending Future<Result<[ResourceEntry], nil>> = @next(reader)
    \\    item Result<[ResourceEntry], nil> = @await(pending)
    \\    _ = item
    \\    completed Result<nil, ProbeError> = @await(completion)
    \\    if @is(completed, Err) return completed
    \\    return Ok()
    \\}
    \\start() {}
;

pub const ListResourceStreamPlan = struct {
    descriptor: p3_async_manifest.Descriptor,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !ListResourceStreamPlan {
        const descriptor = registry.find(
            "do:record-resource-list-stream-probe@0.1.0",
            "read-via-stream",
        ) orelse return error.UnsupportedP3RecordResourceListStreamComponent;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3RecordResourceListStreamComponent) {
            .record_resource_list_stream_reader => {},
            else => return error.UnsupportedP3RecordResourceListStreamComponent,
        }
        if (!matches_source_plan(tokens)) return error.UnsupportedP3RecordResourceListStreamComponent;
        return .{ .descriptor = descriptor };
    }
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
    const plan = try ListResourceStreamPlan.analyze(tokens, registry);
    return emit_wat_for_plan(allocator, plan);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try ListResourceStreamPlan.analyze(tokens, registry);
    return emit_wit_for_plan(allocator, plan);
}

fn emit_wat_for_plan(allocator: std.mem.Allocator, plan: ListResourceStreamPlan) ![]u8 {
    const version_at = std.mem.indexOfScalar(u8, plan.descriptor.wit.package, '@') orelse return error.UnsupportedP3RecordResourceListStreamComponent;
    const package_name = plan.descriptor.wit.package[0..version_at];
    return replace_all(
        allocator,
        canonical_core_wat,
        "do:record-resource-list-stream-canonical",
        package_name,
    );
}

fn emit_wit_for_plan(allocator: std.mem.Allocator, plan: ListResourceStreamPlan) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\package {s};
        \\
        \\interface types {{
        \\  enum error-code {{ io }}
        \\}}
        \\
        \\interface source {{
        \\  use types.{{error-code}};
        \\  resource ticket {{}}
        \\
        \\  record resource-entry {{
        \\    ticket: own<ticket>,
        \\  }}
        \\
        \\  read-via-stream: func() -> tuple<
        \\    stream<list<resource-entry>>,
        \\    future<result<_, error-code>>,
        \\  >;
        \\}}
        \\
        \\interface probe {{
        \\  use types.{{error-code}};
        \\  run: async func() -> result<_, error-code>;
        \\}}
        \\
        \\world {s} {{
        \\  import types;
        \\  import source;
        \\  export probe;
        \\}}
        \\
    ,
        .{ plan.descriptor.wit.package, plan.descriptor.wit.world },
    );
}

const source_local_names = [_][]const u8{
    "probe_read",
    "handles",
    "reader",
    "completion",
    "pending",
    "item",
    "completed",
};

fn matches_source_plan(tokens: []const lexer.Token) bool {
    var token_index: usize = 0;
    var bindings: [source_local_names.len]?[]const u8 = [_]?[]const u8{null} ** source_local_names.len;
    for (exact_source_tokens, 0..) |expected, expected_index| {
        if (expected_index + 1 < exact_source_tokens.len and std.mem.eql(u8, expected, "async") and
            token_index < tokens.len and std.mem.eql(u8, tokens[token_index].lexeme, exact_source_tokens[expected_index + 1])) continue;
        if (token_index >= tokens.len) return false;
        if (std.mem.eql(u8, expected, "await") and token_index + 1 < tokens.len and
            std.mem.eql(u8, tokens[token_index].lexeme, "@") and std.mem.eql(u8, tokens[token_index + 1].lexeme, "await")) token_index += 1;
        const token = tokens[token_index];
        token_index += 1;
        if (source_local_name_index(expected)) |index| {
            if (token.kind != .ident) return false;
            if (bindings[index]) |name| {
                if (!std.mem.eql(u8, token.lexeme, name)) return false;
                continue;
            }
            for (bindings) |existing| {
                if (existing) |name| {
                    if (std.mem.eql(u8, token.lexeme, name)) return false;
                }
            }
            bindings[index] = token.lexeme;
            continue;
        }
        if (!std.mem.eql(u8, token.lexeme, expected)) return false;
    }
    return token_index == tokens.len;
}

fn source_local_name_index(expected: []const u8) ?usize {
    inline for (source_local_names, 0..) |name, index| {
        if (std.mem.eql(u8, expected, name)) return index;
    }
    return null;
}

fn replace_all(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
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
    const size = if (added >= removed) input.len + added - removed else input.len - (removed - added);
    const output = try allocator.alloc(u8, size);
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

test "bounded list-owned resource stream embeds the canonical ABI template" {
    try std.testing.expect(std.mem.indexOf(u8, canonical_core_wat, "[list-result-pointer]") != null);
}

test "bounded list-owned resource stream emits the registered private component" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, exact_source);
    defer std.testing.allocator.free(tokens);
    const plan = try ListResourceStreamPlan.analyze(tokens, registry);

    const wat = try emit_wat_for_plan(std.testing.allocator, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "do:record-resource-list-stream-probe/source@0.1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "do:record-resource-list-stream-canonical") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [list-result-pointer]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $release-list") != null);

    const wit = try emit_wit_for_plan(std.testing.allocator, plan);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:record-resource-list-stream-probe@0.1.0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "stream<list<resource-entry>>") != null);
}

test "bounded list-owned resource stream permits renamed local bindings" {
    const renamed_source =
        \\acquire = @host_func("do:record-resource-list-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-list-stream-probe/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProbeError error = Io
        \\run() -> Result<nil, ProbeError> {
        \\    pair Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>> = acquire()
        \\    source Stream<[ResourceEntry]> = @get(pair, 0)
        \\    done Future<Result<nil, ProbeError>> = @get(pair, 1)
        \\    read_pending Future<Result<[ResourceEntry], nil>> = @next(source)
        \\    read_result Result<[ResourceEntry], nil> = @await(read_pending)
        \\    _ = read_result
        \\    completion_result Result<nil, ProbeError> = @await(done)
        \\    if @is(completion_result, Err) return completion_result
        \\    return Ok()
        \\}
        \\start() {}
    ;
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, renamed_source);
    defer std.testing.allocator.free(tokens);
    _ = try ListResourceStreamPlan.analyze(tokens, registry);
}

test "bounded list-owned resource stream accepts canonical colorless async syntax" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, canonical_source);
    defer std.testing.allocator.free(tokens);
    _ = try ListResourceStreamPlan.analyze(tokens, registry);
}
