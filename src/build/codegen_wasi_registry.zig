//! WASI host import tables, parse/collect, pure lowering helpers.
const std = @import("std");
const wat_component_metadata = @import("wat_component_metadata.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const module_tokens_equal = codegen_tokens.module_tokens_equal;

const tok_eq = codegen_tokens.tok_eq;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_line_end = codegen_tokens.find_line_end;
const find_line_start = codegen_tokens.find_line_start;
const trim_parens = codegen_tokens.trim_parens;
const is_line_start = codegen_tokens.is_line_start;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const string_token_body = codegen_tokens.string_token_body;
const public_decl_name = codegen_names.public_decl_name;
const compact_token_text = codegen_tokens.compact_token_text;

pub const WasiLowering = wat_component_metadata.WasiLowering;
pub const WASI_BINDING_ENTRY_SOURCE = "entry";

pub const WasiHostImport = struct {
    source: []const u8,
    alias: []const u8,
    target: []const u8,
    params: []const u8,
    result: []const u8,
    /// When true, `target` was allocated (from @host locator+member).
    owned_target: bool = false,
};

pub const WasiLinkAtArgs = struct {
    descriptor_start: usize,
    descriptor_end: usize,
    old_flags_start: usize,
    old_flags_end: usize,
    old_path_start: usize,
    old_path_end: usize,
    new_descriptor_start: usize,
    new_descriptor_end: usize,
    new_path_start: usize,
    new_path_end: usize,
};

/// Canonical WIT params/result for known targets (codegen always stores WIT form).
pub fn known_wasi_wit_signature(target: []const u8) ?struct { params: []const u8, result: []const u8 } {
    const known = [_]struct { target: []const u8, params: []const u8, result: []const u8 }{
        .{ .target = "filesystem/types/descriptor.write", .params = "descriptor,list<u8>,filesize", .result = "result<filesize,error-code>" },
        .{ .target = "filesystem/types/descriptor.read", .params = "descriptor,filesize,filesize", .result = "result<tuple<list<u8>,bool>,error-code>" },
        .{ .target = "filesystem/types/descriptor.sync", .params = "descriptor", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.link-at", .params = "descriptor,path-flags,text,borrow<descriptor>,text", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.create-directory-at", .params = "descriptor,text", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.open-at", .params = "descriptor,path-flags,text,open-flags,descriptor-flags", .result = "result<descriptor,error-code>" },
        .{ .target = "filesystem/types/descriptor.remove-directory-at", .params = "descriptor,text", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.drop", .params = "descriptor", .result = "nil" },
        .{ .target = "filesystem/preopens/get-directories", .params = "", .result = "list<tuple<descriptor,text>>" },
        .{ .target = "io/streams/input-stream.read", .params = "input-stream,u64", .result = "result<list<u8>,stream-error>" },
        .{ .target = "io/streams/output-stream.check-write", .params = "output-stream", .result = "result<u64,stream-error>" },
        .{ .target = "io/streams/output-stream.write", .params = "output-stream,list<u8>", .result = "result<_,stream-error>" },
        .{ .target = "io/streams/output-stream.flush", .params = "output-stream", .result = "result<_,stream-error>" },
        .{ .target = "sockets/types/tcp-socket.create", .params = "ip-address-family", .result = "result<tcp-socket,error-code>" },
        .{ .target = "sockets/types/tcp-socket.bind", .params = "tcp-socket,ip-socket-address", .result = "result<_,error-code>" },
        .{ .target = "sockets/types/tcp-socket.drop", .params = "tcp-socket", .result = "nil" },
        .{ .target = "sockets/types/udp-socket.create", .params = "ip-address-family", .result = "result<udp-socket,error-code>" },
        .{ .target = "sockets/types/udp-socket.bind", .params = "udp-socket,ip-socket-address", .result = "result<_,error-code>" },
        .{ .target = "sockets/types/udp-socket.drop", .params = "udp-socket", .result = "nil" },
        .{ .target = "clocks/system-clock/now", .params = "", .result = "Datetime" },
        .{ .target = "clocks/system-clock/get-resolution", .params = "", .result = "u64" },
        .{ .target = "clocks/monotonic-clock/now", .params = "", .result = "u64" },
        .{ .target = "clocks/monotonic-clock/get-resolution", .params = "", .result = "u64" },
        .{ .target = "random/random/get-random-bytes", .params = "u64", .result = "list<u8>" },
        .{ .target = "random/random/get-random-u64", .params = "", .result = "u64" },
    };
    for (known) |item| {
        if (std.mem.eql(u8, item.target, target)) return .{ .params = item.params, .result = item.result };
    }
    return null;
}

pub fn wasi_lowering(import: WasiHostImport) ?WasiLowering {
    return wat_component_metadata.wasiLowering(import);
}

pub fn append_wasi_import_symbol(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    target: []const u8,
) !void {
    try wat_component_metadata.appendWasiImportSymbol(allocator, out, target);
}

pub fn free_wasi_host_imports(allocator: std.mem.Allocator, wasi_imports: []const WasiHostImport) void {
    for (wasi_imports) |import| {
        if (import.owned_target) allocator.free(import.target);
        allocator.free(import.params);
        allocator.free(import.result);
    }
}

pub fn find_wasi_host_import(wasi_imports: []const WasiHostImport, alias: []const u8) ?WasiHostImport {
    for (wasi_imports) |import| {
        if (std.mem.eql(u8, import.alias, alias)) return import;
    }
    return null;
}

pub fn find_wasi_host_import_by_source(wasi_imports: []const WasiHostImport, source: []const u8, alias: []const u8) ?WasiHostImport {
    for (wasi_imports) |import| {
        if (!std.mem.eql(u8, import.source, source)) continue;
        if (std.mem.eql(u8, import.alias, alias)) return import;
    }
    return null;
}

pub fn is_wasi_host_import_start(tokens: []const lexer.Token, idx: usize) bool {
    // name = @host("wasi:pkg/iface@ver", "member", ...)
    const line_end = find_line_end(tokens, idx);
    if (idx + 9 >= line_end) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tok_eq(tokens[idx + 1], "=")) return false;
    if (!tok_eq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "host")) return false;
    if (!tok_eq(tokens[idx + 4], "(")) return false;
    if (tokens[idx + 5].kind != .string) return false;
    const locator = string_token_body(tokens[idx + 5].lexeme) orelse return false;
    if (!std.mem.startsWith(u8, locator, "wasi:")) return false;
    if (!tok_eq(tokens[idx + 6], ",")) return false;
    if (tokens[idx + 7].kind != .string) return false;
    if (!tok_eq(tokens[idx + 8], ",")) return false;
    return true;
}

/// Build internal target key `package/interface/member` from
/// locator `wasi:package/interface@version` and member name.
pub fn wasi_target_from_host_parts(allocator: std.mem.Allocator, locator: []const u8, member: []const u8) !?[]const u8 {
    if (!std.mem.startsWith(u8, locator, "wasi:")) return null;
    const rest = locator["wasi:".len..];
    const at_idx = std.mem.lastIndexOfScalar(u8, rest, '@') orelse return null;
    if (at_idx == 0 or at_idx + 1 >= rest.len) return null;
    const pkg_iface = rest[0..at_idx];
    // version is rest[at_idx+1..] — required non-empty; content validated by sema
    var slash_count: usize = 0;
    for (pkg_iface) |ch| {
        if (ch == '/') slash_count += 1;
    }
    if (slash_count != 1) return null;
    if (member.len == 0) return null;
    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ pkg_iface, member });
}

pub fn collect_wasi_host_imports(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    source: []const u8,
    out: *std.ArrayList(WasiHostImport),
) !void {
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
        if (!is_line_start(tokens, i)) continue;
        if (!is_wasi_host_import_start(tokens, i)) continue;

        const line_end = find_line_end(tokens, i);
        const import = try parse_wasi_host_import(allocator, tokens, i, line_end, source);
        errdefer allocator.free(import.params);
        errdefer allocator.free(import.result);
        try out.append(allocator, import);
        i = line_end - 1;
    }
}

pub fn collect_wasi_host_imports_from_modules(
    allocator: std.mem.Allocator,
    modules: []const imports.ModuleRecord,
    entry_tokens: []const lexer.Token,
    out: *std.ArrayList(WasiHostImport),
) !void {
    for (modules) |module| {
        const source = if (module_tokens_equal(module.tokens, entry_tokens))
            WASI_BINDING_ENTRY_SOURCE
        else
            module.path;
        try collect_wasi_host_imports(allocator, module.tokens, source, out);
    }
}

pub fn parse_wasi_host_import(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    line_end: usize,
    source: []const u8,
) !WasiHostImport {
    // name = @host("wasi:pkg/iface@ver", "member", (...) -> T)
    const alias = public_decl_name(tokens[start_idx].lexeme);
    const locator = string_token_body(tokens[start_idx + 5].lexeme) orelse return error.InvalidImportDecl;
    if (!tok_eq(tokens[start_idx + 6], ",")) return error.InvalidImportDecl;
    const member = string_token_body(tokens[start_idx + 7].lexeme) orelse return error.InvalidImportDecl;
    if (!tok_eq(tokens[start_idx + 8], ",")) return error.InvalidImportDecl;
    const target = (try wasi_target_from_host_parts(allocator, locator, member)) orelse return error.InvalidImportDecl;
    errdefer allocator.free(target);

    const open_params = start_idx + 9;
    const close_idx = find_matching_in_range(tokens, start_idx + 4, "(", ")", line_end) catch return error.InvalidImportDecl;
    if (close_idx + 1 != line_end) return error.InvalidImportDecl;
    if (open_params >= close_idx or !tok_eq(tokens[open_params], "(")) return error.InvalidImportDecl;
    const close_params = find_matching_in_range(tokens, open_params, "(", ")", close_idx) catch return error.InvalidImportDecl;
    if (close_params + 3 > close_idx or !tok_eq(tokens[close_params + 1], "-") or !tok_eq(tokens[close_params + 2], ">")) {
        return error.InvalidImportDecl;
    }

    // Prefer canonical WIT signature for known targets so do-side sugar still lowers.
    if (known_wasi_wit_signature(target)) |wit| {
        return .{
            .source = source,
            .alias = alias,
            .target = target,
            .params = try allocator.dupe(u8, wit.params),
            .result = try allocator.dupe(u8, wit.result),
            .owned_target = true,
        };
    }

    const params = try compact_token_text(allocator, tokens, open_params + 1, close_params);
    errdefer allocator.free(params);
    const result = try compact_token_text(allocator, tokens, close_params + 3, close_idx);
    errdefer allocator.free(result);

    return .{
        .source = source,
        .alias = alias,
        .target = target,
        .params = params,
        .result = result,
        .owned_target = true,
    };
}

pub fn parse_wasi_link_at_args(tokens: []const lexer.Token, args_start: usize, args_end: usize) ?WasiLinkAtArgs {
    const descriptor_end = find_arg_end(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tok_eq(tokens[descriptor_end], ",")) return null;

    const old_flags_start = descriptor_end + 1;
    const old_flags_end = find_arg_end(tokens, old_flags_start, args_end);
    if (old_flags_end == old_flags_start or old_flags_end >= args_end or !tok_eq(tokens[old_flags_end], ",")) return null;

    const old_path_start = old_flags_end + 1;
    const old_path_end = find_arg_end(tokens, old_path_start, args_end);
    if (old_path_end == old_path_start or old_path_end >= args_end or !tok_eq(tokens[old_path_end], ",")) return null;

    const new_descriptor_start = old_path_end + 1;
    const new_descriptor_end = find_arg_end(tokens, new_descriptor_start, args_end);
    if (new_descriptor_end == new_descriptor_start or new_descriptor_end >= args_end or !tok_eq(tokens[new_descriptor_end], ",")) return null;

    const new_path_start = new_descriptor_end + 1;
    const new_path_end = find_arg_end(tokens, new_path_start, args_end);
    if (new_path_end == new_path_start or new_path_end != args_end) return null;

    return .{
        .descriptor_start = args_start,
        .descriptor_end = descriptor_end,
        .old_flags_start = old_flags_start,
        .old_flags_end = old_flags_end,
        .old_path_start = old_path_start,
        .old_path_end = old_path_end,
        .new_descriptor_start = new_descriptor_start,
        .new_descriptor_end = new_descriptor_end,
        .new_path_start = new_path_start,
        .new_path_end = new_path_end,
    };
}

/// Coarse Failed variant for a fallible WASI host (matches stdlib wrapper fallbacks).
pub fn wasi_coarse_failed_variant_name(import: WasiHostImport, err_ty: []const u8) ?[]const u8 {
    const target = import.target;
    if (std.mem.eql(u8, err_ty, "DirError")) {
        if (std.mem.eql(u8, target, "filesystem/types/descriptor.open-at")) return "DirOpenFailed";
        if (std.mem.eql(u8, target, "filesystem/types/descriptor.create-directory-at")) return "DirCreateFailed";
        if (std.mem.eql(u8, target, "filesystem/types/descriptor.remove-directory-at")) return "DirRemoveFailed";
        return null;
    }
    if (std.mem.eql(u8, err_ty, "FileError")) {
        if (std.mem.eql(u8, target, "filesystem/types/descriptor.open-at")) return "FileOpenFailed";
        if (std.mem.eql(u8, target, "filesystem/types/descriptor.sync")) return "FileFlushFailed";
        if (std.mem.eql(u8, target, "filesystem/types/descriptor.write")) return "FileWriteFailed";
        if (std.mem.eql(u8, target, "filesystem/types/descriptor.link-at")) return "FileLinkFailed";
        if (std.mem.eql(u8, target, "filesystem/types/descriptor.read")) return "FileReadFailed";
        return null;
    }
    if (std.mem.eql(u8, err_ty, "StreamError")) {
        if (std.mem.eql(u8, target, "io/streams/input-stream.read")) return "StreamReadFailed";
        if (std.mem.eql(u8, target, "io/streams/output-stream.check-write")) return "StreamCheckWriteFailed";
        if (std.mem.eql(u8, target, "io/streams/output-stream.write")) return "StreamWriteFailed";
        if (std.mem.eql(u8, target, "io/streams/output-stream.flush")) return "StreamFlushFailed";
        return null;
    }
    // G6.3: TcpError / UdpError — create always *HostFailure; bind uses Closed vs HostFailure.
    if (std.mem.eql(u8, err_ty, "TcpError")) {
        if (std.mem.eql(u8, target, "sockets/types/tcp-socket.create")) return "TcpHostFailure";
        if (std.mem.eql(u8, target, "sockets/types/tcp-socket.bind")) return "TcpHostFailure";
        return null;
    }
    if (std.mem.eql(u8, err_ty, "UdpError")) {
        if (std.mem.eql(u8, target, "sockets/types/udp-socket.create")) return "UdpHostFailure";
        if (std.mem.eql(u8, target, "sockets/types/udp-socket.bind")) return "UdpHostFailure";
        return null;
    }
    return null;
}

pub fn wasi_coarse_closed_variant_name(err_ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, err_ty, "DirError")) return "DirClosed";
    if (std.mem.eql(u8, err_ty, "FileError")) return "FileClosed";
    if (std.mem.eql(u8, err_ty, "StreamError")) return "StreamClosed";
    if (std.mem.eql(u8, err_ty, "TcpError")) return "TcpClosed";
    if (std.mem.eql(u8, err_ty, "UdpError")) return "UdpClosed";
    return null;
}

/// Whether this host maps every non-zero status to a single Failed variant (open wrappers).
pub fn wasi_coarse_error_always_failed(import: WasiHostImport) bool {
    return std.mem.eql(u8, import.target, "filesystem/types/descriptor.open-at") or
        std.mem.eql(u8, import.target, "sockets/types/tcp-socket.create") or
        std.mem.eql(u8, import.target, "sockets/types/udp-socket.create");
}



const ExprCallHead = struct {
    name_idx: usize,
    type_args_start: usize = 0,
    type_args_end: usize = 0,
    args_start: usize,
    args_end: usize,
    is_intrinsic: bool,
};

fn exprCallHead(tokens: []const lexer.Token, range: codegen_tokens.Range) ?ExprCallHead {
    var name_idx = range.start;
    var is_intrinsic = false;
    if (tok_eq(tokens[name_idx], "@")) {
        if (name_idx + 1 >= range.end) return null;
        name_idx += 1;
        is_intrinsic = true;
    }
    if (tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= range.end) return null;
    var open_paren = name_idx + 1;
    var type_args_start: usize = 0;
    var type_args_end: usize = 0;
    if (tok_eq(tokens[open_paren], "<")) {
        if (is_intrinsic) return null;
        const close_angle = find_matching_in_range(tokens, open_paren, "<", ">", range.end) catch return null;
        if (close_angle + 1 >= range.end or !tok_eq(tokens[close_angle + 1], "(")) return null;
        type_args_start = open_paren + 1;
        type_args_end = close_angle;
        open_paren = close_angle + 1;
    } else if (!tok_eq(tokens[open_paren], "(")) {
        return null;
    }
    const close_paren = find_matching_in_range(tokens, open_paren, "(", ")", range.end) catch return null;
    if (close_paren + 1 != range.end) return null;
    // Intrinsic name validation stays in codegen_api.zig; here any @name(...) counts as intrinsic.
    return .{
        .name_idx = name_idx,
        .type_args_start = type_args_start,
        .type_args_end = type_args_end,
        .args_start = open_paren + 1,
        .args_end = close_paren,
        .is_intrinsic = is_intrinsic,
    };
}

/// Typed exclusive-union binding of a host call: `r T | U = host(...)`.
pub fn is_wasi_union_result_binding_call(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = find_line_start(tokens, call_idx);
    const line_end = find_line_end(tokens, call_idx);
    const eq_idx = find_top_level_token(tokens, line_start, call_idx, "=") orelse return false;
    // Must look like a typed binding (ident + type with `|`), not multi-lhs.
    if (find_top_level_token(tokens, line_start, eq_idx, ",") != null) return false;
    if (find_top_level_token(tokens, line_start, eq_idx, "|") == null) return false;
    const rhs_range = trim_parens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

/// Thin wrapper return of a host call: `return host(...)`.
pub fn is_wasi_union_result_return_call(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = find_line_start(tokens, call_idx);
    const line_end = find_line_end(tokens, call_idx);
    if (line_start >= line_end or !tok_eq(tokens[line_start], "return")) return false;
    const rhs_range = trim_parens(tokens, line_start + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn is_bare_wasi_host_call_statement(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = find_line_start(tokens, call_idx);
    const line_end = find_line_end(tokens, call_idx);
    // Statement form: host(...) alone on the line (no `=`).
    if (find_top_level_token(tokens, line_start, call_idx, "=") != null) return false;
    const range = trim_parens(tokens, line_start, line_end);
    const call_head = exprCallHead(tokens, range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn is_wasi_result_unit_status_multi_assignment_call(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = find_line_start(tokens, call_idx);
    const line_end = find_line_end(tokens, call_idx);
    const eq_idx = find_top_level_token(tokens, line_start, call_idx, "=") orelse return false;

    const first_lhs_end = find_arg_end(tokens, line_start, eq_idx);
    if (first_lhs_end != line_start + 1 or tokens[line_start].kind != .ident) return false;
    if (!std.mem.eql(u8, tokens[line_start].lexeme, "_")) return false;
    if (first_lhs_end >= eq_idx or !tok_eq(tokens[first_lhs_end], ",")) return false;

    const status_lhs_start = first_lhs_end + 1;
    const status_lhs_end = find_arg_end(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx) return false;
    if (tokens[status_lhs_start].kind != .ident) return false;

    const rhs_range = trim_parens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn is_wasi_result_read_multi_assignment_call(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = find_line_start(tokens, call_idx);
    const line_end = find_line_end(tokens, call_idx);
    const eq_idx = find_top_level_token(tokens, line_start, call_idx, "=") orelse return false;
    if (find_top_level_token(tokens, line_start, eq_idx, ",") == null) return false;
    const rhs_range = trim_parens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn is_wasi_result_list_u8_status_multi_assignment_call(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = find_line_start(tokens, call_idx);
    const line_end = find_line_end(tokens, call_idx);
    const eq_idx = find_top_level_token(tokens, line_start, call_idx, "=") orelse return false;

    const data_lhs_end = find_arg_end(tokens, line_start, eq_idx);
    if (data_lhs_end != line_start + 1 or tokens[line_start].kind != .ident) return false;
    if (data_lhs_end >= eq_idx or !tok_eq(tokens[data_lhs_end], ",")) return false;

    const status_lhs_start = data_lhs_end + 1;
    const status_lhs_end = find_arg_end(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx) return false;
    if (tokens[status_lhs_start].kind != .ident) return false;

    const rhs_range = trim_parens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn wasi_host_import_use_is_lowerable_at_call(
    tokens: []const lexer.Token,
    call_idx: usize,
    import: WasiHostImport,
) bool {
    const lowering = wasi_lowering(import) orelse return false;
    // link-at: multi-lhs `_, status =`, exclusive-union binding, return host(...), or statement discard.
    if (lowering.result_link_at_error) {
        return is_wasi_result_unit_status_multi_assignment_call(tokens, call_idx) or
            is_wasi_union_result_binding_call(tokens, call_idx) or
            is_wasi_union_result_return_call(tokens, call_idx) or
            is_bare_wasi_host_call_statement(tokens, call_idx);
    }
    // tuple-in-result: multi-lhs `data, done, status =` or exclusive-union `Tuple<[u8],bool> | i32 =`.
    if (lowering.result_read_error) {
        return is_wasi_result_read_multi_assignment_call(tokens, call_idx) or
            is_wasi_union_result_binding_call(tokens, call_idx) or
            is_wasi_union_result_return_call(tokens, call_idx);
    }
    // list-in-result: multi-lhs `data, status =` or exclusive-union `[u8] | i32 =`.
    if (lowering.result_list_u8_error) {
        return is_wasi_result_list_u8_status_multi_assignment_call(tokens, call_idx) or
            is_wasi_union_result_binding_call(tokens, call_idx) or
            is_wasi_union_result_return_call(tokens, call_idx);
    }
    return true;
}

pub fn validate_wasi_host_import_build_uses(tokens: []const lexer.Token, wasi_imports: []const WasiHostImport) !void {
    if (wasi_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const import = find_wasi_host_import(wasi_imports, tokens[i].lexeme) orelse continue;
        if (!tok_eq(tokens[i + 1], "(")) continue;
        if (wasi_host_import_use_is_lowerable_at_call(tokens, i, import)) continue;
        return error.UnsupportedWasiHostImport;
    }
}
