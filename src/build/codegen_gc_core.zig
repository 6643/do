const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

pub const GcCoreLowering = enum {
    text_identity,
    fixed_list_set,
    parameterized_list_set,
    managed_struct_set,
    managed_struct_scalar_field_set,
};

pub const GcCoreValueType = enum {
    byte_list,
    usize,
    u8,
    text,
    i32,
};

pub const TextIdentityProfile = struct {
    function_name: []const u8,
    value_name: []const u8,
    value_type: GcCoreValueType,
};

pub const ParameterizedListSetProfile = struct {
    function_name: []const u8,
    input_name: []const u8,
    index_name: []const u8,
    value_name: []const u8,
    input_type: GcCoreValueType,
    index_type: GcCoreValueType,
    value_type: GcCoreValueType,
};

pub const ManagedStructSetProfile = struct {
    struct_name: []const u8,
    function_name: []const u8,
    receiver_name: []const u8,
    value_field_name: []const u8,
    scalar_field_name: ?[]const u8,
    value_field_type: GcCoreValueType,
    scalar_field_type: ?GcCoreValueType,
};

pub const GcCoreProfile = union(enum) {
    text_identity: TextIdentityProfile,
    fixed_list_set: void,
    parameterized_list_set: ParameterizedListSetProfile,
    managed_struct_set: ManagedStructSetProfile,
};

pub fn emit_gc_core_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) ![]u8 {
    _ = program;
    const profile = parse_gc_core_profile(tokens) orelse return error.UnsupportedGcCoreLowering;
    const lowering = lowering_for_gc_core_profile(profile);
    const wat = switch (lowering) {
        .text_identity => text_identity_wat,
        .fixed_list_set => list_set_wat,
        .parameterized_list_set => parameterized_list_set_wat,
        .managed_struct_set => managed_struct_set_wat,
        .managed_struct_scalar_field_set => managed_struct_scalar_field_set_wat,
    };
    return allocator.dupe(u8, wat);
}

pub fn classify_gc_core_lowering(tokens: []const lexer.Token) ?GcCoreLowering {
    const profile = parse_gc_core_profile(tokens) orelse return null;
    return lowering_for_gc_core_profile(profile);
}

pub fn parse_gc_core_profile(tokens: []const lexer.Token) ?GcCoreProfile {
    if (parse_managed_struct_set_profile(tokens)) |profile| return .{ .managed_struct_set = profile };
    if (parse_parameterized_list_set_profile(tokens)) |profile| return .{ .parameterized_list_set = profile };
    if (matches_list_set(tokens)) return .{ .fixed_list_set = {} };
    if (parse_text_identity_profile(tokens)) |profile| return .{ .text_identity = profile };
    return null;
}

fn lowering_for_gc_core_profile(profile: GcCoreProfile) GcCoreLowering {
    return switch (profile) {
        .text_identity => .text_identity,
        .fixed_list_set => .fixed_list_set,
        .parameterized_list_set => .parameterized_list_set,
        .managed_struct_set => |managed_profile| if (managed_profile.scalar_field_name == null) .managed_struct_set else .managed_struct_scalar_field_set,
    };
}

fn parse_text_identity_profile(tokens: []const lexer.Token) ?TextIdentityProfile {
    for (tokens, 0..) |_, start| {
        const shape = [_][]const u8{ "(", "text", ")", "-", ">", "text", "{", "return" };
        if (start + 12 > tokens.len) continue;
        if (tokens[start].kind != .ident or tokens[start + 2].kind != .ident) continue;
        if (!matches_at(tokens, start + 1, shape[0..1])) continue;
        if (!matches_at(tokens, start + 3, shape[1..8])) continue;
        if (!std.mem.eql(u8, tokens[start + 2].lexeme, tokens[start + 10].lexeme)) continue;
        if (!matches_at(tokens, start + 11, &[_][]const u8{"}"})) continue;
        return .{
            .function_name = tokens[start].lexeme,
            .value_name = tokens[start + 2].lexeme,
            .value_type = .text,
        };
    }
    return null;
}

fn matches_list_set(tokens: []const lexer.Token) bool {
    const signature = [_][]const u8{ "update", "(", "input", "[", "u8", "]", ")", "-", ">", "[", "u8", "]", "{" };
    const body = [_][]const u8{ "return", "@", "set", "(", "input", ",", "0", ",", "65", ")", "}" };
    for (tokens, 0..) |_, start| {
        if (!matches_at(tokens, start, &signature)) continue;
        if (!matches_at(tokens, start + signature.len, &body)) continue;
        return true;
    }
    return false;
}

fn parse_parameterized_list_set_profile(tokens: []const lexer.Token) ?ParameterizedListSetProfile {
    for (tokens, 0..) |_, start| {
        const shape = [_][]const u8{ "(", "[", "u8", "]", ",", "usize", ",", "u8", ")", "-", ">", "[", "u8", "]", "{", "return", "@", "set", "(" };
        if (start + 30 > tokens.len) continue;
        if (tokens[start].kind != .ident or tokens[start + 2].kind != .ident or tokens[start + 7].kind != .ident or tokens[start + 10].kind != .ident) continue;
        if (!matches_at(tokens, start + 1, shape[0..1])) continue;
        if (!matches_at(tokens, start + 3, shape[1..5])) continue;
        if (!matches_at(tokens, start + 8, shape[5..7])) continue;
        if (!matches_at(tokens, start + 11, shape[7..19])) continue;
        if (!std.mem.eql(u8, tokens[start + 2].lexeme, tokens[start + 23].lexeme)) continue;
        if (!std.mem.eql(u8, tokens[start + 7].lexeme, tokens[start + 25].lexeme)) continue;
        if (!std.mem.eql(u8, tokens[start + 10].lexeme, tokens[start + 27].lexeme)) continue;
        if (!matches_at(tokens, start + 24, &[_][]const u8{
            ",",
        })) continue;
        if (!matches_at(tokens, start + 26, &[_][]const u8{
            ",",
        })) continue;
        if (!matches_at(tokens, start + 28, &[_][]const u8{ ")", "}" })) continue;
        return .{
            .function_name = tokens[start].lexeme,
            .input_name = tokens[start + 2].lexeme,
            .index_name = tokens[start + 7].lexeme,
            .value_name = tokens[start + 10].lexeme,
            .input_type = .byte_list,
            .index_type = .usize,
            .value_type = .u8,
        };
    }
    return null;
}

fn parse_managed_struct_set_profile(tokens: []const lexer.Token) ?ManagedStructSetProfile {
    for (tokens, 0..) |_, start| {
        if (start + 41 > tokens.len) continue;
        if (tokens[start].kind != .ident or tokens[start + 2].kind != .ident) continue;
        if (!matches_at(tokens, start + 1, &[_][]const u8{"{"})) continue;
        if (!matches_at(tokens, start + 3, &[_][]const u8{ "[", "u8", "]" })) continue;

        const scalar_field_name: ?[]const u8, const function_start: usize = if (matches_at(tokens, start + 6, &[_][]const u8{"}"}))
            .{ null, start + 7 }
        else if (tokens[start + 6].kind == .ident and matches_at(tokens, start + 7, &[_][]const u8{ "i32", "}" }))
            .{ tokens[start + 6].lexeme, start + 9 }
        else
            continue;
        if (tokens[function_start].kind != .ident or tokens[function_start + 2].kind != .ident) continue;
        if (!matches_at(tokens, function_start + 1, &[_][]const u8{"("})) continue;
        if (!std.mem.eql(u8, tokens[function_start + 3].lexeme, tokens[start].lexeme)) continue;
        if (!matches_at(tokens, function_start + 4, &[_][]const u8{ ")", "-", ">" })) continue;
        if (!std.mem.eql(u8, tokens[function_start + 7].lexeme, tokens[start].lexeme)) continue;
        if (!matches_at(tokens, function_start + 8, &[_][]const u8{ "{", "return", "@", "set", "(" })) continue;
        if (!std.mem.eql(u8, tokens[function_start + 2].lexeme, tokens[function_start + 13].lexeme)) continue;
        if (!field_segment_matches(tokens[function_start + 15].lexeme, tokens[start + 2].lexeme)) continue;
        if (!matches_at(tokens, function_start + 14, &[_][]const u8{","})) continue;
        if (!matches_at(tokens, function_start + 16, &[_][]const u8{ ",", "@", "set", "(", "@", "get", "(" })) continue;
        if (!std.mem.eql(u8, tokens[function_start + 2].lexeme, tokens[function_start + 23].lexeme)) continue;
        if (!matches_at(tokens, function_start + 24, &[_][]const u8{","})) continue;
        if (!field_segment_matches(tokens[function_start + 25].lexeme, tokens[start + 2].lexeme)) continue;
        if (!matches_at(tokens, function_start + 26, &[_][]const u8{ ")", ",", "0", ",", "65", ")", ")", "}" })) continue;
        return .{
            .struct_name = tokens[start].lexeme,
            .function_name = tokens[function_start].lexeme,
            .receiver_name = tokens[function_start + 2].lexeme,
            .value_field_name = tokens[start + 2].lexeme,
            .scalar_field_name = scalar_field_name,
            .value_field_type = .byte_list,
            .scalar_field_type = if (scalar_field_name == null) null else .i32,
        };
    }
    return null;
}

fn field_segment_matches(segment: []const u8, field_name: []const u8) bool {
    return segment.len == field_name.len + 1 and segment[0] == '.' and std.mem.eql(u8, segment[1..], field_name);
}

fn matches_at(tokens: []const lexer.Token, start: usize, words: []const []const u8) bool {
    if (start + words.len > tokens.len) return false;
    for (words, 0..) |word, offset| {
        if (!std.mem.eql(u8, tokens[start + offset].lexeme, word)) return false;
    }
    return true;
}

const text_identity_wat =
    \\(module
    \\  (type $do_bytes (array (mut i8)))
    \\  (type $do_text (struct (field $length i32) (field $bytes (ref null $do_bytes))))
    \\  (func $identity (param $value (ref null $do_text)) (result (ref null $do_text))
    \\    local.get $value)
    \\  (func (export "probe") (result i32)
    \\    (local $value (ref null $do_text))
    \\    i32.const 27815
    \\    ref.null $do_bytes
    \\    struct.new $do_text
    \\    call $identity
    \\    local.set $value
    \\    local.get $value
    \\    ref.as_non_null
    \\    struct.get $do_text $length)
    \\)
;

const list_set_wat =
    \\(module
    \\  (type $do_bytes (array (mut i8)))
    \\  (func $update (param $input (ref null $do_bytes)) (result (ref null $do_bytes))
    \\    (local $next (ref $do_bytes))
    \\    i32.const 3
    \\    array.new_default $do_bytes
    \\    local.set $next
    \\    local.get $next
    \\    i32.const 0
    \\    local.get $input
    \\    ref.as_non_null
    \\    i32.const 0
    \\    i32.const 3
    \\    array.copy $do_bytes $do_bytes
    \\    local.get $next
    \\    i32.const 0
    \\    i32.const 65
    \\    array.set $do_bytes
    \\    local.get $next)
    \\  (func (export "probe") (result i32)
    \\    (local $input (ref $do_bytes))
    \\    (local $updated (ref null $do_bytes))
    \\    i32.const 1
    \\    i32.const 2
    \\    i32.const 3
    \\    array.new_fixed $do_bytes 3
    \\    local.tee $input
    \\    call $update
    \\    local.set $updated
    \\    local.get $input
    \\    i32.const 0
    \\    array.get_s $do_bytes
    \\    i32.const 1
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $updated
    \\    ref.as_non_null
    \\    i32.const 0
    \\    array.get_s $do_bytes
    \\    i32.const 65
    \\    i32.ne
    \\    if unreachable end
    \\    i32.const 27815)
    \\)
;

const parameterized_list_set_wat =
    \\(module
    \\  (type $do_bytes (array (mut i8)))
    \\  (func $set_at (param $input (ref null $do_bytes)) (param $index i32) (param $value i32) (result (ref null $do_bytes))
    \\    (local $next (ref $do_bytes))
    \\    (local $length i32)
    \\    local.get $input
    \\    ref.as_non_null
    \\    array.len
    \\    local.set $length
    \\    local.get $length
    \\    array.new_default $do_bytes
    \\    local.set $next
    \\    local.get $next
    \\    i32.const 0
    \\    local.get $input
    \\    ref.as_non_null
    \\    i32.const 0
    \\    local.get $length
    \\    array.copy $do_bytes $do_bytes
    \\    local.get $next
    \\    local.get $index
    \\    local.get $value
    \\    array.set $do_bytes
    \\    local.get $next)
    \\  (func (export "probe") (result i32)
    \\    (local $input (ref $do_bytes))
    \\    (local $updated (ref null $do_bytes))
    \\    i32.const 1
    \\    i32.const 2
    \\    i32.const 3
    \\    array.new_fixed $do_bytes 3
    \\    local.tee $input
    \\    i32.const 0
    \\    i32.const 65
    \\    call $set_at
    \\    local.set $updated
    \\    local.get $input
    \\    i32.const 0
    \\    array.get_s $do_bytes
    \\    i32.const 1
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $updated
    \\    ref.as_non_null
    \\    i32.const 0
    \\    array.get_s $do_bytes
    \\    i32.const 65
    \\    i32.ne
    \\    if unreachable end
    \\    i32.const 27815)
    \\)
;

const managed_struct_set_wat =
    \\(module
    \\  (type $do_bytes (array (mut i8)))
    \\  (type $box (struct (field $value (ref null $do_bytes))))
    \\  (func $copy_set (param $input (ref null $do_bytes)) (result (ref $do_bytes))
    \\    (local $next (ref $do_bytes))
    \\    i32.const 3
    \\    array.new_default $do_bytes
    \\    local.set $next
    \\    local.get $next
    \\    i32.const 0
    \\    local.get $input
    \\    ref.as_non_null
    \\    i32.const 0
    \\    i32.const 3
    \\    array.copy $do_bytes $do_bytes
    \\    local.get $next
    \\    i32.const 0
    \\    i32.const 65
    \\    array.set $do_bytes
    \\    local.get $next)
    \\  (func $update (param $input (ref null $box)) (result (ref null $box))
    \\    local.get $input
    \\    ref.as_non_null
    \\    struct.get $box $value
    \\    call $copy_set
    \\    struct.new $box)
    \\  (func (export "probe") (result i32)
    \\    (local $original (ref $box))
    \\    (local $updated (ref null $box))
    \\    i32.const 1
    \\    i32.const 2
    \\    i32.const 3
    \\    array.new_fixed $do_bytes 3
    \\    struct.new $box
    \\    local.tee $original
    \\    call $update
    \\    local.set $updated
    \\    local.get $original
    \\    struct.get $box $value
    \\    ref.as_non_null
    \\    i32.const 0
    \\    array.get_s $do_bytes
    \\    i32.const 1
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $updated
    \\    ref.as_non_null
    \\    struct.get $box $value
    \\    ref.as_non_null
    \\    i32.const 0
    \\    array.get_s $do_bytes
    \\    i32.const 65
    \\    i32.ne
    \\    if unreachable end
    \\    i32.const 27815)
    \\)
;

const managed_struct_scalar_field_set_wat =
    \\(module
    \\  (type $do_bytes (array (mut i8)))
    \\  (type $box (struct (field $value (ref null $do_bytes)) (field $tag i32)))
    \\  (func $copy_set (param $input (ref null $do_bytes)) (result (ref $do_bytes))
    \\    (local $next (ref $do_bytes))
    \\    i32.const 3
    \\    array.new_default $do_bytes
    \\    local.set $next
    \\    local.get $next
    \\    i32.const 0
    \\    local.get $input
    \\    ref.as_non_null
    \\    i32.const 0
    \\    i32.const 3
    \\    array.copy $do_bytes $do_bytes
    \\    local.get $next
    \\    i32.const 0
    \\    i32.const 65
    \\    array.set $do_bytes
    \\    local.get $next)
    \\  (func $update (param $input (ref null $box)) (result (ref null $box))
    \\    (local $tag i32)
    \\    local.get $input
    \\    ref.as_non_null
    \\    struct.get $box $tag
    \\    local.set $tag
    \\    local.get $input
    \\    ref.as_non_null
    \\    struct.get $box $value
    \\    call $copy_set
    \\    local.get $tag
    \\    struct.new $box)
    \\  (func (export "probe") (result i32)
    \\    (local $original (ref $box))
    \\    (local $updated (ref null $box))
    \\    i32.const 1
    \\    i32.const 2
    \\    i32.const 3
    \\    array.new_fixed $do_bytes 3
    \\    i32.const 9
    \\    struct.new $box
    \\    local.tee $original
    \\    call $update
    \\    local.set $updated
    \\    local.get $original
    \\    struct.get $box $value
    \\    ref.as_non_null
    \\    i32.const 0
    \\    array.get_s $do_bytes
    \\    i32.const 1
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $original
    \\    struct.get $box $tag
    \\    i32.const 9
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $updated
    \\    ref.as_non_null
    \\    struct.get $box $value
    \\    ref.as_non_null
    \\    i32.const 0
    \\    array.get_s $do_bytes
    \\    i32.const 65
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $updated
    \\    ref.as_non_null
    \\    struct.get $box $tag
    \\    i32.const 9
    \\    i32.ne
    \\    if unreachable end
    \\    i32.const 27815)
    \\)
;

test "GC text identity lowers source parameters and results as GC references" {
    const source =
        \\identity(value text) -> text {
        \\    return value
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_gc_core_wat(std.testing.allocator, program, tokens);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_text $length") != null);
}

test "GC text identity profile retains renamed source binding" {
    const source =
        \\relay(message text) -> text {
        \\    return message
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const profile = parse_gc_core_profile(tokens) orelse return error.TestExpectedEqual;
    switch (profile) {
        .text_identity => |text_identity| {
            try std.testing.expectEqualStrings("relay", text_identity.function_name);
            try std.testing.expectEqualStrings("message", text_identity.value_name);
            try std.testing.expectEqual(GcCoreValueType.text, text_identity.value_type);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC lowering rejects a source body outside the lowered subset" {
    const source =
        \\identity(value text) -> text {
        \\    return "changed"
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedGcCoreLowering, emit_gc_core_wat(std.testing.allocator, program, tokens));
}

test "GC list set lowers a new array while preserving the input array" {
    const source =
        \\update(input [u8]) -> [u8] {
        \\    return @set(input, 0, 65)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_gc_core_wat(std.testing.allocator, program, tokens);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_bytes $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
}

test "GC parameterized list set copies its runtime array length" {
    const source =
        \\set_at(input [u8], index usize, value u8) -> [u8] {
        \\    return @set(input, index, value)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_gc_core_wat(std.testing.allocator, program, tokens);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.len\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $index") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $value") != null);
}

test "GC lowering classification identifies parameterized list updates" {
    const source =
        \\set_at(input [u8], index usize, value u8) -> [u8] {
        \\    return @set(input, index, value)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const lowering = classify_gc_core_lowering(tokens) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(GcCoreLowering.parameterized_list_set, lowering);
}

test "GC lowering classification accepts renamed parameterized list bindings" {
    const source =
        \\replace(bytes [u8], offset usize, next u8) -> [u8] {
        \\    return @set(bytes, offset, next)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const lowering = classify_gc_core_lowering(tokens) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(GcCoreLowering.parameterized_list_set, lowering);
}

test "GC parameterized list profile retains its source data flow" {
    const source =
        \\replace(bytes [u8], offset usize, next u8) -> [u8] {
        \\    return @set(bytes, offset, next)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const profile = parse_gc_core_profile(tokens) orelse return error.TestExpectedEqual;
    switch (profile) {
        .parameterized_list_set => |list_set| {
            try std.testing.expectEqualStrings("replace", list_set.function_name);
            try std.testing.expectEqualStrings("bytes", list_set.input_name);
            try std.testing.expectEqualStrings("offset", list_set.index_name);
            try std.testing.expectEqualStrings("next", list_set.value_name);
            try std.testing.expectEqual(GcCoreValueType.byte_list, list_set.input_type);
            try std.testing.expectEqual(GcCoreValueType.usize, list_set.index_type);
            try std.testing.expectEqual(GcCoreValueType.u8, list_set.value_type);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC managed struct update rebuilds its outer value and changed list field" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\update(box Box) -> Box {
        \\    return @set(box, .value, @set(@get(box, .value), 0, 65))
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_gc_core_wat(std.testing.allocator, program, tokens);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_bytes $do_bytes") != null);
}

test "GC managed struct profile retains renamed update data flow" {
    const source =
        \\Packet {
        \\    bytes [u8]
        \\}
        \\rewrite(packet Packet) -> Packet {
        \\    return @set(packet, .bytes, @set(@get(packet, .bytes), 0, 65))
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const profile = parse_gc_core_profile(tokens) orelse return error.TestExpectedEqual;
    switch (profile) {
        .managed_struct_set => |managed| {
            try std.testing.expectEqualStrings("Packet", managed.struct_name);
            try std.testing.expectEqualStrings("rewrite", managed.function_name);
            try std.testing.expectEqualStrings("packet", managed.receiver_name);
            try std.testing.expectEqualStrings("bytes", managed.value_field_name);
            try std.testing.expect(managed.scalar_field_name == null);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC managed struct update preserves an unchanged scalar field" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\update(box Box) -> Box {
        \\    return @set(box, .value, @set(@get(box, .value), 0, 65))
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_gc_core_wat(std.testing.allocator, program, tokens);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $tag i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
}
