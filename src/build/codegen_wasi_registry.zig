//! WASI host import tables, parse/collect, pure lowering helpers.
const std = @import("std");
const component_metadata_wat = @import("component_metadata_wat.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const gen_util = @import("gen_util.zig");
const moduleTokensEqual = gen_util.moduleTokensEqual;

const tokEq = gen_util.tokEq;
const findMatchingInRange = gen_util.findMatchingInRange;
const findLineEnd = gen_util.findLineEnd;
const findLineStart = gen_util.findLineStart;
const trimParens = gen_util.trimParens;
const isLineStart = gen_util.isLineStart;
const findTopLevelToken = gen_util.findTopLevelToken;
const findArgEnd = gen_util.findArgEnd;
const stringTokenBody = gen_util.stringTokenBody;
const publicDeclName = gen_util.publicDeclName;
const compactTokenText = gen_util.compactTokenText;

pub const WasiLowering = component_metadata_wat.WasiLowering;
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
pub fn knownWasiWitSignature(target: []const u8) ?struct { params: []const u8, result: []const u8 } {
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

pub fn wasiLowering(import: WasiHostImport) ?WasiLowering {
    return component_metadata_wat.wasiLowering(import);
}

pub fn appendWasiImportSymbol(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    target: []const u8,
) !void {
    try component_metadata_wat.appendWasiImportSymbol(allocator, out, target);
}

pub fn freeWasiHostImports(allocator: std.mem.Allocator, wasi_imports: []const WasiHostImport) void {
    for (wasi_imports) |import| {
        if (import.owned_target) allocator.free(import.target);
        allocator.free(import.params);
        allocator.free(import.result);
    }
}

pub fn findWasiHostImport(wasi_imports: []const WasiHostImport, alias: []const u8) ?WasiHostImport {
    for (wasi_imports) |import| {
        if (std.mem.eql(u8, import.alias, alias)) return import;
    }
    return null;
}

pub fn findWasiHostImportBySource(wasi_imports: []const WasiHostImport, source: []const u8, alias: []const u8) ?WasiHostImport {
    for (wasi_imports) |import| {
        if (!std.mem.eql(u8, import.source, source)) continue;
        if (std.mem.eql(u8, import.alias, alias)) return import;
    }
    return null;
}

pub fn isWasiHostImportStart(tokens: []const lexer.Token, idx: usize) bool {
    // name = @host("wasi:pkg/iface@ver", "member", ...)
    const line_end = findLineEnd(tokens, idx);
    if (idx + 9 >= line_end) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    if (!tokEq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "host")) return false;
    if (!tokEq(tokens[idx + 4], "(")) return false;
    if (tokens[idx + 5].kind != .string) return false;
    const locator = stringTokenBody(tokens[idx + 5].lexeme) orelse return false;
    if (!std.mem.startsWith(u8, locator, "wasi:")) return false;
    if (!tokEq(tokens[idx + 6], ",")) return false;
    if (tokens[idx + 7].kind != .string) return false;
    if (!tokEq(tokens[idx + 8], ",")) return false;
    return true;
}

/// Build internal target key `package/interface/member` from
/// locator `wasi:package/interface@version` and member name.
pub fn wasiTargetFromHostParts(allocator: std.mem.Allocator, locator: []const u8, member: []const u8) !?[]const u8 {
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

pub fn collectWasiHostImports(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    source: []const u8,
    out: *std.ArrayList(WasiHostImport),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isLineStart(tokens, i)) continue;
        if (!isWasiHostImportStart(tokens, i)) continue;

        const line_end = findLineEnd(tokens, i);
        const import = try parseWasiHostImport(allocator, tokens, i, line_end, source);
        errdefer allocator.free(import.params);
        errdefer allocator.free(import.result);
        try out.append(allocator, import);
        i = line_end - 1;
    }
}

pub fn collectWasiHostImportsFromModules(
    allocator: std.mem.Allocator,
    modules: []const imports.ModuleRecord,
    entry_tokens: []const lexer.Token,
    out: *std.ArrayList(WasiHostImport),
) !void {
    for (modules) |module| {
        const source = if (moduleTokensEqual(module.tokens, entry_tokens))
            WASI_BINDING_ENTRY_SOURCE
        else
            module.path;
        try collectWasiHostImports(allocator, module.tokens, source, out);
    }
}

pub fn parseWasiHostImport(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    line_end: usize,
    source: []const u8,
) !WasiHostImport {
    // name = @host("wasi:pkg/iface@ver", "member", (...) -> T)
    const alias = publicDeclName(tokens[start_idx].lexeme);
    const locator = stringTokenBody(tokens[start_idx + 5].lexeme) orelse return error.InvalidImportDecl;
    if (!tokEq(tokens[start_idx + 6], ",")) return error.InvalidImportDecl;
    const member = stringTokenBody(tokens[start_idx + 7].lexeme) orelse return error.InvalidImportDecl;
    if (!tokEq(tokens[start_idx + 8], ",")) return error.InvalidImportDecl;
    const target = (try wasiTargetFromHostParts(allocator, locator, member)) orelse return error.InvalidImportDecl;
    errdefer allocator.free(target);

    const open_params = start_idx + 9;
    const close_idx = findMatchingInRange(tokens, start_idx + 4, "(", ")", line_end) catch return error.InvalidImportDecl;
    if (close_idx + 1 != line_end) return error.InvalidImportDecl;
    if (open_params >= close_idx or !tokEq(tokens[open_params], "(")) return error.InvalidImportDecl;
    const close_params = findMatchingInRange(tokens, open_params, "(", ")", close_idx) catch return error.InvalidImportDecl;
    if (close_params + 3 > close_idx or !tokEq(tokens[close_params + 1], "-") or !tokEq(tokens[close_params + 2], ">")) {
        return error.InvalidImportDecl;
    }

    // Prefer canonical WIT signature for known targets so do-side sugar still lowers.
    if (knownWasiWitSignature(target)) |wit| {
        return .{
            .source = source,
            .alias = alias,
            .target = target,
            .params = try allocator.dupe(u8, wit.params),
            .result = try allocator.dupe(u8, wit.result),
            .owned_target = true,
        };
    }

    const params = try compactTokenText(allocator, tokens, open_params + 1, close_params);
    errdefer allocator.free(params);
    const result = try compactTokenText(allocator, tokens, close_params + 3, close_idx);
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

pub fn parseWasiLinkAtArgs(tokens: []const lexer.Token, args_start: usize, args_end: usize) ?WasiLinkAtArgs {
    const descriptor_end = findArgEnd(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tokEq(tokens[descriptor_end], ",")) return null;

    const old_flags_start = descriptor_end + 1;
    const old_flags_end = findArgEnd(tokens, old_flags_start, args_end);
    if (old_flags_end == old_flags_start or old_flags_end >= args_end or !tokEq(tokens[old_flags_end], ",")) return null;

    const old_path_start = old_flags_end + 1;
    const old_path_end = findArgEnd(tokens, old_path_start, args_end);
    if (old_path_end == old_path_start or old_path_end >= args_end or !tokEq(tokens[old_path_end], ",")) return null;

    const new_descriptor_start = old_path_end + 1;
    const new_descriptor_end = findArgEnd(tokens, new_descriptor_start, args_end);
    if (new_descriptor_end == new_descriptor_start or new_descriptor_end >= args_end or !tokEq(tokens[new_descriptor_end], ",")) return null;

    const new_path_start = new_descriptor_end + 1;
    const new_path_end = findArgEnd(tokens, new_path_start, args_end);
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
pub fn wasiCoarseFailedVariantName(import: WasiHostImport, err_ty: []const u8) ?[]const u8 {
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

pub fn wasiCoarseClosedVariantName(err_ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, err_ty, "DirError")) return "DirClosed";
    if (std.mem.eql(u8, err_ty, "FileError")) return "FileClosed";
    if (std.mem.eql(u8, err_ty, "StreamError")) return "StreamClosed";
    if (std.mem.eql(u8, err_ty, "TcpError")) return "TcpClosed";
    if (std.mem.eql(u8, err_ty, "UdpError")) return "UdpClosed";
    return null;
}

/// Whether this host maps every non-zero status to a single Failed variant (open wrappers).
pub fn wasiCoarseErrorAlwaysFailed(import: WasiHostImport) bool {
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

fn exprCallHead(tokens: []const lexer.Token, range: gen_util.Range) ?ExprCallHead {
    var name_idx = range.start;
    var is_intrinsic = false;
    if (tokEq(tokens[name_idx], "@")) {
        if (name_idx + 1 >= range.end) return null;
        name_idx += 1;
        is_intrinsic = true;
    }
    if (tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= range.end) return null;
    var open_paren = name_idx + 1;
    var type_args_start: usize = 0;
    var type_args_end: usize = 0;
    if (tokEq(tokens[open_paren], "<")) {
        if (is_intrinsic) return null;
        const close_angle = findMatchingInRange(tokens, open_paren, "<", ">", range.end) catch return null;
        if (close_angle + 1 >= range.end or !tokEq(tokens[close_angle + 1], "(")) return null;
        type_args_start = open_paren + 1;
        type_args_end = close_angle;
        open_paren = close_angle + 1;
    } else if (!tokEq(tokens[open_paren], "(")) {
        return null;
    }
    const close_paren = findMatchingInRange(tokens, open_paren, "(", ")", range.end) catch return null;
    if (close_paren + 1 != range.end) return null;
    // Intrinsic name validation stays in gen.zig; here any @name(...) counts as intrinsic.
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
pub fn isWasiUnionResultBindingCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    const eq_idx = findTopLevelToken(tokens, line_start, call_idx, "=") orelse return false;
    // Must look like a typed binding (ident + type with `|`), not multi-lhs.
    if (findTopLevelToken(tokens, line_start, eq_idx, ",") != null) return false;
    if (findTopLevelToken(tokens, line_start, eq_idx, "|") == null) return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

/// Thin wrapper return of a host call: `return host(...)`.
pub fn isWasiUnionResultReturnCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    if (line_start >= line_end or !tokEq(tokens[line_start], "return")) return false;
    const rhs_range = trimParens(tokens, line_start + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn isBareWasiHostCallStatement(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    // Statement form: host(...) alone on the line (no `=`).
    if (findTopLevelToken(tokens, line_start, call_idx, "=") != null) return false;
    const range = trimParens(tokens, line_start, line_end);
    const call_head = exprCallHead(tokens, range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn isWasiResultUnitStatusMultiAssignmentCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    const eq_idx = findTopLevelToken(tokens, line_start, call_idx, "=") orelse return false;

    const first_lhs_end = findArgEnd(tokens, line_start, eq_idx);
    if (first_lhs_end != line_start + 1 or tokens[line_start].kind != .ident) return false;
    if (!std.mem.eql(u8, tokens[line_start].lexeme, "_")) return false;
    if (first_lhs_end >= eq_idx or !tokEq(tokens[first_lhs_end], ",")) return false;

    const status_lhs_start = first_lhs_end + 1;
    const status_lhs_end = findArgEnd(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx) return false;
    if (tokens[status_lhs_start].kind != .ident) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn isWasiResultReadMultiAssignmentCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    const eq_idx = findTopLevelToken(tokens, line_start, call_idx, "=") orelse return false;
    if (findTopLevelToken(tokens, line_start, eq_idx, ",") == null) return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn isWasiResultListU8StatusMultiAssignmentCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    const eq_idx = findTopLevelToken(tokens, line_start, call_idx, "=") orelse return false;

    const data_lhs_end = findArgEnd(tokens, line_start, eq_idx);
    if (data_lhs_end != line_start + 1 or tokens[line_start].kind != .ident) return false;
    if (data_lhs_end >= eq_idx or !tokEq(tokens[data_lhs_end], ",")) return false;

    const status_lhs_start = data_lhs_end + 1;
    const status_lhs_end = findArgEnd(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx) return false;
    if (tokens[status_lhs_start].kind != .ident) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

pub fn wasiHostImportUseIsLowerableAtCall(
    tokens: []const lexer.Token,
    call_idx: usize,
    import: WasiHostImport,
) bool {
    const lowering = wasiLowering(import) orelse return false;
    // link-at: multi-lhs `_, status =`, exclusive-union binding, return host(...), or statement discard.
    if (lowering.result_link_at_error) {
        return isWasiResultUnitStatusMultiAssignmentCall(tokens, call_idx) or
            isWasiUnionResultBindingCall(tokens, call_idx) or
            isWasiUnionResultReturnCall(tokens, call_idx) or
            isBareWasiHostCallStatement(tokens, call_idx);
    }
    // tuple-in-result: multi-lhs `data, done, status =` or exclusive-union `Tuple<[u8],bool> | i32 =`.
    if (lowering.result_read_error) {
        return isWasiResultReadMultiAssignmentCall(tokens, call_idx) or
            isWasiUnionResultBindingCall(tokens, call_idx) or
            isWasiUnionResultReturnCall(tokens, call_idx);
    }
    // list-in-result: multi-lhs `data, status =` or exclusive-union `[u8] | i32 =`.
    if (lowering.result_list_u8_error) {
        return isWasiResultListU8StatusMultiAssignmentCall(tokens, call_idx) or
            isWasiUnionResultBindingCall(tokens, call_idx) or
            isWasiUnionResultReturnCall(tokens, call_idx);
    }
    return true;
}

pub fn validateWasiHostImportBuildUses(tokens: []const lexer.Token, wasi_imports: []const WasiHostImport) !void {
    if (wasi_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const import = findWasiHostImport(wasi_imports, tokens[i].lexeme) orelse continue;
        if (!tokEq(tokens[i + 1], "(")) continue;
        if (wasiHostImportUseIsLowerableAtCall(tokens, i, import)) continue;
        return error.UnsupportedWasiHostImport;
    }
}

