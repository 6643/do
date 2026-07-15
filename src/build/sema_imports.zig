//! Semantic analysis — import checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_shapes = @import("sema_shapes.zig");
const sema_function_support = @import("sema_function_support.zig");

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
    wasi,
};

pub fn check_host_imports(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
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
        try validate_host_import_decl(tokens, i);
        const alias = public_func_name(tokens[i].lexeme);
        if (contains_name(seen_aliases.items, alias)) return mark_error_at(tokens, i, error.DuplicateHostImportAlias);
        try seen_aliases.append(allocator, alias);
        i = (parse_import_decl_end(tokens, i) orelse i + 1) - 1;
    }
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


fn validate_host_import_decl(tokens: []const lexer.Token, name_idx: usize) !void {
    if (tokens[name_idx].kind != .ident) return mark_error_at(tokens, name_idx, error.InvalidImportDecl);
    const alias = public_func_name(tokens[name_idx].lexeme);
    if (!is_valid_import_name(alias)) return mark_error_at(tokens, name_idx, error.InvalidImportDecl);
    if (!is_lower_ident_name(alias)) return mark_error_at(tokens, name_idx, error.InvalidImportDecl);

    const eq_idx = top_level_line_assign_idx(tokens, name_idx) orelse return mark_error_at(tokens, name_idx, error.InvalidImportDecl);
    const at_idx = eq_idx + 1;
    try validate_host_import_line(tokens, at_idx, parse_import_decl_end(tokens, name_idx) orelse return mark_error_at(tokens, at_idx, error.InvalidImportDecl));
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


fn validate_host_import_line(tokens: []const lexer.Token, at_idx: usize, import_end: usize) !void {
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
    const kind = try validate_host_import_locator_member(tokens, at_idx + 3, at_idx + 5, locator, member);
    const sig_start = at_idx + 7;
    if (sig_start >= import_end - 1) return mark_error_at(tokens, at_idx + 6, error.InvalidImportDecl);
    try validate_host_signature(tokens, sig_start, import_end - 1, kind);
    if (kind == .wasi) {
        const target = try build_wasi_target_key(tokens, at_idx + 3, locator, member);
        try validate_known_wasi_signature(tokens, at_idx + 3, target, sig_start, import_end - 1);
    }
}

/// Validate locator+member and return host kind. Does not allocate.
fn validate_host_import_locator_member(
    tokens: []const lexer.Token,
    locator_idx: usize,
    member_idx: usize,
    locator: []const u8,
    member: []const u8,
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
    return mark_error_at(tokens, locator_idx, error.InvalidImportDecl);
}

fn is_valid_wasi_host_locator(locator: []const u8) bool {
    if (!std.mem.startsWith(u8, locator, "wasi:")) return false;
    const rest = locator["wasi:".len..];
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
    // Simple semver-ish: digits and dots, non-empty (e.g. 0.3.0)
    if (version.len == 0) return false;
    var has_digit = false;
    for (version) |ch| {
        if (ch >= '0' and ch <= '9') {
            has_digit = true;
            continue;
        }
        if (ch == '.') continue;
        return false;
    }
    return has_digit;
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
        (known.do_result_alt4 != null and compact_token_range_equals(tokens, close_idx + 3, sig_end, known.do_result_alt4.?));
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
        },
        .{
            .target = "filesystem/types/descriptor.sync",
            .params = "descriptor",
            .result = "result<_,error-code>",
            .do_params = "i32",
            .do_params_alt = "File",
            // Do exclusive union sugar: nil = ok, i32 = status (error-code+1; 0 never on err arm).
            .do_result = "nil|i32",
            // P4: match public FileError|nil order for thin wrappers; also accept nil|FileError.
            .do_result_alt = "FileError|nil",
            .do_result_alt2 = "nil|FileError",
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
        },
        .{ .target = "filesystem/types/descriptor.read-directory", .params = "descriptor", .result = "tuple<stream<directory-entry>,future<result<_,error-code>>>" },
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
        },
        .{
            .target = "sockets/types/tcp-socket.create",
            .params = "ip-address-family",
            .result = "result<tcp-socket,error-code>",
            .do_params = "u8",
            .do_params_alt = "i32",
            .do_result = "TcpSocket|i32",
            .do_result_alt = "TcpSocket|TcpError",
        },
        .{
            .target = "sockets/types/tcp-socket.bind",
            .params = "tcp-socket,ip-socket-address",
            .result = "result<_,error-code>",
            .do_params = "TcpSocket,IpSocketAddress",
            .do_result = "nil|i32",
            .do_result_alt = "TcpError|nil",
            .do_result_alt2 = "nil|TcpError",
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
        },
        .{
            .target = "sockets/types/udp-socket.bind",
            .params = "udp-socket,ip-socket-address",
            .result = "result<_,error-code>",
            .do_params = "UdpSocket,IpSocketAddress",
            .do_result = "nil|i32",
            .do_result_alt = "UdpError|nil",
            .do_result_alt2 = "nil|UdpError",
        },
        .{
            .target = "sockets/types/udp-socket.drop",
            .params = "udp-socket",
            .result = "nil",
            .do_params = "UdpSocket",
            .do_params_alt = "i32",
        },
        .{ .target = "http/client/send", .params = "request", .result = "result<response,error-code>" },
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
        .wasi => {
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
        .wasi => {
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

    if (std.mem.eql(u8, name, "result")) {
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

    if (std.mem.eql(u8, name, "option") or std.mem.eql(u8, name, "borrow") or std.mem.eql(u8, name, "own")) {
        if (start_idx + 2 >= end_idx or !tok_eq(tokens[start_idx + 1], "<")) return null;
        const item_end = parse_wit_type(tokens, start_idx + 2, end_idx) orelse return null;
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
            return .{ .open_idx = fields.open, .close_idx = fields.close };
        }
    }
    return null;
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

