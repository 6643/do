//! Semantic analysis — import checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_shapes = @import("sema_shapes.zig");
const sema_function_support = @import("sema_function_support.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const p3_filesystem_wit_manifest = @import("p3_filesystem_wit_manifest.zig");
const resource_abi_registry = @import("resource_abi_registry.zig");

const compact_token_range_equals = sema_tokens.compact_token_range_equals;
const contains_name = sema_tokens.contains_name;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const find_struct_field_type_end = sema_tokens.find_struct_field_type_end;
const find_top_level_comma = sema_tokens.find_top_level_comma;
const is_error_type_name = sema_tokens.is_error_type_name;
const is_host_import_decl_start = sema_tokens.is_host_import_decl_start;
const is_host_import_line = sema_tokens.is_host_import_line;
const is_lower_ident_name = sema_tokens.is_lower_ident_name;
const is_modern_import_assign = sema_tokens.is_modern_import_assign;
const is_readonly_ident_name = sema_tokens.is_readonly_ident_name;
const is_reserved_func_name = sema_tokens.is_reserved_func_name;
const is_struct_field_name = sema_tokens.is_struct_field_name;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;
const is_valid_declared_type_name = sema_tokens.is_valid_declared_type_name;
const is_payload_enum_decl_start = sema_tokens.is_payload_enum_decl_start;
const is_valid_path_seg = sema_tokens.is_valid_path_seg;
const mark_error_at = sema_tokens.mark_error_at;
const normalize_struct_field_name = sema_tokens.normalize_struct_field_name;
const parse_import_decl_end = sema_function_support.parse_import_decl_end;
const skip_top_level_import_brace = sema_function_support.skip_top_level_import_brace;
const public_func_name = sema_tokens.public_func_name;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;
const top_level_line_assign_idx = sema_tokens.top_level_line_assign_idx;
const validate_import_file_name_text = sema_tokens.validate_import_file_name_text;
const KnownWasiRecordField = sema_shapes.KnownWasiRecordField;
const LocalImportPrefix = sema_shapes.LocalImportPrefix;

const HostImportKind = enum {
    env,
    generic,
    wasi,
    resource_probe,
};

pub fn check_host_imports(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var resource_registry = try resource_abi_registry.Registry.load(allocator, @embedFile("resource_abi_registry.json"));
    defer resource_registry.deinit(allocator);

    var seen_aliases = std.ArrayList([]const u8).empty;
    defer seen_aliases.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (!is_host_import_decl_start(tokens, i)) continue;
        try validate_host_import_decl(tokens, i, &resource_registry);
        const alias = public_func_name(tokens[i].lexeme);
        if (contains_name(seen_aliases.items, alias)) return mark_error_at(tokens, i, error.DuplicateHostImportAlias);
        try seen_aliases.append(allocator, alias);
        i = (parse_import_decl_end(tokens, i) orelse i + 1) - 1;
    }
}

pub fn check_p3_async_host_imports(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);

    // Keep the admitted record-stream descriptor tied to the checked-in WIT
    // source. A source drift must reject the binding instead of silently
    // continuing with stale record facts.
    p3_filesystem_wit_manifest.validate() catch return mark_error_at(tokens, 0, error.InvalidImportDecl);

    var depth_brace: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(token, "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        const is_host_func = tok_eq(token, "host_func");
        const is_host = tok_eq(token, "host");
        if ((!is_host_func and !is_host) or idx == 0 or !tok_eq(tokens[idx - 1], "@")) continue;
        const open_idx = idx + 1;
        if (open_idx >= tokens.len or !tok_eq(tokens[open_idx], "(")) return mark_error_at(tokens, idx, error.InvalidImportDecl);
        const close_idx = find_matching(tokens, open_idx, "(", ")") catch return mark_error_at(tokens, open_idx, error.InvalidImportDecl);
        if (open_idx + 5 >= close_idx or tokens[open_idx + 1].kind != .string or !tok_eq(tokens[open_idx + 2], ",") or tokens[open_idx + 3].kind != .string or !tok_eq(tokens[open_idx + 4], ",")) {
            return mark_error_at(tokens, idx, error.InvalidImportDecl);
        }
        const locator = string_token_body(tokens[open_idx + 1].lexeme) orelse return mark_error_at(tokens, open_idx + 1, error.InvalidImportDecl);
        const member = string_token_body(tokens[open_idx + 3].lexeme) orelse return mark_error_at(tokens, open_idx + 3, error.InvalidImportDecl);
        const descriptor = registry.find(locator, member) orelse {
            // Ordinary @host declarations retain the synchronous/WASI
            // validator when no pinned async descriptor exists. @host_func is
            // the explicit P3-only form and remains strict.
            if (is_host) continue;
            return mark_error_at(tokens, open_idx + 3, error.UnknownP3AsyncHostDescriptor);
        };
        // Keep the historical @host path for scalar, HTTP, and byte-stream
        // declarations. The source-mirror check is only needed for the
        // admitted record-stream descriptor; @host_func remains fully strict.
        if (is_host and !std.mem.eql(u8, descriptor.effect, "record-stream-reader")) continue;
        const sig_start = open_idx + 5;
        if (!p3_async_signature_matches(tokens, sig_start, close_idx, descriptor)) return mark_error_at(tokens, sig_start, error.P3AsyncHostSignatureMismatch);
        const shape = p3_async_manifest.lowering_shape(descriptor);
        if (shape == null and !is_pinned_http_client_send_descriptor(descriptor)) return mark_error_at(tokens, idx, error.UnknownP3AsyncHostDescriptor);
        const is_stream_effect = if (shape) |resolved_shape| switch (resolved_shape) {
            .http_stream_reader, .stream_reader_acquire, .stream_writer, .record_stream_reader, .record_resource_list_stream_reader, .record_resource_list_stream_producer, .record_resource_list_stream_dynamic_producer, .record_resource_list_stream_batched_producer, .variant_resource_stream_reader => true,
            else => false,
        } else false;
        if (!is_stream_effect and !std.mem.eql(u8, descriptor.effect, "async")) return mark_error_at(tokens, idx, error.UnknownP3AsyncHostDescriptor);
    }
}

fn p3_async_signature_matches(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, descriptor: p3_async_manifest.Descriptor) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "(")) return false;
    const close_idx = find_matching(tokens, start_idx, "(", ")") catch return false;
    if (close_idx + 3 >= end_idx or !tok_eq(tokens[close_idx + 1], "-") or !tok_eq(tokens[close_idx + 2], ">")) return false;

    const shape = p3_async_manifest.lowering_shape(descriptor);
    if (shape == null and !is_pinned_http_client_send_descriptor(descriptor)) return false;
    if (shape) |resolved_shape| {
        switch (resolved_shape) {
            .http_stream_reader => return http_stream_reader_signature_matches(tokens, start_idx, close_idx, end_idx),
            .stream_reader_acquire => return stream_reader_signature_matches(tokens, start_idx, close_idx, end_idx),
            .record_stream_reader => return record_stream_reader_signature_matches(tokens, start_idx, close_idx, end_idx, descriptor),
            .record_resource_list_stream_reader => return record_resource_list_stream_reader_signature_matches(tokens, start_idx, close_idx, end_idx, descriptor),
            .record_resource_list_stream_producer => return record_resource_list_stream_producer_signature_matches(tokens, close_idx, end_idx, descriptor),
            .record_resource_list_stream_dynamic_producer => return record_resource_list_stream_producer_signature_matches(tokens, close_idx, end_idx, descriptor),
            .record_resource_list_stream_batched_producer => return record_resource_list_stream_producer_signature_matches(tokens, close_idx, end_idx, descriptor),
            .variant_resource_stream_reader => return variant_resource_stream_signature_matches(tokens, start_idx, close_idx, end_idx),
            .stream_writer => return stream_writer_signature_matches(tokens, close_idx, end_idx),
            .filesystem_get_type => return filesystem_get_type_signature_matches(tokens, start_idx, close_idx, end_idx),
            .filesystem_sync => return filesystem_sync_signature_matches(tokens, start_idx, close_idx, end_idx),
            else => {},
        }
    }

    var param_idx: usize = 0;
    var token_idx = start_idx + 1;
    while (token_idx < close_idx) {
        if (param_idx >= descriptor.params.len or tokens[token_idx].kind != .ident or !std.mem.eql(u8, tokens[token_idx].lexeme, descriptor.params[param_idx])) return false;
        param_idx += 1;
        token_idx += 1;
        if (token_idx == close_idx) break;
        if (!tok_eq(tokens[token_idx], ",")) return false;
        token_idx += 1;
    }
    if (param_idx != descriptor.params.len) return false;
    return token_range_matches_type_name(tokens, close_idx + 3, end_idx, descriptor.result);
}

fn filesystem_get_type_signature_matches(
    tokens: []const lexer.Token,
    params_start_idx: usize,
    params_close_idx: usize,
    end_idx: usize,
) bool {
    if (params_close_idx != params_start_idx + 2 or
        tokens[params_start_idx + 1].kind != .ident or
        !std.mem.eql(u8, tokens[params_start_idx + 1].lexeme, "Dir")) return false;
    return compact_token_range_equals(tokens, params_close_idx + 3, end_idx, "DescriptorType|FileError");
}

fn filesystem_sync_signature_matches(
    tokens: []const lexer.Token,
    params_start_idx: usize,
    params_close_idx: usize,
    end_idx: usize,
) bool {
    if (params_close_idx != params_start_idx + 2 or
        tokens[params_start_idx + 1].kind != .ident or
        !std.mem.eql(u8, tokens[params_start_idx + 1].lexeme, "Dir")) return false;
    return compact_token_range_equals(tokens, params_close_idx + 3, end_idx, "nil|SyncError");
}

fn http_stream_reader_signature_matches(
    tokens: []const lexer.Token,
    params_start_idx: usize,
    params_close_idx: usize,
    end_idx: usize,
) bool {
    if (params_close_idx != params_start_idx + 2 or tokens[params_start_idx + 1].kind != .ident or
        !std.mem.eql(u8, tokens[params_start_idx + 1].lexeme, "HttpResponse")) return false;
    const result_start = params_close_idx + 3;
    if (result_start + 20 != end_idx or
        !tok_eq(tokens[result_start], "Tuple") or !tok_eq(tokens[result_start + 1], "<") or
        !tok_eq(tokens[result_start + 2], "Stream") or !tok_eq(tokens[result_start + 3], "<") or
        !tok_eq(tokens[result_start + 4], "u8") or !tok_eq(tokens[result_start + 5], ">") or
        !tok_eq(tokens[result_start + 6], ",") or !tok_eq(tokens[result_start + 7], "Future") or
        !tok_eq(tokens[result_start + 8], "<") or !tok_eq(tokens[result_start + 9], "Result") or
        !tok_eq(tokens[result_start + 10], "<") or !tok_eq(tokens[result_start + 11], "option") or
        !tok_eq(tokens[result_start + 12], "<") or !tok_eq(tokens[result_start + 13], "trailers") or
        !tok_eq(tokens[result_start + 14], ">") or !tok_eq(tokens[result_start + 15], ",") or
        tokens[result_start + 16].kind != .ident or !tok_eq(tokens[result_start + 17], ">") or
        !tok_eq(tokens[result_start + 18], ">") or !tok_eq(tokens[result_start + 19], ">")) return false;
    return true;
}

fn stream_reader_signature_matches(
    tokens: []const lexer.Token,
    params_start_idx: usize,
    params_close_idx: usize,
    end_idx: usize,
) bool {
    if (params_close_idx != params_start_idx + 1) return false;
    const result_start = params_close_idx + 3;
    if (result_start + 17 != end_idx or
        !tok_eq(tokens[result_start], "Tuple") or
        !tok_eq(tokens[result_start + 1], "<") or
        !tok_eq(tokens[result_start + 2], "Stream") or
        !tok_eq(tokens[result_start + 3], "<") or
        !tok_eq(tokens[result_start + 4], "u8") or
        !tok_eq(tokens[result_start + 5], ">") or
        !tok_eq(tokens[result_start + 6], ",") or
        !tok_eq(tokens[result_start + 7], "Future") or
        !tok_eq(tokens[result_start + 8], "<") or
        !tok_eq(tokens[result_start + 9], "Result") or
        !tok_eq(tokens[result_start + 10], "<") or
        !tok_eq(tokens[result_start + 11], "nil") or
        !tok_eq(tokens[result_start + 12], ",") or
        tokens[result_start + 13].kind != .ident or
        !tok_eq(tokens[result_start + 14], ">") or
        !tok_eq(tokens[result_start + 15], ">") or
        !tok_eq(tokens[result_start + 16], ">")) return false;
    return true;
}

fn record_stream_reader_signature_matches(
    tokens: []const lexer.Token,
    params_start_idx: usize,
    params_close_idx: usize,
    end_idx: usize,
    descriptor: p3_async_manifest.Descriptor,
) bool {
    const filesystem_descriptor =
        std.mem.eql(u8, descriptor.locator, "wasi:filesystem/types@0.3.0-rc-2025-09-16") and
        std.mem.eql(u8, descriptor.member, "descriptor.read-directory");
    if (filesystem_descriptor) {
        if (params_close_idx != params_start_idx + 2 or
            tokens[params_start_idx + 1].kind != .ident or
            !std.mem.eql(u8, tokens[params_start_idx + 1].lexeme, "Dir")) return false;
    } else if (descriptor.params.len != 0 or params_close_idx != params_start_idx + 1) {
        return false;
    }
    const result_start = params_close_idx + 3;
    if (result_start + 17 != end_idx or
        !tok_eq(tokens[result_start], "Tuple") or !tok_eq(tokens[result_start + 1], "<") or
        !tok_eq(tokens[result_start + 2], "Stream") or !tok_eq(tokens[result_start + 3], "<") or
        tokens[result_start + 4].kind != .ident or !tok_eq(tokens[result_start + 5], ">") or
        !tok_eq(tokens[result_start + 6], ",") or !tok_eq(tokens[result_start + 7], "Future") or
        !tok_eq(tokens[result_start + 8], "<") or !tok_eq(tokens[result_start + 9], "Result") or
        !tok_eq(tokens[result_start + 10], "<") or !tok_eq(tokens[result_start + 11], "nil") or
        !tok_eq(tokens[result_start + 12], ",") or
        tokens[result_start + 13].kind != .ident or
        !tok_eq(tokens[result_start + 14], ">") or !tok_eq(tokens[result_start + 15], ">") or
        !tok_eq(tokens[result_start + 16], ">")) return false;
    const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return false) {
        .record_stream_reader => |value| value,
        else => return false,
    };
    if (!source_type_matches_element(tokens[result_start + 4].lexeme, shape.element)) return false;
    if (filesystem_descriptor) return pinned_directory_entry_record_mirror_matches(tokens);
    return true;
}

fn record_resource_list_stream_reader_signature_matches(
    tokens: []const lexer.Token,
    params_start_idx: usize,
    params_close_idx: usize,
    end_idx: usize,
    descriptor: p3_async_manifest.Descriptor,
) bool {
    if (params_close_idx != params_start_idx + 1) return false;
    const result_start = params_close_idx + 3;
    if (result_start + 19 != end_idx or
        !tok_eq(tokens[result_start], "Tuple") or
        !tok_eq(tokens[result_start + 1], "<") or
        !tok_eq(tokens[result_start + 2], "Stream") or
        !tok_eq(tokens[result_start + 3], "<") or
        !tok_eq(tokens[result_start + 4], "[") or
        tokens[result_start + 5].kind != .ident or
        !tok_eq(tokens[result_start + 6], "]") or
        !tok_eq(tokens[result_start + 7], ">") or
        !tok_eq(tokens[result_start + 8], ",") or
        !tok_eq(tokens[result_start + 9], "Future") or
        !tok_eq(tokens[result_start + 10], "<") or
        !tok_eq(tokens[result_start + 11], "Result") or
        !tok_eq(tokens[result_start + 12], "<") or
        !tok_eq(tokens[result_start + 13], "nil") or
        !tok_eq(tokens[result_start + 14], ",") or
        tokens[result_start + 15].kind != .ident or
        !tok_eq(tokens[result_start + 16], ">") or
        !tok_eq(tokens[result_start + 17], ">") or
        !tok_eq(tokens[result_start + 18], ">")) return false;

    const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return false) {
        .record_resource_list_stream_reader => |value| value,
        else => return false,
    };
    return source_type_matches_element(tokens[result_start + 5].lexeme, shape.element) and
        std.mem.eql(u8, tokens[result_start + 15].lexeme, "ProbeError");
}

fn record_resource_list_stream_producer_signature_matches(
    tokens: []const lexer.Token,
    params_close_idx: usize,
    end_idx: usize,
    descriptor: p3_async_manifest.Descriptor,
) bool {
    if (params_close_idx < 7 or
        !tok_eq(tokens[params_close_idx - 7], "(") or
        !tok_eq(tokens[params_close_idx - 6], "StreamWriter") or
        !tok_eq(tokens[params_close_idx - 5], "<") or
        !tok_eq(tokens[params_close_idx - 4], "[") or
        tokens[params_close_idx - 3].kind != .ident or
        !tok_eq(tokens[params_close_idx - 2], "]") or
        !tok_eq(tokens[params_close_idx - 1], ">")) return false;

    const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return false) {
        .record_resource_list_stream_producer => |value| value,
        .record_resource_list_stream_dynamic_producer => |value| value,
        .record_resource_list_stream_batched_producer => |value| value,
        else => return false,
    };
    if (!source_type_matches_element(tokens[params_close_idx - 3].lexeme, shape.element)) return false;

    const result_start = params_close_idx + 3;
    if (result_start + 6 != end_idx or
        !tok_eq(tokens[result_start], "Result") or
        !tok_eq(tokens[result_start + 1], "<") or
        !tok_eq(tokens[result_start + 2], "nil") or
        !tok_eq(tokens[result_start + 3], ",") or
        tokens[result_start + 4].kind != .ident or
        !std.mem.eql(u8, tokens[result_start + 4].lexeme, "ProducerError") or
        !tok_eq(tokens[result_start + 5], ">")) return false;
    return true;
}

fn variant_resource_stream_signature_matches(
    tokens: []const lexer.Token,
    params_start_idx: usize,
    params_close_idx: usize,
    end_idx: usize,
) bool {
    if (params_close_idx != params_start_idx + 1) return false;
    const result_start = params_close_idx + 3;
    if (result_start + 21 != end_idx or
        !tok_eq(tokens[result_start], "Tuple") or !tok_eq(tokens[result_start + 1], "<") or
        !tok_eq(tokens[result_start + 2], "Stream") or !tok_eq(tokens[result_start + 3], "<") or
        !tok_eq(tokens[result_start + 4], "Ticket") or !tok_eq(tokens[result_start + 5], "|") or
        !tok_eq(tokens[result_start + 6], "nil") or !tok_eq(tokens[result_start + 7], "|") or
        !tok_eq(tokens[result_start + 8], "EventError") or !tok_eq(tokens[result_start + 9], ">") or
        !tok_eq(tokens[result_start + 10], ",") or !tok_eq(tokens[result_start + 11], "Future") or
        !tok_eq(tokens[result_start + 12], "<") or !tok_eq(tokens[result_start + 13], "Result") or
        !tok_eq(tokens[result_start + 14], "<") or !tok_eq(tokens[result_start + 15], "nil") or
        !tok_eq(tokens[result_start + 16], ",") or !tok_eq(tokens[result_start + 17], "EventError") or
        !tok_eq(tokens[result_start + 18], ">") or !tok_eq(tokens[result_start + 19], ">") or
        !tok_eq(tokens[result_start + 20], ">")) return false;
    return true;
}

fn source_type_matches_element(source_type: []const u8, element: []const u8) bool {
    var source_index: usize = 0;
    var element_index: usize = 0;
    for (source_type) |char| {
        if (char >= 'A' and char <= 'Z' and source_index != 0) {
            if (element_index >= element.len or element[element_index] != '-') return false;
            element_index += 1;
        }
        if (element_index >= element.len) return false;
        const expected = if (char >= 'A' and char <= 'Z') char + ('a' - 'A') else char;
        if (element[element_index] != expected) return false;
        source_index += 1;
        element_index += 1;
    }
    return element_index == element.len;
}

fn is_pinned_http_client_send_descriptor(descriptor: p3_async_manifest.Descriptor) bool {
    return std.mem.eql(u8, descriptor.locator, "wasi:http/client@0.3.0-rc-2025-09-16") and
        std.mem.eql(u8, descriptor.member, "send");
}

fn stream_writer_signature_matches(tokens: []const lexer.Token, params_close_idx: usize, end_idx: usize) bool {
    const params_start = params_close_idx;
    if (params_start < 5 or
        !tok_eq(tokens[params_start - 5], "(") or
        !tok_eq(tokens[params_start - 4], "StreamWriter") or
        !tok_eq(tokens[params_start - 3], "<") or
        !tok_eq(tokens[params_start - 2], "u8") or
        !tok_eq(tokens[params_start - 1], ">")) return false;
    const result_start = params_close_idx + 3;
    if (result_start + 6 != end_idx or
        !tok_eq(tokens[result_start], "Result") or
        !tok_eq(tokens[result_start + 1], "<") or
        !tok_eq(tokens[result_start + 2], "nil") or
        !tok_eq(tokens[result_start + 3], ",") or
        tokens[result_start + 4].kind != .ident or
        !tok_eq(tokens[result_start + 5], ">")) return false;
    return true;
}

fn token_range_matches_type_name(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected: []const u8) bool {
    var expected_idx: usize = 0;
    var token_idx = start_idx;
    while (token_idx < end_idx) : (token_idx += 1) {
        const lexeme = tokens[token_idx].lexeme;
        if (expected_idx + lexeme.len > expected.len) return false;
        if (!std.mem.eql(u8, expected[expected_idx .. expected_idx + lexeme.len], lexeme)) return false;
        expected_idx += lexeme.len;
    }
    return expected_idx == expected.len;
}

fn resource_probe_signature_matches(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    descriptor: resource_abi_registry.Descriptor,
) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "(")) return false;
    const close_idx = find_matching(tokens, start_idx, "(", ")") catch return false;
    if (close_idx + 3 >= end_idx or !tok_eq(tokens[close_idx + 1], "-") or !tok_eq(tokens[close_idx + 2], ">")) return false;

    var param_idx: usize = 0;
    var token_idx = start_idx + 1;
    while (token_idx < close_idx) {
        if (param_idx >= descriptor.params.len) return false;
        const next = parse_wit_type(tokens, token_idx, close_idx) orelse return false;
        if (!resource_probe_type_matches(tokens, token_idx, next, descriptor, descriptor.params[param_idx].type_name)) return false;
        param_idx += 1;
        token_idx = next;
        if (token_idx == close_idx) break;
        if (!tok_eq(tokens[token_idx], ",")) return false;
        token_idx += 1;
    }
    if (param_idx != descriptor.params.len) return false;
    return resource_probe_type_matches(tokens, close_idx + 3, end_idx, descriptor, descriptor.result.type_name);
}

fn resource_probe_type_matches(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    descriptor: resource_abi_registry.Descriptor,
    expected: []const u8,
) bool {
    if (std.mem.eql(u8, expected, descriptor.resource)) {
        if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
        return resource_probe_declared_type_matches(tokens, tokens[start_idx].lexeme, descriptor.resource_path);
    }
    if (descriptor.result_resource) |result_resource| {
        if (std.mem.eql(u8, expected, result_resource)) {
            if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
            return resource_probe_declared_type_matches(tokens, tokens[start_idx].lexeme, descriptor.result_resource_path.?);
        }
        if (descriptor.result_error_resource) |error_resource| {
            if (std.mem.eql(u8, expected, error_resource)) {
                if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
                return resource_probe_declared_type_matches(tokens, tokens[start_idx].lexeme, descriptor.result_error_resource_path.?);
            }
            if (owned_result_type_matches_resources(expected, result_resource, error_resource)) {
                return owned_result_payload_types_match(
                    tokens,
                    start_idx,
                    end_idx,
                    descriptor.result_resource_path.?,
                    descriptor.result_error_resource_path.?,
                );
            }
        }
        if (owned_result_type_matches_resource(expected, result_resource)) {
            return owned_result_payload_type_matches(tokens, start_idx, end_idx, descriptor.result_resource_path.?);
        }
    }
    return token_range_matches_type_name(tokens, start_idx, end_idx, expected);
}

fn resource_probe_declared_type_matches(
    tokens: []const lexer.Token,
    type_name: []const u8,
    resource_path: []const u8,
) bool {
    var i: usize = 0;
    while (i + 5 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, type_name)) continue;
        if (!tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or !tok_eq(tokens[i + 3], "wasi_resource") or !tok_eq(tokens[i + 4], "(") or tokens[i + 5].kind != .string) continue;
        const declared_resource_path = string_token_body(tokens[i + 5].lexeme) orelse continue;
        if (std.mem.eql(u8, resource_path, declared_resource_path)) return true;
    }
    return false;
}

fn owned_result_type_matches_resource(type_name: []const u8, resource: []const u8) bool {
    const prefix = "result<";
    const suffix = ",error-code>";
    return type_name.len == prefix.len + resource.len + suffix.len and
        std.mem.eql(u8, type_name[0..prefix.len], prefix) and
        std.mem.eql(u8, type_name[prefix.len .. prefix.len + resource.len], resource) and
        std.mem.eql(u8, type_name[prefix.len + resource.len ..], suffix);
}

fn owned_result_type_matches_resources(type_name: []const u8, result_resource: []const u8, error_resource: []const u8) bool {
    const prefix = "result<";
    const separator = ",";
    const suffix = ">";
    const expected_len = prefix.len + result_resource.len + separator.len + error_resource.len + suffix.len;
    return type_name.len == expected_len and
        std.mem.eql(u8, type_name[0..prefix.len], prefix) and
        std.mem.eql(u8, type_name[prefix.len .. prefix.len + result_resource.len], result_resource) and
        std.mem.eql(u8, type_name[prefix.len + result_resource.len .. prefix.len + result_resource.len + separator.len], separator) and
        std.mem.eql(u8, type_name[prefix.len + result_resource.len + separator.len .. prefix.len + result_resource.len + separator.len + error_resource.len], error_resource) and
        std.mem.eql(u8, type_name[expected_len - suffix.len ..], suffix);
}

fn owned_result_payload_type_matches(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    resource_path: []const u8,
) bool {
    if (end_idx != start_idx + 6 or tokens[start_idx].kind != .ident) return false;
    if (!std.mem.eql(u8, tokens[start_idx].lexeme, "Result") and !std.mem.eql(u8, tokens[start_idx].lexeme, "result")) return false;
    if (!tok_eq(tokens[start_idx + 1], "<") or tokens[start_idx + 2].kind != .ident or !tok_eq(tokens[start_idx + 3], ",") or tokens[start_idx + 4].kind != .ident or !tok_eq(tokens[start_idx + 5], ">")) return false;
    return resource_probe_declared_type_matches(tokens, tokens[start_idx + 2].lexeme, resource_path);
}

fn owned_result_payload_types_match(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    result_resource_path: []const u8,
    error_resource_path: []const u8,
) bool {
    if (end_idx != start_idx + 6 or tokens[start_idx].kind != .ident) return false;
    if (!std.mem.eql(u8, tokens[start_idx].lexeme, "Result") and !std.mem.eql(u8, tokens[start_idx].lexeme, "result")) return false;
    if (!tok_eq(tokens[start_idx + 1], "<") or tokens[start_idx + 2].kind != .ident or !tok_eq(tokens[start_idx + 3], ",") or tokens[start_idx + 4].kind != .ident or !tok_eq(tokens[start_idx + 5], ">")) return false;
    return resource_probe_declared_type_matches(tokens, tokens[start_idx + 2].lexeme, result_resource_path) and
        resource_probe_declared_type_matches(tokens, tokens[start_idx + 4].lexeme, error_resource_path);
}

test "resource ABI signatures map an owned Result payload to its distinct resource declaration" {
    const json =
        \\{"schema":1,"descriptors":[
        \\  {"locator":"wasi:http/client@0.3.0-rc-2025-09-16","member":"send","resource":"request","resource_path":"http/types/request","result_resource":"response","result_resource_path":"http/types/response","params":[{"type":"request","ownership":"own"}],"result":{"type":"result<response,error-code>","ownership":"own"},"resource_drop":false}
        \\]}
    ;
    var registry = try resource_abi_registry.Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send") orelse return error.TestUnexpectedResult;

    const source =
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\(HttpRequest) -> Result<HttpResponse, HttpError>
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var sig_start: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, "(")) sig_start = idx;
    }
    try std.testing.expect(resource_probe_signature_matches(tokens, sig_start, tokens.len, descriptor));
}

test "resource ABI signatures reject a Result payload declared at another resource path" {
    const json =
        \\{"schema":1,"descriptors":[
        \\  {"locator":"wasi:http/client@0.3.0-rc-2025-09-16","member":"send","resource":"request","resource_path":"http/types/request","result_resource":"response","result_resource_path":"http/types/response","params":[{"type":"request","ownership":"own"}],"result":{"type":"result<response,error-code>","ownership":"own"},"resource_drop":false}
        \\]}
    ;
    var registry = try resource_abi_registry.Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send") orelse return error.TestUnexpectedResult;

    const source =
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/not-response", { .id i64 })
        \\HttpError error = HttpFailure
        \\(HttpRequest) -> Result<HttpResponse, HttpError>
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var sig_start: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, "(")) sig_start = idx;
    }
    try std.testing.expect(!resource_probe_signature_matches(tokens, sig_start, tokens.len, descriptor));
}

test "owned resource Result signatures validate both private HTTP payload paths" {
    const json =
        \\{"schema":1,"descriptors":[
        \\  {"locator":"do:resource-probe-owned-error/http@0.1.0","member":"send","resource":"request","resource_path":"do:resource-probe-owned-error/http/request","result_resource":"response","result_resource_path":"do:resource-probe-owned-error/http/response","result_error_resource":"error-resource","result_error_resource_path":"do:resource-probe-owned-error/http/error-resource","params":[{"type":"request","ownership":"own"}],"result":{"type":"result<response,error-resource>","ownership":"own"},"resource_drop":false}
        \\]}
    ;
    var registry = try resource_abi_registry.Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:resource-probe-owned-error/http@0.1.0", "send") orelse return error.TestUnexpectedResult;

    const source =
        \\HttpRequest = @wasi_resource("do:resource-probe-owned-error/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe-owned-error/http/response", { .id i64 })
        \\HttpErrorResource = @wasi_resource("do:resource-probe-owned-error/http/error-resource", { .id i64 })
        \\(HttpRequest) -> Result<HttpResponse, HttpErrorResource>
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var sig_start: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, "(")) sig_start = idx;
    }
    try std.testing.expect(resource_probe_signature_matches(tokens, sig_start, tokens.len, descriptor));
}

test "owned resource Result signatures reject a drifted private HTTP error path" {
    const json =
        \\{"schema":1,"descriptors":[
        \\  {"locator":"do:resource-probe-owned-error/http@0.1.0","member":"send","resource":"request","resource_path":"do:resource-probe-owned-error/http/request","result_resource":"response","result_resource_path":"do:resource-probe-owned-error/http/response","result_error_resource":"error-resource","result_error_resource_path":"do:resource-probe-owned-error/http/error-resource","params":[{"type":"request","ownership":"own"}],"result":{"type":"result<response,error-resource>","ownership":"own"},"resource_drop":false}
        \\]}
    ;
    var registry = try resource_abi_registry.Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:resource-probe-owned-error/http@0.1.0", "send") orelse return error.TestUnexpectedResult;

    const source =
        \\HttpRequest = @wasi_resource("do:resource-probe-owned-error/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe-owned-error/http/response", { .id i64 })
        \\HttpErrorResource = @wasi_resource("do:resource-probe-owned-error/http/other-error", { .id i64 })
        \\(HttpRequest) -> Result<HttpResponse, HttpErrorResource>
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var sig_start: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, "(")) sig_start = idx;
    }
    try std.testing.expect(!resource_probe_signature_matches(tokens, sig_start, tokens.len, descriptor));
}

pub fn check_local_imports(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (!is_modern_import_assign(tokens, i)) continue;

        const eq_idx = top_level_line_assign_idx(tokens, i) orelse return mark_error_at(tokens, i, error.InvalidImportDecl);
        const at_idx = eq_idx + 1;
        if (is_host_import_line(tokens, at_idx)) {
            i = (parse_import_decl_end(tokens, i) orelse i + 1) - 1;
            continue;
        }

        try validate_local_import_decl(tokens, i, at_idx);
        i = (parse_import_decl_end(tokens, i) orelse i + 1) - 1;
    }
}

fn validate_host_import_decl(tokens: []const lexer.Token, name_idx: usize, resource_registry: *const resource_abi_registry.Registry) !void {
    if (tokens[name_idx].kind != .ident) return mark_error_at(tokens, name_idx, error.InvalidImportDecl);
    const alias = public_func_name(tokens[name_idx].lexeme);
    if (!is_valid_import_name(alias)) return mark_error_at(tokens, name_idx, error.InvalidImportDecl);
    if (!is_lower_ident_name(alias)) return mark_error_at(tokens, name_idx, error.InvalidImportDecl);

    const eq_idx = top_level_line_assign_idx(tokens, name_idx) orelse return mark_error_at(tokens, name_idx, error.InvalidImportDecl);
    const at_idx = eq_idx + 1;
    if (at_idx + 1 < tokens.len and tok_eq(tokens[at_idx], "@") and tok_eq(tokens[at_idx + 1], "host_func")) return;
    try validate_host_import_line(tokens, at_idx, parse_import_decl_end(tokens, name_idx) orelse return mark_error_at(tokens, at_idx, error.InvalidImportDecl), resource_registry);
}

fn is_valid_import_name(name: []const u8) bool {
    return (is_valid_declared_type_name(name) or is_lower_ident_name(name) or is_readonly_ident_name(name)) and !is_reserved_func_name(name);
}

fn import_alias_matches_target(alias: []const u8, target: []const u8) bool {
    if (is_valid_declared_type_name(target)) return is_valid_declared_type_name(alias);
    if (is_lower_ident_name(target)) return is_lower_ident_name(alias);
    if (is_readonly_ident_name(target)) return is_readonly_ident_name(alias);
    return false;
}

fn validate_local_import_decl(tokens: []const lexer.Token, name_idx: usize, at_idx: usize) !void {
    if (tokens[name_idx].kind != .ident) return mark_error_at(tokens, name_idx, error.InvalidImportDecl);
    if (tokens[name_idx].lexeme.len != 0 and tokens[name_idx].lexeme[0] == '.') return mark_error_at(tokens, name_idx, error.InvalidImportDecl);
    if (!is_valid_import_name(tokens[name_idx].lexeme)) return mark_error_at(tokens, name_idx, error.InvalidImportDecl);

    const close_idx = parse_import_decl_end(tokens, name_idx) orelse return mark_error_at(tokens, at_idx, error.InvalidImportDecl);
    if (at_idx + 7 != close_idx) return mark_error_at(tokens, at_idx, error.InvalidImportDecl);
    if (tokens[at_idx + 1].kind != .ident or !std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib")) return mark_error_at(tokens, at_idx, error.InvalidImportDecl);
    if (!tok_eq(tokens[at_idx + 2], "(")) return mark_error_at(tokens, at_idx + 2, error.InvalidImportDecl);
    if (tokens[at_idx + 3].kind != .string) return mark_error_at(tokens, at_idx + 3, error.InvalidImportDecl);
    if (!tok_eq(tokens[at_idx + 4], ",")) return mark_error_at(tokens, at_idx + 4, error.InvalidImportDecl);
    if (tokens[at_idx + 5].kind != .ident) return mark_error_at(tokens, at_idx + 5, error.InvalidImportDecl);

    var file_path = string_token_body(tokens[at_idx + 3].lexeme) orelse return mark_error_at(tokens, at_idx + 3, error.InvalidImportDecl);
    const target = tokens[at_idx + 5].lexeme;
    var prefix: LocalImportPrefix = .std;
    if (std.mem.startsWith(u8, file_path, "./")) {
        prefix = .local;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "~/")) {
        prefix = .dep;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "/")) {
        return mark_error_at(tokens, at_idx + 3, error.InvalidImportDecl);
    }

    try validate_import_file_name_text(tokens, at_idx + 3, file_path, prefix);
    if (!is_valid_import_name(target)) return mark_error_at(tokens, at_idx + 3, error.InvalidImportDecl);
    if (!import_alias_matches_target(tokens[name_idx].lexeme, target)) return mark_error_at(tokens, name_idx, error.InvalidImportDecl);
}

fn validate_host_import_line(
    tokens: []const lexer.Token,
    at_idx: usize,
    import_end: usize,
    resource_registry: *const resource_abi_registry.Registry,
) !void {
    // @host(locator, member, sig)
    if (at_idx + 9 > import_end) return mark_error_at(tokens, at_idx, error.InvalidImportDecl);
    if (!tok_eq(tokens[at_idx], "@")) return mark_error_at(tokens, at_idx, error.InvalidImportDecl);
    if (tokens[at_idx + 1].kind != .ident) return mark_error_at(tokens, at_idx + 1, error.InvalidImportDecl);
    if (!std.mem.eql(u8, tokens[at_idx + 1].lexeme, "host")) return mark_error_at(tokens, at_idx + 1, error.InvalidImportDecl);
    if (!tok_eq(tokens[at_idx + 2], "(")) return mark_error_at(tokens, at_idx + 2, error.InvalidImportDecl);
    if (tokens[at_idx + 3].kind != .string) return mark_error_at(tokens, at_idx + 3, error.InvalidImportDecl);
    if (!tok_eq(tokens[at_idx + 4], ",")) return mark_error_at(tokens, at_idx + 4, error.InvalidImportDecl);
    if (tokens[at_idx + 5].kind != .string) return mark_error_at(tokens, at_idx + 5, error.InvalidImportDecl);
    if (!tok_eq(tokens[at_idx + 6], ",")) return mark_error_at(tokens, at_idx + 6, error.InvalidImportDecl);

    const locator = string_token_body(tokens[at_idx + 3].lexeme) orelse return mark_error_at(tokens, at_idx + 3, error.InvalidImportDecl);
    const member = string_token_body(tokens[at_idx + 5].lexeme) orelse return mark_error_at(tokens, at_idx + 5, error.InvalidImportDecl);
    const kind = try validate_host_import_locator_member(tokens, at_idx + 3, at_idx + 5, locator, member, resource_registry);
    const sig_start = at_idx + 7;
    if (sig_start >= import_end - 1) return mark_error_at(tokens, at_idx + 6, error.InvalidImportDecl);
    try validate_host_signature(tokens, sig_start, import_end - 1, kind);
    if (kind == .wasi) {
        const target = try build_wasi_target_key(tokens, at_idx + 3, locator, member);
        try validate_known_wasi_signature(tokens, at_idx + 3, target, sig_start, import_end - 1);
    }
    if (kind == .resource_probe) {
        const descriptor = resource_registry.find(locator, member) orelse unreachable;
        if (!resource_probe_signature_matches(tokens, sig_start, import_end - 1, descriptor)) {
            return mark_error_at(tokens, sig_start, error.InvalidImportDecl);
        }
    }
}

/// Validate locator+member and return host kind. Does not allocate.
fn validate_host_import_locator_member(
    tokens: []const lexer.Token,
    locator_idx: usize,
    member_idx: usize,
    locator: []const u8,
    member: []const u8,
    resource_registry: *const resource_abi_registry.Registry,
) !HostImportKind {
    if (std.mem.eql(u8, locator, "env")) {
        if (!is_valid_path_seg(member)) return mark_error_at(tokens, member_idx, error.InvalidImportDecl);
        return .env;
    }
    if (std.mem.startsWith(u8, locator, "wasi:")) {
        if (!is_valid_wasi_host_locator(locator)) return mark_error_at(tokens, locator_idx, error.InvalidImportDecl);
        if (!is_valid_wasi_host_member(member)) return mark_error_at(tokens, member_idx, error.InvalidImportDecl);
        return .wasi;
    }
    if (resource_registry.find(locator, member) != null) return .resource_probe;
    if (!is_valid_wit_host_locator(locator)) return mark_error_at(tokens, locator_idx, error.InvalidImportDecl);
    if (!is_valid_wasi_host_member(member)) return mark_error_at(tokens, member_idx, error.InvalidImportDecl);
    return .generic;
}

fn is_valid_wasi_host_locator(locator: []const u8) bool {
    return std.mem.startsWith(u8, locator, "wasi:") and is_valid_wit_host_locator(locator);
}

fn is_valid_wit_host_locator(locator: []const u8) bool {
    const namespace_end = std.mem.indexOfScalar(u8, locator, ':') orelse return false;
    if (namespace_end == 0 or namespace_end + 1 >= locator.len) return false;
    if (!is_valid_wit_path_seg(locator[0..namespace_end])) return false;
    const rest = locator[namespace_end + 1 ..];
    const at_idx = std.mem.lastIndexOfScalar(u8, rest, '@') orelse return false;
    if (at_idx == 0 or at_idx + 1 >= rest.len) return false;
    const pkg_iface = rest[0..at_idx];
    const version = rest[at_idx + 1 ..];
    var slash_count: usize = 0;
    for (pkg_iface) |ch| {
        if (ch == '/') slash_count += 1;
    }
    if (slash_count != 1) return false;
    const slash = std.mem.indexOfScalar(u8, pkg_iface, '/') orelse return false;
    if (!is_valid_wit_path_seg(pkg_iface[0..slash])) return false;
    if (!is_valid_wit_path_seg(pkg_iface[slash + 1 ..])) return false;
    return is_valid_wasi_version(version);
}

fn is_valid_wasi_host_member(member: []const u8) bool {
    if (member.len == 0) return false;
    // member may contain '.' (descriptor.write) and '-' (get-random-bytes, link-at)
    var i: usize = 0;
    while (i < member.len) {
        const ch = member[i];
        const ok = (ch >= 'a' and ch <= 'z') or
            (ch >= '0' and ch <= '9') or
            ch == '-' or ch == '.';
        if (!ok) return false;
        i += 1;
    }
    if (member[0] == '.' or member[0] == '-' or member[member.len - 1] == '.' or member[member.len - 1] == '-') return false;
    return true;
}

fn is_valid_wasi_version(version: []const u8) bool {
    const prerelease_at = std.mem.indexOfScalar(u8, version, '-') orelse version.len;
    if (!is_valid_semver_core(version[0..prerelease_at])) return false;
    if (prerelease_at == version.len) return true;
    return is_valid_semver_prerelease(version[prerelease_at + 1 ..]);
}

fn is_valid_semver_core(core: []const u8) bool {
    var component_start: usize = 0;
    var component_count: usize = 0;
    var i: usize = 0;
    while (i <= core.len) : (i += 1) {
        if (i != core.len and core[i] != '.') continue;
        if (!is_valid_semver_number(core[component_start..i])) return false;
        component_count += 1;
        component_start = i + 1;
    }
    return component_count == 3;
}

fn is_valid_semver_prerelease(prerelease: []const u8) bool {
    var identifier_start: usize = 0;
    var i: usize = 0;
    while (i <= prerelease.len) : (i += 1) {
        if (i != prerelease.len and prerelease[i] != '.') continue;
        const identifier = prerelease[identifier_start..i];
        if (identifier.len == 0) return false;
        var all_digits = true;
        for (identifier) |ch| {
            const valid = (ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z') or
                (ch >= '0' and ch <= '9') or
                ch == '-';
            if (!valid) return false;
            if (ch < '0' or ch > '9') all_digits = false;
        }
        if (all_digits and !is_valid_semver_number(identifier)) return false;
        identifier_start = i + 1;
    }
    return true;
}

fn is_valid_semver_number(number: []const u8) bool {
    if (number.len == 0) return false;
    if (number.len > 1 and number[0] == '0') return false;
    for (number) |ch| if (ch < '0' or ch > '9') return false;
    return true;
}

fn is_valid_wit_path_seg(seg: []const u8) bool {
    if (seg.len == 0) return false;
    // package/interface segments: lowercase, digits, '-'
    for (seg) |ch| {
        const ok = (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '-';
        if (!ok) return false;
    }
    return true;
}

/// Build package/interface/member for known-table lookup. Returns stack buffer via static... no, use threadlocal or just reconstruct inline.
/// Caller uses the returned slice only for lookup (points into a temporary array on stack - must not escape).
fn build_wasi_target_key(tokens: []const lexer.Token, site_idx: usize, locator: []const u8, member: []const u8) ![]const u8 {
    // Use a fixed buffer - targets are short. Store in threadlocal static for this call's validate_known_wasi_signature only.
    // Safer: allocate is not available without allocator. Reconstruct path without alloc by checking known table with custom compare.
    // Simpler approach: stack buffer in validate_host_import_line via array and pass slice.
    return build_wasi_target_key_buf(locator, member) orelse return mark_error_at(tokens, site_idx, error.InvalidImportDecl);
}

var wasi_target_key_buf: [256]u8 = undefined;

fn build_wasi_target_key_buf(locator: []const u8, member: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, locator, "wasi:")) return null;
    const rest = locator["wasi:".len..];
    const at_idx = std.mem.lastIndexOfScalar(u8, rest, '@') orelse return null;
    const pkg_iface = rest[0..at_idx];
    if (pkg_iface.len + 1 + member.len > wasi_target_key_buf.len) return null;
    @memcpy(wasi_target_key_buf[0..pkg_iface.len], pkg_iface);
    wasi_target_key_buf[pkg_iface.len] = '/';
    @memcpy(wasi_target_key_buf[pkg_iface.len + 1 ..][0..member.len], member);
    return wasi_target_key_buf[0 .. pkg_iface.len + 1 + member.len];
}

fn validate_host_signature(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !void {
    if (start_idx >= end_idx) return mark_error_at(tokens, @min(start_idx, tokens.len - 1), error.InvalidImportDecl);
    if (!tok_eq(tokens[start_idx], "(")) return mark_error_at(tokens, start_idx, error.InvalidImportDecl);
    const close_idx = find_matching(tokens, start_idx, "(", ")") catch return mark_error_at(tokens, start_idx, error.InvalidImportDecl);
    if (close_idx + 3 >= end_idx or !tok_eq(tokens[close_idx + 1], "-") or !tok_eq(tokens[close_idx + 2], ">")) return mark_error_at(tokens, close_idx, error.InvalidImportDecl);
    try validate_host_import_params(tokens, start_idx + 1, close_idx, kind);
    try validate_host_return_type(tokens, close_idx + 3, end_idx, kind);
}

const KnownWasiSignature = struct {
    target: []const u8,
    params: []const u8,
    result: []const u8,
    /// Optional do-side signature accepted as sugar for the same target (stored as WIT form for codegen).
    do_params: ?[]const u8 = null,
    /// Additional accepted do-side params forms (resource names vs i32 sugar).
    do_params_alt: ?[]const u8 = null,
    do_params_alt2: ?[]const u8 = null,
    do_result: ?[]const u8 = null,
    /// Additional accepted do-side result forms (e.g. `Dir|i32` / `File|i32` vs transitional `result<…>`).
    do_result_alt: ?[]const u8 = null,
    do_result_alt2: ?[]const u8 = null,
    do_result_alt3: ?[]const u8 = null,
    do_result_alt4: ?[]const u8 = null,
    do_result_alt5: ?[]const u8 = null,
    do_result_alt6: ?[]const u8 = null,
    result_record: ?KnownWasiRecord = null,
};

const KnownWasiRecord = struct {
    name: []const u8,
    fields: []const KnownWasiRecordField,
};

const WIT_DATETIME_FIELDS = [_]KnownWasiRecordField{
    .{ .name = "seconds", .ty = "i64" },
    .{ .name = "nanoseconds", .ty = "u32" },
};

fn validate_known_wasi_signature(
    tokens: []const lexer.Token,
    site_idx: usize,
    target: []const u8,
    sig_start: usize,
    sig_end: usize,
) !void {
    const known = find_known_wasi_signature(target) orelse return;
    const close_idx = find_matching(tokens, sig_start, "(", ")") catch
        return mark_error_at(tokens, sig_start, error.InvalidImportDecl);
    if (close_idx + 3 >= sig_end or !tok_eq(tokens[close_idx + 1], "-") or !tok_eq(tokens[close_idx + 2], ">")) {
        return mark_error_at(tokens, sig_start, error.InvalidImportDecl);
    }
    const params_ok = compact_token_range_equals(tokens, sig_start + 1, close_idx, known.params) or
        (known.do_params != null and compact_token_range_equals(tokens, sig_start + 1, close_idx, known.do_params.?)) or
        (known.do_params_alt != null and compact_token_range_equals(tokens, sig_start + 1, close_idx, known.do_params_alt.?)) or
        (known.do_params_alt2 != null and compact_token_range_equals(tokens, sig_start + 1, close_idx, known.do_params_alt2.?));
    const result_ok = compact_token_range_equals(tokens, close_idx + 3, sig_end, known.result) or
        (known.do_result != null and compact_token_range_equals(tokens, close_idx + 3, sig_end, known.do_result.?)) or
        (known.do_result_alt != null and compact_token_range_equals(tokens, close_idx + 3, sig_end, known.do_result_alt.?)) or
        (known.do_result_alt2 != null and compact_token_range_equals(tokens, close_idx + 3, sig_end, known.do_result_alt2.?)) or
        (known.do_result_alt3 != null and compact_token_range_equals(tokens, close_idx + 3, sig_end, known.do_result_alt3.?)) or
        (known.do_result_alt4 != null and compact_token_range_equals(tokens, close_idx + 3, sig_end, known.do_result_alt4.?)) or
        (known.do_result_alt5 != null and compact_token_range_equals(tokens, close_idx + 3, sig_end, known.do_result_alt5.?)) or
        (known.do_result_alt6 != null and compact_token_range_equals(tokens, close_idx + 3, sig_end, known.do_result_alt6.?));
    if (!params_ok or !result_ok) {
        return mark_error_at(tokens, site_idx, error.InvalidImportDecl);
    }
    if (known.result_record) |record| {
        if (!known_wasi_record_mirror_matches(tokens, record)) return mark_error_at(tokens, site_idx, error.InvalidImportDecl);
    }
}

fn find_known_wasi_signature(target: []const u8) ?KnownWasiSignature {
    const known = [_]KnownWasiSignature{
        .{
            .target = "filesystem/types/descriptor.write",
            .params = "descriptor,list<u8>,filesize",
            .result = "result<filesize,error-code>",
            .do_params = "i32,[u8],u64",
            .do_params_alt = "File,[u8],u64",
            // Transitional multi-lhs form still accepted.
            .do_result = "result<u64,error-code>",
            // Exclusive union: ok = filesize u64, err = status i32 (error-code+1).
            .do_result_alt = "u64|i32",
            // P4: err arm as coarse FileError (status → FileWriteFailed / FileClosed).
            .do_result_alt2 = "u64|FileError",
            .do_result_alt3 = "Result<u64,FileError>",
        },
        .{
            .target = "filesystem/types/descriptor.read",
            .params = "descriptor,filesize,filesize",
            .result = "result<tuple<list<u8>,bool>,error-code>",
            .do_params = "i32,u64,u64",
            .do_params_alt = "File,u64,u64",
            // Transitional multi-lhs form still accepted.
            .do_result = "result<tuple<[u8],bool>,error-code>",
            // Exclusive union: ok = Tuple<[u8],bool> (data+done), err = status i32 (error-code+1).
            .do_result_alt = "Tuple<[u8],bool>|i32",
            .do_result_alt2 = "Result<Tuple<[u8],bool>,FileError>",
            .do_result_alt3 = "Tuple<[u8],bool>|FileError",
        },
        .{
            .target = "filesystem/types/descriptor.sync",
            .params = "descriptor",
            .result = "result<_,error-code>",
            .do_params = "i32",
            .do_params_alt = "File",
            .do_params_alt2 = "Dir",
            // Do exclusive union sugar: nil = ok, i32 = status (error-code+1; 0 never on err arm).
            .do_result = "nil|i32",
            // P4: match public FileError|nil order for thin wrappers; also accept nil|FileError.
            .do_result_alt = "FileError|nil",
            .do_result_alt2 = "nil|FileError",
            .do_result_alt3 = "Result<nil,FileError>",
            .do_result_alt4 = "SyncError|nil",
            .do_result_alt5 = "nil|SyncError",
            .do_result_alt6 = "Result<nil,SyncError>",
        },
        .{
            .target = "filesystem/types/descriptor.link-at",
            .params = "descriptor,path-flags,text,borrow<descriptor>,text",
            .result = "result<_,error-code>",
            .do_params = "i32,i32,text,i32,text",
            .do_params_alt = "File,i32,text,File,text",
            .do_result = "nil|i32",
            .do_result_alt = "FileError|nil",
            .do_result_alt2 = "nil|FileError",
            .do_result_alt3 = "Result<nil,FileError>",
        },
        .{
            .target = "filesystem/types/descriptor.create-directory-at",
            .params = "descriptor,text",
            .result = "result<_,error-code>",
            .do_params = "i32,text",
            .do_params_alt = "Dir,text",
            .do_result = "nil|i32",
            .do_result_alt = "DirError|nil",
            .do_result_alt2 = "nil|DirError",
            .do_result_alt3 = "Result<nil,DirError>",
        },
        .{
            .target = "filesystem/types/descriptor.open-at",
            .params = "descriptor,path-flags,text,open-flags,descriptor-flags",
            .result = "result<descriptor,error-code>",
            .do_params = "i32,i32,text,i32,i32",
            // Resource handle sugar: parent Dir/File lowers via .id.
            .do_params_alt = "Dir,i32,text,i32,i32",
            .do_params_alt2 = "File,i32,text,i32,i32",
            .do_result = "result<i32,error-code>",
            // Exclusive union: ok = Dir/File (.id from descriptor), err = status i32 (error-code+1).
            .do_result_alt = "Dir|i32",
            .do_result_alt2 = "File|i32",
            // P4: err arm as coarse DirError / FileError (status → *OpenFailed).
            .do_result_alt3 = "Dir|DirError",
            .do_result_alt4 = "File|FileError",
            .do_result_alt5 = "Result<Dir,DirError>",
            .do_result_alt6 = "Result<File,FileError>",
        },
        .{
            .target = "filesystem/types/descriptor.remove-directory-at",
            .params = "descriptor,text",
            .result = "result<_,error-code>",
            .do_params = "i32,text",
            .do_params_alt = "Dir,text",
            .do_result = "nil|i32",
            .do_result_alt = "DirError|nil",
            .do_result_alt2 = "nil|DirError",
            .do_result_alt3 = "Result<nil,DirError>",
        },
        .{
            .target = "filesystem/types/descriptor.read-directory",
            .params = "descriptor",
            .result = "tuple<stream<directory-entry>,future<result<_,error-code>>>",
            .do_params = "Dir",
            .do_result = "Tuple<Stream<DirectoryEntry>,Future<Result<nil,DirectoryError>>>",
        },
        .{
            .target = "filesystem/types/descriptor.drop",
            .params = "descriptor",
            .result = "nil",
            .do_params = "i32",
            .do_params_alt = "Dir",
            .do_params_alt2 = "File",
        },
        .{
            .target = "filesystem/preopens/get-directories",
            .params = "",
            .result = "list<tuple<descriptor,text>>",
            // Preferred do form packs Dir shells; bracket sugar not yet valid on @host wasi result.
            // compact_token_range_equals ignores whitespace, so spaces in source are fine.
            .do_result = "list<tuple<Dir,text>>",
            .do_result_alt = "list<tuple<i32,text>>",
            .do_result_alt2 = "[Tuple<Dir,text>]",
        },
        .{
            .target = "io/streams/input-stream.read",
            .params = "input-stream,u64",
            .result = "result<list<u8>,stream-error>",
            .do_params = "i32,u64",
            .do_params_alt = "InputStream,u64",
            // Transitional multi-lhs form still accepted.
            .do_result = "result<[u8],stream-error>",
            // Exclusive union: ok = list storage [u8], err = status i32 or coarse StreamError.
            .do_result_alt = "[u8]|i32",
            .do_result_alt2 = "[u8]|StreamError",
            .do_result_alt3 = "Result<[u8],StreamError>",
        },
        .{
            .target = "io/streams/output-stream.check-write",
            .params = "output-stream",
            .result = "result<u64,stream-error>",
            .do_params = "i32",
            .do_params_alt = "OutputStream",
            // Same exclusive-union shape as filesize write (ok u64, err status i32 or StreamError).
            .do_result = "u64|i32",
            .do_result_alt = "u64|StreamError",
            .do_result_alt2 = "Result<u64,StreamError>",
        },
        .{
            .target = "io/streams/output-stream.write",
            .params = "output-stream,list<u8>",
            .result = "result<_,stream-error>",
            .do_params = "i32,[u8]",
            .do_params_alt = "OutputStream,[u8]",
            .do_result = "nil|i32",
            .do_result_alt = "StreamError|nil",
            .do_result_alt2 = "nil|StreamError",
            .do_result_alt3 = "Result<nil,StreamError>",
        },
        .{
            .target = "io/streams/output-stream.flush",
            .params = "output-stream",
            .result = "result<_,stream-error>",
            .do_params = "i32",
            .do_params_alt = "OutputStream",
            .do_result = "nil|i32",
            .do_result_alt = "StreamError|nil",
            .do_result_alt2 = "nil|StreamError",
            .do_result_alt3 = "Result<nil,StreamError>",
        },
        .{
            .target = "sockets/types/tcp-socket.create",
            .params = "ip-address-family",
            .result = "result<tcp-socket,error-code>",
            .do_params = "u8",
            .do_params_alt = "i32",
            .do_result = "TcpSocket|i32",
            .do_result_alt = "TcpSocket|TcpError",
            .do_result_alt2 = "Result<TcpSocket,TcpError>",
        },
        .{
            .target = "sockets/types/tcp-socket.bind",
            .params = "tcp-socket,ip-socket-address",
            .result = "result<_,error-code>",
            .do_params = "TcpSocket,IpSocketAddress",
            .do_result = "nil|i32",
            .do_result_alt = "TcpError|nil",
            .do_result_alt2 = "nil|TcpError",
            .do_result_alt3 = "Result<nil,TcpError>",
        },
        .{
            .target = "sockets/types/tcp-socket.drop",
            .params = "tcp-socket",
            .result = "nil",
            .do_params = "TcpSocket",
            .do_params_alt = "i32",
        },
        .{
            .target = "sockets/types/udp-socket.create",
            .params = "ip-address-family",
            .result = "result<udp-socket,error-code>",
            .do_params = "u8",
            .do_params_alt = "i32",
            .do_result = "UdpSocket|i32",
            .do_result_alt = "UdpSocket|UdpError",
            .do_result_alt2 = "Result<UdpSocket,UdpError>",
        },
        .{
            .target = "sockets/types/udp-socket.bind",
            .params = "udp-socket,ip-socket-address",
            .result = "result<_,error-code>",
            .do_params = "UdpSocket,IpSocketAddress",
            .do_result = "nil|i32",
            .do_result_alt = "UdpError|nil",
            .do_result_alt2 = "nil|UdpError",
            .do_result_alt3 = "Result<nil,UdpError>",
        },
        .{
            .target = "sockets/types/udp-socket.drop",
            .params = "udp-socket",
            .result = "nil",
            .do_params = "UdpSocket",
            .do_params_alt = "i32",
        },
        .{
            .target = "http/client/send",
            .params = "request",
            .result = "result<response,error-code>",
            .do_params = "HttpRequest",
            .do_result = "Result<HttpResponse,HttpError>",
        },
        .{ .target = "text/char/echo", .params = "char", .result = "char" },
        .{
            .target = "clocks/system-clock/now",
            .params = "",
            .result = "Datetime",
            .result_record = .{ .name = "Datetime", .fields = &WIT_DATETIME_FIELDS },
        },
        .{ .target = "clocks/system-clock/get-resolution", .params = "", .result = "u64" },
        .{ .target = "clocks/monotonic-clock/now", .params = "", .result = "u64" },
        .{ .target = "clocks/monotonic-clock/get-resolution", .params = "", .result = "u64" },
        .{
            .target = "random/random/get-random-bytes",
            .params = "u64",
            .result = "list<u8>",
            .do_result = "[u8]",
        },
        .{ .target = "random/random/get-random-u64", .params = "", .result = "u64" },
    };
    for (known) |item| {
        if (std.mem.eql(u8, item.target, target)) return item;
    }
    return null;
}

const StructDeclRange = struct {
    open_idx: usize,
    close_idx: usize,
    wasi_target: ?[]const u8 = null,
};

fn known_wasi_record_mirror_matches(tokens: []const lexer.Token, record: KnownWasiRecord) bool {
    const decl = find_public_struct_decl(tokens, record.name) orelse return false;

    var field_idx: usize = 0;
    var i = decl.open_idx + 1;
    while (i < decl.close_idx) {
        const line_end = find_line_end_idx(tokens, i);
        if (tokens[i].kind != .ident or !is_struct_field_name(tokens[i].lexeme) or i + 1 >= line_end) {
            i = line_end;
            continue;
        }
        if (field_idx >= record.fields.len) return false;

        const expected = record.fields[field_idx];
        if (!std.mem.eql(u8, normalize_struct_field_name(tokens[i].lexeme), expected.name)) return false;

        const type_end = find_struct_field_type_end(tokens, i + 1, line_end);
        if (!compact_token_range_equals(tokens, i + 1, type_end, expected.ty)) return false;

        field_idx += 1;
        i = line_end;
    }

    return field_idx == record.fields.len;
}

fn pinned_directory_entry_record_mirror_matches(tokens: []const lexer.Token) bool {
    const decl = find_public_struct_decl(tokens, "DirectoryEntry") orelse return false;
    if (decl.wasi_target == null or
        !std.mem.eql(u8, decl.wasi_target.?, p3_filesystem_wit_manifest.directory_entry_target)) return false;

    var field_idx: usize = 0;
    var i = decl.open_idx + 1;
    while (i < decl.close_idx) {
        if (tok_eq(tokens[i], ",")) {
            i += 1;
            continue;
        }
        if (tokens[i].kind != .ident or !is_struct_field_name(tokens[i].lexeme) or i + 1 >= decl.close_idx) return false;
        const expected = p3_filesystem_wit_manifest.record_field(field_idx) orelse return false;
        if (!std.mem.eql(u8, normalize_struct_field_name(tokens[i].lexeme), expected.do_name)) return false;
        const type_end = find_top_level_comma(tokens, i + 1, decl.close_idx) orelse decl.close_idx;
        if (!compact_token_range_equals(tokens, i + 1, type_end, expected.do_type)) return false;
        field_idx += 1;
        i = if (type_end < decl.close_idx) type_end + 1 else decl.close_idx;
    }
    return field_idx == p3_filesystem_wit_manifest.record_field_count();
}

fn validate_host_import_params(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !void {
    var i = start_idx;
    while (i < end_idx) {
        if (tok_eq(tokens[i], ",")) {
            i += 1;
            continue;
        }

        const next = try validate_host_param_type(tokens, i, end_idx, kind);
        i = next;
        if (i < end_idx) {
            if (!tok_eq(tokens[i], ",")) return mark_error_at(tokens, i, error.InvalidImportDecl);
            i += 1;
        }
    }
}

fn validate_host_return_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !void {
    const next = try validate_host_return_type_at(tokens, start_idx, end_idx, kind);
    if (next != end_idx) return mark_error_at(tokens, next, error.InvalidImportDecl);
}

fn validate_host_param_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !usize {
    if (start_idx >= end_idx) return mark_error_at(tokens, @min(start_idx, tokens.len - 1), error.InvalidImportDecl);
    switch (kind) {
        .env => {
            if (tokens[start_idx].kind == .ident and is_host_param_type(tokens[start_idx].lexeme)) {
                return start_idx + 1;
            }
            return mark_error_at(tokens, start_idx, error.InvalidImportDecl);
        },
        .generic, .wasi, .resource_probe => {
            const next = parse_wit_type(tokens, start_idx, end_idx) orelse
                return mark_error_at(tokens, start_idx, error.InvalidImportDecl);
            return next;
        },
    }
}

fn validate_host_return_type_at(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !usize {
    if (start_idx >= end_idx) return mark_error_at(tokens, @min(start_idx, tokens.len - 1), error.InvalidImportDecl);
    switch (kind) {
        .env => {
            if (tokens[start_idx].kind == .ident and is_host_return_type(tokens[start_idx].lexeme)) {
                return start_idx + 1;
            }
            return mark_error_at(tokens, start_idx, error.InvalidImportDecl);
        },
        .generic, .wasi, .resource_probe => {
            // Accept WIT types and do exclusive unions (`nil | i32`, `Dir | i32`, …).
            const next = parse_wit_or_do_union_type(tokens, start_idx, end_idx) orelse
                return mark_error_at(tokens, start_idx, error.InvalidImportDecl);
            return next;
        },
    }
}

/// WIT type, or do exclusive union of WIT/do arms separated by `|` (spaces ignored by token stream).
/// WIT type, or do exclusive union of WIT/do arms separated by `|` (spaces ignored by token stream).
fn parse_wit_or_do_union_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var next = parse_wit_type(tokens, start_idx, end_idx) orelse return null;
    while (next < end_idx and tok_eq(tokens[next], "|")) {
        const arm_end = parse_wit_type(tokens, next + 1, end_idx) orelse return null;
        next = arm_end;
    }
    return next;
}

fn is_valid_wit_target_path(path: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= path.len) {
        const slash_idx = std.mem.indexOfScalarPos(u8, path, start, '/') orelse path.len;
        const seg = path[start..slash_idx];
        if (!is_valid_wit_path_name(seg)) return false;
        count += 1;
        if (slash_idx == path.len) break;
        start = slash_idx + 1;
    }
    return count >= 3;
}

fn is_host_param_type(name: []const u8) bool {
    const allowed = [_][]const u8{
        "i32",
        "i64",
        "f32",
        "f64",
    };
    for (allowed) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn is_host_return_type(name: []const u8) bool {
    if (std.mem.eql(u8, name, "nil")) return true;
    return is_host_param_type(name);
}

fn parse_wit_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;
    // Do storage sugar: `[T]` where T is any parseable host type (u8, Tuple<…>, …).
    if (tok_eq(tokens[start_idx], "[")) {
        const elem_end = parse_wit_type(tokens, start_idx + 1, end_idx) orelse return null;
        if (elem_end >= end_idx or !tok_eq(tokens[elem_end], "]")) return null;
        return elem_end + 1;
    }
    if (tokens[start_idx].kind != .ident) return null;
    const name = tokens[start_idx].lexeme;

    if (std.mem.eql(u8, name, "list")) {
        if (start_idx + 2 >= end_idx or !tok_eq(tokens[start_idx + 1], "<")) return null;
        const item_end = parse_wit_type(tokens, start_idx + 2, end_idx) orelse return null;
        if (item_end >= end_idx or !tok_eq(tokens[item_end], ">")) return null;
        return item_end + 1;
    }

    if (std.mem.eql(u8, name, "result") or std.mem.eql(u8, name, "Result")) {
        if (start_idx + 4 >= end_idx or !tok_eq(tokens[start_idx + 1], "<")) return null;
        const ok_end = parse_wit_type(tokens, start_idx + 2, end_idx) orelse return null;
        if (ok_end >= end_idx or !tok_eq(tokens[ok_end], ",")) return null;
        const err_end = parse_wit_type(tokens, ok_end + 1, end_idx) orelse return null;
        if (err_end >= end_idx or !tok_eq(tokens[err_end], ">")) return null;
        return err_end + 1;
    }

    // WIT `tuple<…>` and do `Tuple<…>` sugar (same shape; do capital-T form for host Ok|Err).
    if (std.mem.eql(u8, name, "tuple") or std.mem.eql(u8, name, "Tuple")) {
        if (start_idx + 4 >= end_idx or !tok_eq(tokens[start_idx + 1], "<")) return null;
        var i = start_idx + 2;
        var count: usize = 0;
        while (i < end_idx) {
            const next = parse_wit_type(tokens, i, end_idx) orelse return null;
            count += 1;
            i = next;
            if (i >= end_idx) return null;
            if (tok_eq(tokens[i], ">")) return if (count >= 2) i + 1 else null;
            if (!tok_eq(tokens[i], ",")) return null;
            i += 1;
        }
        return null;
    }

    if (std.mem.eql(u8, name, "option") or
        std.mem.eql(u8, name, "borrow") or
        std.mem.eql(u8, name, "own") or
        std.mem.eql(u8, name, "future") or
        std.mem.eql(u8, name, "Future") or
        std.mem.eql(u8, name, "stream") or
        std.mem.eql(u8, name, "Stream"))
    {
        if (start_idx + 2 >= end_idx or !tok_eq(tokens[start_idx + 1], "<")) return null;
        const is_async_container = std.mem.eql(u8, name, "future") or
            std.mem.eql(u8, name, "Future") or
            std.mem.eql(u8, name, "stream") or
            std.mem.eql(u8, name, "Stream");
        const item_end = if (is_async_container)
            parse_wit_or_do_union_type(tokens, start_idx + 2, end_idx) orelse return null
        else
            parse_wit_type(tokens, start_idx + 2, end_idx) orelse return null;
        if (item_end >= end_idx or !tok_eq(tokens[item_end], ">")) return null;
        return item_end + 1;
    }

    if (std.mem.eql(u8, name, "_")) return start_idx + 1;
    if (has_public_struct_decl(tokens, name)) return start_idx + 1;
    // G6.3: payload enum names in host params (e.g. IpSocketAddress).
    if (has_public_payload_enum_decl(tokens, name)) return start_idx + 1;
    // P4: coarse do error enums in host Ok|Err results (DirError / FileError).
    // Forward refs allowed: name ends with Error (same as resource names in host params).
    if (is_error_type_name(name)) return start_idx + 1;

    return parse_wit_name(tokens, start_idx, end_idx);
}

fn has_public_struct_decl(tokens: []const lexer.Token, name: []const u8) bool {
    return find_public_struct_decl(tokens, name) != null;
}

fn has_public_payload_enum_decl(tokens: []const lexer.Token, name: []const u8) bool {
    if (!is_valid_declared_type_name(name)) return false;
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_payload_enum_decl_start(tokens, i)) continue;
        if (std.mem.eql(u8, tokens[i].lexeme, name)) return true;
    }
    return false;
}

fn find_public_struct_decl(tokens: []const lexer.Token, name: []const u8) ?StructDeclRange {
    if (!is_valid_declared_type_name(name)) return null;

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        // Classic: Name { fields }
        if (i + 1 < tokens.len and tok_eq(tokens[i + 1], "{")) {
            const close_idx = find_matching(tokens, i + 1, "{", "}") catch return null;
            return .{ .open_idx = i + 1, .close_idx = close_idx };
        }
        // Declarative: Name = @wasi_record|wasi_resource("…", { fields })
        if (wasi_struct_fields_range(tokens, i)) |fields| {
            return .{
                .open_idx = fields.open,
                .close_idx = fields.close,
                .wasi_target = wasi_decl_target(tokens, i),
            };
        }
    }
    return null;
}

fn wasi_decl_target(tokens: []const lexer.Token, name_idx: usize) ?[]const u8 {
    if (name_idx + 5 >= tokens.len or
        !tok_eq(tokens[name_idx + 1], "=") or
        !tok_eq(tokens[name_idx + 2], "@") or
        tokens[name_idx + 3].kind != .ident or
        (!std.mem.eql(u8, tokens[name_idx + 3].lexeme, "wasi_record") and
            !std.mem.eql(u8, tokens[name_idx + 3].lexeme, "wasi_resource")) or
        !tok_eq(tokens[name_idx + 4], "(") or
        tokens[name_idx + 5].kind != .string) return null;
    return string_token_body(tokens[name_idx + 5].lexeme);
}

const BraceRange = struct { open: usize, close: usize };

fn wasi_struct_fields_range(tokens: []const lexer.Token, name_idx: usize) ?BraceRange {
    if (name_idx + 5 >= tokens.len) return null;
    if (!tok_eq(tokens[name_idx + 1], "=") or !tok_eq(tokens[name_idx + 2], "@")) return null;
    if (tokens[name_idx + 3].kind != .ident) return null;
    const kind = tokens[name_idx + 3].lexeme;
    if (!std.mem.eql(u8, kind, "wasi_record") and !std.mem.eql(u8, kind, "wasi_resource")) return null;
    if (!tok_eq(tokens[name_idx + 4], "(")) return null;
    const close_call = find_matching(tokens, name_idx + 4, "(", ")") catch return null;
    var j = name_idx + 5;
    while (j < close_call) : (j += 1) {
        if (!tok_eq(tokens[j], "{")) continue;
        const close_brace = find_matching(tokens, j, "{", "}") catch return null;
        return .{ .open = j, .close = close_brace };
    }
    return null;
}

fn parse_wit_name(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (tokens[start_idx].kind != .ident or !is_valid_wit_path_name(tokens[start_idx].lexeme)) return null;
    var i = start_idx + 1;
    while (i + 1 < end_idx and tok_eq(tokens[i], "-")) {
        if (tokens[i + 1].kind != .ident or !is_valid_wit_path_name(tokens[i + 1].lexeme)) return null;
        i += 2;
    }
    return i;
}

fn is_valid_wit_path_name(name: []const u8) bool {
    var start: usize = 0;
    while (start <= name.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, name, start, '.') orelse name.len;
        if (!is_valid_wit_name_part(name[start..dot_idx])) return false;
        if (dot_idx == name.len) return true;
        start = dot_idx + 1;
    }
    return false;
}

fn is_valid_wit_name_part(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] < 'a' or name[0] > 'z') return false;
    if (name[name.len - 1] == '-') return false;

    var prev_dash = false;
    for (name[1..]) |ch| {
        if (ch >= 'a' and ch <= 'z') {
            prev_dash = false;
            continue;
        }
        if (ch >= '0' and ch <= '9') {
            prev_dash = false;
            continue;
        }
        if (ch == '-') {
            if (prev_dash) return false;
            prev_dash = true;
            continue;
        }
        return false;
    }
    return true;
}

test "registered resource probe host declarations match their descriptor" {
    const source =
        \\create = @host("do:resource-probe/ledger@0.1.0", "create", (u32) -> Ticket)
        \\borrow_value = @host("do:resource-probe/ledger@0.1.0", "borrow-value", (Ticket) -> u32)
        \\consume = @host("do:resource-probe/ledger@0.1.0", "consume", (Ticket) -> u32)
        \\Ticket = @wasi_resource("do:resource-probe/ledger/ticket", { .id i64 })
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_host_imports(std.testing.allocator, tokens);
}

test "ordinary host imports accept custom WIT package locators" {
    const source =
        \\send = @host("do:bindgen-probe/api@0.1.0", "send", (u32) -> u32)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_host_imports(std.testing.allocator, tokens);
}

test "generated WIT host bindings accept custom resource signatures" {
    const source =
        \\send = @host("do:bindgen-probe/api@0.1.0", "send", (Request) -> Response | ApiError)
        \\completion = @host("do:bindgen-probe/api@0.1.0", "completion", () -> Future<u32>)
        \\events = @host("do:bindgen-probe/api@0.1.0", "events", () -> Stream<u8>)
        \\Request = @wasi_resource("do:bindgen-probe/api/request", { .id i64 })
        \\Response = @wasi_resource("do:bindgen-probe/api/response", { .id i64 })
        \\ApiError error = Failed
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_host_imports(std.testing.allocator, tokens);
}

test "generic host imports accept a Future whose payload is an exclusive union" {
    const source =
        \\send = @host("do:bindgen-probe/api@0.1.0", "send", (Request) -> Future<Response | ApiError>)
        \\Request = @wasi_resource("do:bindgen-probe/api/request", { .id i64 })
        \\Response = @wasi_resource("do:bindgen-probe/api/response", { .id i64 })
        \\ApiError error = Failed
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_host_imports(std.testing.allocator, tokens);
}

test "custom WIT host locators reject malformed package identities" {
    const sources = [_][]const u8{
        \\call = @host("do:bindgen-probe/api", "call", (u32) -> u32)
        \\call = @host("do:bindgen-probe/api@0.1.0/extra", "call", (u32) -> u32)
        \\call = @host("do:bindgen-probe/api@0.1", "call", (u32) -> u32)
        \\call = @host("do:bindgen-probe//api@0.1.0", "call", (u32) -> u32)
        \\call = @host("do:bindgen-probe/api@0.1.0", "call/extra", (u32) -> u32)
    };
    for (sources) |source| {
        const tokens = try lexer.tokenize(std.testing.allocator, source);
        defer std.testing.allocator.free(tokens);
        try std.testing.expectError(error.InvalidImportDecl, check_host_imports(std.testing.allocator, tokens));
    }
}

test "WASI host locators require SemVer and accept pinned prereleases" {
    try std.testing.expect(is_valid_wasi_host_locator("wasi:http/client@0.3.0-rc-2025-09-16"));
    try std.testing.expect(is_valid_wasi_host_locator("wasi:clocks/monotonic-clock@0.3.0"));
    try std.testing.expect(!is_valid_wasi_host_locator("wasi:http/client@0.3"));
    try std.testing.expect(!is_valid_wasi_host_locator("wasi:http/client@0.03.0"));
    try std.testing.expect(!is_valid_wasi_host_locator("wasi:http/client@0.3.0-"));
    try std.testing.expect(!is_valid_wasi_host_locator("wasi:http/client@0.3.0-rc..1"));
}

test "WASI host imports accept nested Stream and Future return types" {
    const source =
        \\stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_host_imports(std.testing.allocator, tokens);
}

test "pinned read-directory host imports accept the fixed record stream signature" {
    const source =
        \\.host_read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\DirectoryEntry = @wasi_record("filesystem/types/directory-entry", { .type i32, .name text })
        \\DirectoryError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_host_imports(std.testing.allocator, tokens);
}

test "pinned read-directory host_func imports use the same fixed signature" {
    const source =
        \\.host_read_directory = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\DirectoryEntry = @wasi_record("filesystem/types/directory-entry", { .type i32, .name text })
        \\DirectoryError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "pinned filesystem get-type host imports accept the descriptor result union" {
    const source =
        \\get_type = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-type", (Dir) -> DescriptorType | FileError)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\DescriptorType = Unknown | Directory | RegularFile
        \\FileError error = Io | NoEntry
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "pinned filesystem get-type host imports reject a drifted source result" {
    const source =
        \\get_type = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-type", (Dir) -> WrongType | FileError)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\WrongType = Unknown | Directory | RegularFile | Socket
        \\FileError error = Io | NoEntry
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.P3AsyncHostSignatureMismatch, check_p3_async_host_imports(std.testing.allocator, tokens));
}

test "pinned filesystem sync host imports accept the unit error union" {
    const source =
        \\sync_descriptor = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync", (Dir) -> nil | SyncError)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\SyncError error = Io | NoEntry
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "pinned filesystem sync host imports reject a borrowed payload" {
    const source =
        \\sync_descriptor = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync", (Dir) -> borrow<Dir> | SyncError)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\SyncError error = Io | NoEntry
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.P3AsyncHostSignatureMismatch, check_p3_async_host_imports(std.testing.allocator, tokens));
}

test "generic record stream host_func imports accept descriptor-shaped source types" {
    const source =
        \\probe_read = @host_func("do:record-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>>)
        \\ProbeEntry = @record { .id u32, .label text }
        \\ProbeError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "bounded list-owned resource stream host_func imports accept the exact signature" {
    const source =
        \\probe_read = @host_func("do:record-resource-list-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-list-stream-probe/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProbeError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "variant resource stream host_func imports accept the measured signature" {
    const source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
        \\Ticket = @wasi_resource("do:variant-resource-stream-canonical/source/ticket", { .id i64 })
        \\EventError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "variant resource stream host_func imports reject a drifted element" {
    const source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, EventError>>>)
        \\EventError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.P3AsyncHostSignatureMismatch, check_p3_async_host_imports(std.testing.allocator, tokens));
}

test "pinned read-directory rejects a drifted record mirror" {
    const sources = [_][]const u8{
        \\.host_read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\DirectoryEntry = @wasi_record("filesystem/types/other-entry", { .type i32, .name text })
        \\DirectoryError error = Io
        ,
        \\.host_read_directory = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\DirectoryEntry = @wasi_record("filesystem/types/directory-entry", { .type u32, .name text })
        \\DirectoryError error = Io
        ,
        \\.host_read_directory = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\DirectoryEntry = @wasi_record("filesystem/types/directory-entry", { .type i32 })
        \\DirectoryError error = Io
        ,
    };
    for (sources) |source| {
        const tokens = try lexer.tokenize(std.testing.allocator, source);
        defer std.testing.allocator.free(tokens);
        try std.testing.expectError(error.P3AsyncHostSignatureMismatch, check_p3_async_host_imports(std.testing.allocator, tokens));
    }
}

test "pinned read-directory host imports reject a non-record stream element" {
    const source =
        \\.host_read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<u8>, Future<Result<nil, DirectoryError>>>)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\DirectoryError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.InvalidImportDecl, check_host_imports(std.testing.allocator, tokens));
}

test "pinned stream writer host imports accept the affine writer signature" {
    const source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\StdoutError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "pinned HTTP client send host imports defer shape validation to the service plan" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "C-min producer host_func imports accept the exact list writer signature" {
    const source =
        \\consume = @host_func("do:g6-2-c-min-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-c-min-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "dynamic C-min producer host_func imports accept the exact list writer signature" {
    const source =
        \\consume = @host_func("do:g6-2-c-min-dynamic-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-c-min-dynamic-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}

test "dynamic C-min producer host_func imports reject an unbounded writer result" {
    const source =
        \\consume = @host_func("do:g6-2-c-min-dynamic-producer@0.1.0", "consume-via-stream", (StreamWriter<u8>) -> Result<nil, ProducerError>)
        \\ProducerError error = Io | Pipe | InvalidMode
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.P3AsyncHostSignatureMismatch, check_p3_async_host_imports(std.testing.allocator, tokens));
}

test "C-min producer host_func imports reject a drifted list element" {
    const source =
        \\consume = @host_func("do:g6-2-c-min-producer@0.1.0", "consume-via-stream", (StreamWriter<u8>) -> Result<nil, ProducerError>)
        \\ProducerError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.P3AsyncHostSignatureMismatch, check_p3_async_host_imports(std.testing.allocator, tokens));
}

test "C-min producer host_func imports reject a drifted error type" {
    const source =
        \\consume = @host_func("do:g6-2-c-min-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, OtherError>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.P3AsyncHostSignatureMismatch, check_p3_async_host_imports(std.testing.allocator, tokens));
}

test "C-min producer host_func imports reject an unregistered locator" {
    const source =
        \\consume = @host_func("do:g6-2-c-min-producer-unknown@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.UnknownP3AsyncHostDescriptor, check_p3_async_host_imports(std.testing.allocator, tokens));
}

test "batched list resource producer host_func imports accept the exact list writer signature" {
    const source =
        \\consume = @host_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\ProducerError error = Io | Pipe | InvalidMode
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try check_p3_async_host_imports(std.testing.allocator, tokens);
}
