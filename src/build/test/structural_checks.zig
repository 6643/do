const std = @import("std");

pub const ModuleViolation = enum {
    legacy_top_level_name,
    legacy_facade,
    legacy_facade_import,
    collect_imports_emitter,
    wat_import_pipeline,
    storage_import_wasi,
    pipeline_reexport,
    sema_control_facade,
    sema_leaf_peer_import,
};

pub const GeneratedTextViolation = enum {
    legacy_helper,
    duplicate_formatter,
    missing_named_arg_guard,
    unindexed_placeholder,
    positional_format_args,
    unformatted_single_line,
    static_template_copy,
    embedded_template_append,
    generated_module_formatter,
    multi_line_append_slice,
    raw_template_formatter,
    body_emitter_append,
    unindexed_block_placeholder,
    single_line_formatted_block,
    single_line_static_block,
};

const Result = struct {
    violation: ?GeneratedTextViolation = null,
};

const static_template_copies = [_][]const u8{
    "allocator.dupe(u8, resource_async_core_wat)",
    "allocator.dupe(u8, resource_async_cancel_core_wat)",
    "allocator.dupe(u8, generic_record_stream_core_wat)",
    "allocator.dupe(u8, generic_async_runtime_component_wat)",
    "allocator.dupe(u8, core_wat)",
    "allocator.dupe(u8, two_await_core_wat)",
    "allocator.dupe(u8, cli_result_core_wat)",
    "allocator.dupe(u8, scalar_result_core_wat)",
    "allocator.dupe(u8, http_payload_cancel_core_wat)",
    "allocator.dupe(u8, http_response_body_core_wat)",
    "allocator.dupe(u8, http_response_body_read_core_wat)",
    "allocator.dupe(u8, http_request_empty_core_wat)",
    "allocator.dupe(u8, http_service_core_wat)",
    "allocator.dupe(u8, http_response_trailers_read_functions)",
    "allocator.dupe(u8, http_request_body_producer_imports)",
    "allocator.dupe(u8, http_request_body_producer_helpers_wat)",
    "allocator.dupe(u8, http_request_send_imports)",
    "allocator.dupe(u8, http_request_constructor_helper_wat)",
    "allocator.dupe(u8, http_request_body_constructor_helper_wat)",
};

const embedded_template_appends = [_][]const u8{
    "output.appendSlice(allocator, canonical_core_wat[0..close])",
    "output.appendSlice(allocator, canonical_core_wat[close..])",
    "appendSlice(allocator, generic_async_component_wat)",
};

const gc_sync_forbidden = [_][]const u8{
    "fn append(self: *BodyEmitter",
    "self.append(",
    "local.get ${s}",
    "local.set ${s}",
    "br ${s}",
    "i32.const {d}",
    ".{ receiver_name, field_name }",
    ".{ index_local, break_label, body_label }",
};

pub fn check_module_source(path: []const u8, source: []const u8) ?ModuleViolation {
    const basename = std.fs.path.basename(path);
    const top_level = is_build_root_file(path);
    if (top_level and (std.mem.startsWith(u8, basename, "gen_") or
        std.mem.startsWith(u8, basename, "sema_func_")))
    {
        return .legacy_top_level_name;
    }
    if (std.mem.eql(u8, basename, "gen_collect.zig") or
        std.mem.eql(u8, basename, "sema_util.zig"))
    {
        return .legacy_facade;
    }
    if (std.mem.containsAtLeast(u8, source, 1, "@import(\"sema_control.zig\")")) {
        return .legacy_facade_import;
    }
    if (std.mem.endsWith(u8, basename, ".zig") and
        (std.mem.startsWith(u8, basename, "codegen_collect_") or
            std.mem.eql(u8, basename, "codegen_collect_body.zig")) and
        contains_import_prefix(source, "codegen_emit_")
    ) {
        return .collect_imports_emitter;
    }
    if ((std.mem.startsWith(u8, basename, "wat_") or
        std.mem.startsWith(u8, basename, "runtime_")) and
        std.mem.containsAtLeast(u8, source, 1, "@import(\"codegen_pipeline.zig\")"))
    {
        return .wat_import_pipeline;
    }
    if (std.mem.eql(u8, basename, "codegen_storage_layout.zig") and
        std.mem.containsAtLeast(u8, source, 1, "@import(\"codegen_emit_wasi.zig\")"))
    {
        return .storage_import_wasi;
    }
    if (std.mem.eql(u8, basename, "codegen_pipeline.zig") and
        contains_pipeline_reexport(source))
    {
        return .pipeline_reexport;
    }
    if (std.mem.eql(u8, basename, "sema_control.zig") or
        std.mem.containsAtLeast(u8, source, 1, "@import(\"sema_control.zig\")"))
    {
        return .sema_control_facade;
    }
    if ((std.mem.eql(u8, basename, "sema_control_flow.zig") or
        std.mem.eql(u8, basename, "sema_field_checks.zig") or
        std.mem.eql(u8, basename, "sema_constraints.zig")) and
        contains_sema_peer_import(source))
    {
        return .sema_leaf_peer_import;
    }
    return null;
}

pub fn check_generated_text_source(path: []const u8, source: []const u8) ?GeneratedTextViolation {
    if (contains_any(source, &.{
        "append_fmt_generated",
        "alloc_fmt_generated",
        "append_generated",
        "alloc_generated",
    })) return .legacy_helper;

    if (!std.mem.eql(u8, std.fs.path.basename(path), "codegen_text.zig") and
        contains_duplicate_formatter(source))
    {
        return .duplicate_formatter;
    }

    if (std.mem.eql(u8, std.fs.path.basename(path), "codegen_text.zig") and
        std.mem.count(u8, source, "validate_named_format_args(@TypeOf(args));") != 4)
    {
        return .missing_named_arg_guard;
    }

    for (static_template_copies) |needle| {
        if (std.mem.containsAtLeast(u8, source, 1, needle)) return .static_template_copy;
    }
    for (embedded_template_appends) |needle| {
        if (std.mem.containsAtLeast(u8, source, 1, needle)) return .embedded_template_append;
    }

    const basename = std.fs.path.basename(path);
    if ((std.mem.eql(u8, basename, "codegen_p3_wait_for.zig") or
        std.mem.eql(u8, basename, "codegen_component_wasi_http.zig")) and
        std.mem.containsAtLeast(u8, source, 1, "std.fmt.allocPrint"))
    {
        return .generated_module_formatter;
    }

    if (std.mem.eql(u8, basename, "emit_do.zig") and
        std.mem.containsAtLeast(u8, source, 1, "appendSlice(allocator, \\\"// generated by do wit; source WIT is authoritative\\n\\n\\\")"))
    {
        return .embedded_template_append;
    }
    if (contains_multi_line_append_slice(source)) return .multi_line_append_slice;

    if (std.mem.eql(u8, basename, "codegen_gc_sync.zig")) {
        for (gc_sync_forbidden) |needle| {
            if (std.mem.containsAtLeast(u8, source, 1, needle)) return .body_emitter_append;
        }
    }

    if (check_format_calls(source)) |violation| return violation;
    return null;
}

pub fn check_module_tree(allocator: std.mem.Allocator, io: std.Io, root: []const u8) !void {
    var dir = try std.Io.Dir.openDirAbsolute(io, root, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (skip_directory(entry.basename)) walker.leave(io);
            continue;
        }
        if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        if (is_checker_file(entry.basename)) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(64 * 1024 * 1024));
        defer allocator.free(source);
        if (check_module_source(entry.path, source)) |violation| {
            std.debug.print("module boundary violation: {s}: {s}\n", .{ entry.path, @tagName(violation) });
            return error.StructuralCheckFailed;
        }
    }
}

pub fn check_generated_text_tree(allocator: std.mem.Allocator, io: std.Io, root: []const u8) !void {
    var dir = try std.Io.Dir.openDirAbsolute(io, root, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (skip_directory(entry.basename)) walker.leave(io);
            continue;
        }
        if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        if (is_checker_file(entry.basename)) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(64 * 1024 * 1024));
        defer allocator.free(source);
        if (check_generated_text_source(entry.path, source)) |violation| {
            std.debug.print("generated-text violation: {s}: {s}\n", .{ entry.path, @tagName(violation) });
            return error.StructuralCheckFailed;
        }
    }
}

fn is_build_root_file(path: []const u8) bool {
    var it = std.mem.splitBackwardsScalar(u8, path, std.fs.path.sep);
    _ = it.next();
    const parent = it.next() orelse return false;
    return std.mem.eql(u8, parent, "build");
}

fn contains_import_prefix(source: []const u8, prefix: []const u8) bool {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "@import(\"") ) |start| {
        const value_start = start + "@import(\"".len;
        if (std.mem.startsWith(u8, source[value_start..], prefix)) return true;
        cursor = value_start;
    }
    return false;
}

fn contains_pipeline_reexport(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "pub const ")) continue;
        if (std.mem.containsAtLeast(u8, line, 1, "= codegen_generics.") or
            std.mem.containsAtLeast(u8, line, 1, "= codegen_storage_layout.") or
            std.mem.containsAtLeast(u8, line, 1, "= codegen_emit_wasi.")) return true;
    }
    return false;
}

fn contains_sema_peer_import(source: []const u8) bool {
    return contains_any(source, &.{
        "@import(\"sema_control_flow.zig\")",
        "@import(\"sema_field_checks.zig\")",
        "@import(\"sema_constraints.zig\")",
    });
}

fn contains_any(source: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.containsAtLeast(u8, source, 1, needle)) return true;
    }
    return false;
}

fn contains_duplicate_formatter(source: []const u8) bool {
    var cursor: usize = 0;
    const prefix = "fn append_fmt(";
    while (std.mem.indexOfPos(u8, source, cursor, prefix)) |start| {
        const end = @min(source.len, start + 800);
        const body = source[start..end];
        if (std.mem.indexOfScalar(u8, body, '}')) |close| {
            if (std.mem.containsAtLeast(u8, body[0..close], 1, "std.fmt.allocPrint")) return true;
        } else if (std.mem.containsAtLeast(u8, body, 1, "std.fmt.allocPrint")) {
            return true;
        }
        cursor = start + prefix.len;
    }
    return false;
}

fn contains_multi_line_append_slice(source: []const u8) bool {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "appendSlice(") ) |start| {
        const end = find_call_end(source, start) orelse source.len;
        const call = source[start..end];
        if (std.mem.containsAtLeast(u8, call, 1, "\\n\\n")) return true;
        cursor = if (end < source.len) end + 1 else source.len;
    }
    return false;
}

fn find_call_end(source: []const u8, start: usize) ?usize {
    const open = std.mem.indexOfScalarPos(u8, source, start, '(') orelse return null;
    var depth: usize = 0;
    var quoted = false;
    var index = open;
    while (index < source.len) : (index += 1) {
        if (index == 0 or source[index - 1] == '\n') {
            var raw_start = index;
            while (raw_start < source.len and (source[raw_start] == ' ' or source[raw_start] == '\t')) : (raw_start += 1) {}
            if (raw_start + 1 < source.len and source[raw_start] == '\\' and source[raw_start + 1] == '\\') {
                var raw_end = raw_start;
                while (raw_end < source.len and source[raw_end] != '\n') : (raw_end += 1) {}
                index = raw_end;
                continue;
            }
        }
        const ch = source[index];
        if (ch == '"') {
            var backslashes: usize = 0;
            var cursor = index;
            while (cursor > 0 and source[cursor - 1] == '\\') : (cursor -= 1) backslashes += 1;
            if (backslashes % 2 == 0) quoted = !quoted;
            continue;
        }
        if (quoted) continue;
        if (ch == '(') {
            depth += 1;
        } else if (ch == ')') {
            depth -= 1;
            if (depth == 0) return index + 1;
        }
    }
    return null;
}

fn check_format_calls(source: []const u8) ?GeneratedTextViolation {
    var cursor: usize = 0;
    while (true) {
        const append = std.mem.indexOfPos(u8, source, cursor, "append_fmt") orelse source.len;
        const alloc = std.mem.indexOfPos(u8, source, cursor, "alloc_fmt") orelse source.len;
        const block = std.mem.indexOfPos(u8, source, cursor, "append_fmt_block") orelse source.len;
        const alloc_block = std.mem.indexOfPos(u8, source, cursor, "alloc_fmt_block") orelse source.len;
        const start = @min(@min(append, alloc), @min(block, alloc_block));
        if (start == source.len) break;
        const end = find_call_end(source, start) orelse source.len;
        const call = source[start..end];
        const is_block = start == block or start == alloc_block;
        const is_fmt = !is_block and (start == append or start == alloc);
        if (is_fmt and has_unindexed_placeholder(call)) return .unindexed_placeholder;
        if (is_block and has_unindexed_placeholder(call)) return .unindexed_block_placeholder;
        if (has_positional_tuple(call)) return .positional_format_args;
        if (is_single_line_unformatted(call)) return .unformatted_single_line;
        if (is_fmt and contains_raw_template_line(call)) {
            return .raw_template_formatter;
        }
        if (is_block) {
            const lines = block_line_count(call);
            if (lines > 0 and lines <= 1) return .single_line_formatted_block;
        }
        cursor = if (end < source.len) end + 1 else source.len;
    }

    cursor = 0;
    while (true) {
        const append = std.mem.indexOfPos(u8, source, cursor, "append_block") orelse source.len;
        const alloc = std.mem.indexOfPos(u8, source, cursor, "alloc_block") orelse source.len;
        const fmt_append = std.mem.indexOfPos(u8, source, cursor, "append_fmt_block") orelse source.len;
        const fmt_alloc = std.mem.indexOfPos(u8, source, cursor, "alloc_fmt_block") orelse source.len;
        const start = @min(@min(append, alloc), @min(fmt_append, fmt_alloc));
        if (start == source.len) break;
        if (start == fmt_append or start == fmt_alloc) {
            cursor = start + 1;
            continue;
        }
        const end = find_call_end(source, start) orelse source.len;
        if (block_line_count(source[start..end]) == 1) return .single_line_static_block;
        cursor = if (end < source.len) end + 1 else source.len;
    }
    return null;
}

fn has_unindexed_placeholder(call: []const u8) bool {
    for ([_]u8{ 's', 'd', 'i', 'f', 'x', 'X', 'b', 'o', 'c' }) |kind| {
        var needle: [3]u8 = .{ '{', kind, '}' };
        if (std.mem.containsAtLeast(u8, call, 1, &needle)) return true;
    }
    return false;
}

fn has_positional_tuple(call: []const u8) bool {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, call, cursor, ".{") ) |start| {
        if (inside_double_quoted_string(call, start)) {
            cursor = start + 2;
            continue;
        }
        var index = start + 2;
        while (index < call.len and std.ascii.isWhitespace(call[index])) : (index += 1) {}
        if (index < call.len and call[index] != '}' and call[index] != '.' and call[index] != '{') return true;
        cursor = index;
    }
    return false;
}

fn inside_double_quoted_string(source: []const u8, position: usize) bool {
    var quoted = false;
    var index: usize = 0;
    while (index < position) : (index += 1) {
        if (source[index] != '"') continue;
        var backslashes: usize = 0;
        var cursor = index;
        while (cursor > 0 and source[cursor - 1] == '\\') : (cursor -= 1) backslashes += 1;
        if (backslashes % 2 == 0) quoted = !quoted;
    }
    return quoted;
}

fn is_single_line_unformatted(call: []const u8) bool {
    if (!std.mem.containsAtLeast(u8, call, 1, ".{}")) return false;
    if (has_unindexed_placeholder(call) or std.mem.containsAtLeast(u8, call, 1, "{[")) return false;
    return std.mem.indexOfScalar(u8, call, '\n') == null;
}

fn contains_raw_template_line(call: []const u8) bool {
    var lines = std.mem.splitScalar(u8, call, '\n');
    while (lines.next()) |line| {
        var index: usize = 0;
        while (index < line.len and std.ascii.isWhitespace(line[index])) : (index += 1) {}
        if (index + 1 < line.len and line[index] == '\\' and line[index + 1] == '\\') return true;
    }
    return false;
}

fn block_line_count(call: []const u8) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, call, '\n');
    while (lines.next()) |line| {
        var index: usize = 0;
        while (index < line.len and std.ascii.isWhitespace(line[index])) : (index += 1) {}
        if (index + 1 < line.len and line[index] == '\\' and line[index + 1] == '\\') {
            var rest = line[index + 2..];
            while (rest.len > 0 and std.ascii.isWhitespace(rest[0])) rest = rest[1..];
            if (rest.len != 0) count += 1;
        }
    }
    return count;
}

fn skip_directory(name: []const u8) bool {
    return std.mem.eql(u8, name, ".git") or std.mem.eql(u8, name, ".zig-cache") or
        std.mem.eql(u8, name, "tmp") or std.mem.eql(u8, name, ".tmp");
}

fn is_checker_file(name: []const u8) bool {
    return std.mem.eql(u8, name, "structural_checks.zig") or
        std.mem.eql(u8, name, "structural_checks_test.zig");
}
