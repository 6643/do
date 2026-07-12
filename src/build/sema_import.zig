//! Semantic analysis — import checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_util = @import("sema_util.zig");
const sema_types = @import("sema_types.zig");

const compactTokenRangeEquals = sema_util.compactTokenRangeEquals;
const containsName = sema_util.containsName;
const findLineEndIdx = sema_util.findLineEndIdx;
const findMatching = sema_util.findMatching;
const findStructFieldTypeEnd = sema_util.findStructFieldTypeEnd;
const findTopLevelComma = sema_util.findTopLevelComma;
const isErrorTypeName = sema_util.isErrorTypeName;
const isHostImportDeclStart = sema_util.isHostImportDeclStart;
const isHostImportLine = sema_util.isHostImportLine;
const isLowerIdentName = sema_util.isLowerIdentName;
const isModernImportAssign = sema_util.isModernImportAssign;
const isReadonlyIdentName = sema_util.isReadonlyIdentName;
const isReservedFuncName = sema_util.isReservedFuncName;
const isStructFieldName = sema_util.isStructFieldName;
const isTopLevelDeclHead = sema_util.isTopLevelDeclHead;
const isValidDeclaredTypeName = sema_util.isValidDeclaredTypeName;
const isValidPathSeg = sema_util.isValidPathSeg;
const markErrorAt = sema_util.markErrorAt;
const normalizeStructFieldName = sema_util.normalizeStructFieldName;
const parseImportDeclEnd = sema_util.parseImportDeclEnd;
const skipTopLevelImportBrace = sema_util.skipTopLevelImportBrace;
const publicFuncName = sema_util.publicFuncName;
const stringTokenBody = sema_util.stringTokenBody;
const tokEq = sema_util.tokEq;
const topLevelLineAssignIdx = sema_util.topLevelLineAssignIdx;
const validateImportFileNameText = sema_util.validateImportFileNameText;
const KnownWasiRecordField = sema_types.KnownWasiRecordField;
const LocalImportPrefix = sema_types.LocalImportPrefix;

const HostImportKind = enum {
    env,
    wasi,
};

pub fn checkHostImports(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var seen_aliases = std.ArrayList([]const u8).empty;
    defer seen_aliases.deinit(allocator);

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
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (!isHostImportDeclStart(tokens, i)) continue;
        try validateHostImportDecl(tokens, i);
        const alias = publicFuncName(tokens[i].lexeme);
        if (containsName(seen_aliases.items, alias)) return markErrorAt(tokens, i, error.DuplicateHostImportAlias);
        try seen_aliases.append(allocator, alias);
        i = (parseImportDeclEnd(tokens, i) orelse i + 1) - 1;
    }
}


pub fn checkLocalImports(tokens: []const lexer.Token) !void {
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
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (!isModernImportAssign(tokens, i)) continue;

        const eq_idx = topLevelLineAssignIdx(tokens, i) orelse return markErrorAt(tokens, i, error.InvalidImportDecl);
        const at_idx = eq_idx + 1;
        if (isHostImportLine(tokens, at_idx)) {
            i = (parseImportDeclEnd(tokens, i) orelse i + 1) - 1;
            continue;
        }

        try validateLocalImportDecl(tokens, i, at_idx);
        i = (parseImportDeclEnd(tokens, i) orelse i + 1) - 1;
    }
}


fn validateHostImportDecl(tokens: []const lexer.Token, name_idx: usize) !void {
    if (tokens[name_idx].kind != .ident) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    const alias = publicFuncName(tokens[name_idx].lexeme);
    if (!isValidImportName(alias)) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    if (!isLowerIdentName(alias)) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);

    const eq_idx = topLevelLineAssignIdx(tokens, name_idx) orelse return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    const at_idx = eq_idx + 1;
    try validateHostImportLine(tokens, at_idx, parseImportDeclEnd(tokens, name_idx) orelse return markErrorAt(tokens, at_idx, error.InvalidImportDecl));
}


fn isValidImportName(name: []const u8) bool {
    return (isValidDeclaredTypeName(name) or isLowerIdentName(name) or isReadonlyIdentName(name)) and !isReservedFuncName(name);
}


fn importAliasMatchesTarget(alias: []const u8, target: []const u8) bool {
    if (isValidDeclaredTypeName(target)) return isValidDeclaredTypeName(alias);
    if (isLowerIdentName(target)) return isLowerIdentName(alias);
    if (isReadonlyIdentName(target)) return isReadonlyIdentName(alias);
    return false;
}


fn validateLocalImportDecl(tokens: []const lexer.Token, name_idx: usize, at_idx: usize) !void {
    if (tokens[name_idx].kind != .ident) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    if (tokens[name_idx].lexeme.len != 0 and tokens[name_idx].lexeme[0] == '.') return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    if (!isValidImportName(tokens[name_idx].lexeme)) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);

    const close_idx = parseImportDeclEnd(tokens, name_idx) orelse return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (at_idx + 7 != close_idx) return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (tokens[at_idx + 1].kind != .ident or !std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib")) return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (!tokEq(tokens[at_idx + 2], "(")) return markErrorAt(tokens, at_idx + 2, error.InvalidImportDecl);
    if (tokens[at_idx + 3].kind != .string) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    if (!tokEq(tokens[at_idx + 4], ",")) return markErrorAt(tokens, at_idx + 4, error.InvalidImportDecl);
    if (tokens[at_idx + 5].kind != .ident) return markErrorAt(tokens, at_idx + 5, error.InvalidImportDecl);

    var file_path = stringTokenBody(tokens[at_idx + 3].lexeme) orelse return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    const target = tokens[at_idx + 5].lexeme;
    var prefix: LocalImportPrefix = .std;
    if (std.mem.startsWith(u8, file_path, "./")) {
        prefix = .local;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "~/")) {
        prefix = .dep;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "/")) {
        return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    }

    try validateImportFileNameText(tokens, at_idx + 3, file_path, prefix);
    if (!isValidImportName(target)) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    if (!importAliasMatchesTarget(tokens[name_idx].lexeme, target)) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
}


fn validateHostImportLine(tokens: []const lexer.Token, at_idx: usize, import_end: usize) !void {
    if (at_idx + 5 > import_end) return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (!tokEq(tokens[at_idx], "@")) return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (tokens[at_idx + 1].kind != .ident) return markErrorAt(tokens, at_idx + 1, error.InvalidImportDecl);
    if (!tokEq(tokens[at_idx + 2], "(")) return markErrorAt(tokens, at_idx + 2, error.InvalidImportDecl);
    if (tokens[at_idx + 3].kind != .string) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);

    const target = stringTokenBody(tokens[at_idx + 3].lexeme) orelse return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    const kind = try validateHostImportTarget(tokens, at_idx, at_idx + 1);
    const comma_idx = findTopLevelComma(tokens, at_idx + 4, import_end - 1) orelse return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    if (comma_idx + 1 >= import_end - 1) return markErrorAt(tokens, comma_idx, error.InvalidImportDecl);
    try validateHostSignature(tokens, comma_idx + 1, import_end - 1, kind);
    if (kind == .wasi) {
        try validateKnownWasiSignature(tokens, at_idx + 3, target, comma_idx + 1, import_end - 1);
    }
}


fn validateHostImportTarget(tokens: []const lexer.Token, at_idx: usize, name_idx: usize) !HostImportKind {
    const target = stringTokenBody(tokens[at_idx + 3].lexeme) orelse return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    if (std.mem.eql(u8, tokens[name_idx].lexeme, "env")) {
        if (!isValidPathSeg(target)) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
        return .env;
    }
    if (std.mem.eql(u8, tokens[name_idx].lexeme, "wasi_func")) {
        if (!isValidWitTargetPath(target)) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
        return .wasi;
    }
    return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
}


fn validateHostSignature(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !void {
    if (start_idx >= end_idx) return markErrorAt(tokens, @min(start_idx, tokens.len - 1), error.InvalidImportDecl);
    if (!tokEq(tokens[start_idx], "(")) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    if (close_idx + 3 >= end_idx or !tokEq(tokens[close_idx + 1], "-") or !tokEq(tokens[close_idx + 2], ">")) return markErrorAt(tokens, close_idx, error.InvalidImportDecl);
    try validateHostImportParams(tokens, start_idx + 1, close_idx, kind);
    try validateHostReturnType(tokens, close_idx + 3, end_idx, kind);
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

fn validateKnownWasiSignature(
    tokens: []const lexer.Token,
    site_idx: usize,
    target: []const u8,
    sig_start: usize,
    sig_end: usize,
) !void {
    const known = findKnownWasiSignature(target) orelse return;
    const close_idx = findMatching(tokens, sig_start, "(", ")") catch
        return markErrorAt(tokens, sig_start, error.InvalidImportDecl);
    if (close_idx + 3 >= sig_end or !tokEq(tokens[close_idx + 1], "-") or !tokEq(tokens[close_idx + 2], ">")) {
        return markErrorAt(tokens, sig_start, error.InvalidImportDecl);
    }
    const params_ok = compactTokenRangeEquals(tokens, sig_start + 1, close_idx, known.params) or
        (known.do_params != null and compactTokenRangeEquals(tokens, sig_start + 1, close_idx, known.do_params.?)) or
        (known.do_params_alt != null and compactTokenRangeEquals(tokens, sig_start + 1, close_idx, known.do_params_alt.?)) or
        (known.do_params_alt2 != null and compactTokenRangeEquals(tokens, sig_start + 1, close_idx, known.do_params_alt2.?));
    const result_ok = compactTokenRangeEquals(tokens, close_idx + 3, sig_end, known.result) or
        (known.do_result != null and compactTokenRangeEquals(tokens, close_idx + 3, sig_end, known.do_result.?)) or
        (known.do_result_alt != null and compactTokenRangeEquals(tokens, close_idx + 3, sig_end, known.do_result_alt.?)) or
        (known.do_result_alt2 != null and compactTokenRangeEquals(tokens, close_idx + 3, sig_end, known.do_result_alt2.?)) or
        (known.do_result_alt3 != null and compactTokenRangeEquals(tokens, close_idx + 3, sig_end, known.do_result_alt3.?)) or
        (known.do_result_alt4 != null and compactTokenRangeEquals(tokens, close_idx + 3, sig_end, known.do_result_alt4.?));
    if (!params_ok or !result_ok) {
        return markErrorAt(tokens, site_idx, error.InvalidImportDecl);
    }
    if (known.result_record) |record| {
        if (!knownWasiRecordMirrorMatches(tokens, record)) return markErrorAt(tokens, site_idx, error.InvalidImportDecl);
    }
}


fn findKnownWasiSignature(target: []const u8) ?KnownWasiSignature {
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
            // Preferred do form packs Dir shells; bracket sugar not yet valid on wasi_func result.
            // compactTokenRangeEquals ignores whitespace, so spaces in source are fine.
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
        .{ .target = "sockets/types/tcp-socket.create", .params = "ip-address-family", .result = "result<tcp-socket,error-code>" },
        .{ .target = "sockets/types/tcp-socket.bind", .params = "tcp-socket,ip-socket-address", .result = "result<_,error-code>" },
        .{ .target = "sockets/types/udp-socket.create", .params = "ip-address-family", .result = "result<udp-socket,error-code>" },
        .{ .target = "sockets/types/udp-socket.bind", .params = "udp-socket,ip-socket-address", .result = "result<_,error-code>" },
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

fn knownWasiRecordMirrorMatches(tokens: []const lexer.Token, record: KnownWasiRecord) bool {
    const decl = findPublicStructDecl(tokens, record.name) orelse return false;

    var field_idx: usize = 0;
    var i = decl.open_idx + 1;
    while (i < decl.close_idx) {
        const line_end = findLineEndIdx(tokens, i);
        if (tokens[i].kind != .ident or !isStructFieldName(tokens[i].lexeme) or i + 1 >= line_end) {
            i = line_end;
            continue;
        }
        if (field_idx >= record.fields.len) return false;

        const expected = record.fields[field_idx];
        if (!std.mem.eql(u8, normalizeStructFieldName(tokens[i].lexeme), expected.name)) return false;

        const type_end = findStructFieldTypeEnd(tokens, i + 1, line_end);
        if (!compactTokenRangeEquals(tokens, i + 1, type_end, expected.ty)) return false;

        field_idx += 1;
        i = line_end;
    }

    return field_idx == record.fields.len;
}


fn validateHostImportParams(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !void {
    var i = start_idx;
    while (i < end_idx) {
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }

        const next = try validateHostParamType(tokens, i, end_idx, kind);
        i = next;
        if (i < end_idx) {
            if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, error.InvalidImportDecl);
            i += 1;
        }
    }
}


fn validateHostReturnType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !void {
    const next = try validateHostReturnTypeAt(tokens, start_idx, end_idx, kind);
    if (next != end_idx) return markErrorAt(tokens, next, error.InvalidImportDecl);
}


fn validateHostParamType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !usize {
    if (start_idx >= end_idx) return markErrorAt(tokens, @min(start_idx, tokens.len - 1), error.InvalidImportDecl);
    switch (kind) {
        .env => {
            if (tokens[start_idx].kind == .ident and isHostParamType(tokens[start_idx].lexeme)) {
                return start_idx + 1;
            }
            return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
        },
        .wasi => {
            const next = parseWitType(tokens, start_idx, end_idx) orelse
                return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
            return next;
        },
    }
}


fn validateHostReturnTypeAt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !usize {
    if (start_idx >= end_idx) return markErrorAt(tokens, @min(start_idx, tokens.len - 1), error.InvalidImportDecl);
    switch (kind) {
        .env => {
            if (tokens[start_idx].kind == .ident and isHostReturnType(tokens[start_idx].lexeme)) {
                return start_idx + 1;
            }
            return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
        },
        .wasi => {
            // Accept WIT types and do exclusive unions (`nil | i32`, `Dir | i32`, …).
            const next = parseWitOrDoUnionType(tokens, start_idx, end_idx) orelse
                return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
            return next;
        },
    }
}

/// WIT type, or do exclusive union of WIT/do arms separated by `|` (spaces ignored by token stream).

/// WIT type, or do exclusive union of WIT/do arms separated by `|` (spaces ignored by token stream).
fn parseWitOrDoUnionType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var next = parseWitType(tokens, start_idx, end_idx) orelse return null;
    while (next < end_idx and tokEq(tokens[next], "|")) {
        const arm_end = parseWitType(tokens, next + 1, end_idx) orelse return null;
        next = arm_end;
    }
    return next;
}


fn isValidWitTargetPath(path: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= path.len) {
        const slash_idx = std.mem.indexOfScalarPos(u8, path, start, '/') orelse path.len;
        const seg = path[start..slash_idx];
        if (!isValidWitPathName(seg)) return false;
        count += 1;
        if (slash_idx == path.len) break;
        start = slash_idx + 1;
    }
    return count >= 3;
}


fn isHostParamType(name: []const u8) bool {
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


fn isHostReturnType(name: []const u8) bool {
    if (std.mem.eql(u8, name, "nil")) return true;
    return isHostParamType(name);
}


fn parseWitType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;
    // Do storage sugar: `[T]` where T is any parseable host type (u8, Tuple<…>, …).
    if (tokEq(tokens[start_idx], "[")) {
        const elem_end = parseWitType(tokens, start_idx + 1, end_idx) orelse return null;
        if (elem_end >= end_idx or !tokEq(tokens[elem_end], "]")) return null;
        return elem_end + 1;
    }
    if (tokens[start_idx].kind != .ident) return null;
    const name = tokens[start_idx].lexeme;

    if (std.mem.eql(u8, name, "list")) {
        if (start_idx + 2 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return null;
        const item_end = parseWitType(tokens, start_idx + 2, end_idx) orelse return null;
        if (item_end >= end_idx or !tokEq(tokens[item_end], ">")) return null;
        return item_end + 1;
    }

    if (std.mem.eql(u8, name, "result")) {
        if (start_idx + 4 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return null;
        const ok_end = parseWitType(tokens, start_idx + 2, end_idx) orelse return null;
        if (ok_end >= end_idx or !tokEq(tokens[ok_end], ",")) return null;
        const err_end = parseWitType(tokens, ok_end + 1, end_idx) orelse return null;
        if (err_end >= end_idx or !tokEq(tokens[err_end], ">")) return null;
        return err_end + 1;
    }

    // WIT `tuple<…>` and do `Tuple<…>` sugar (same shape; do capital-T form for host Ok|Err).
    if (std.mem.eql(u8, name, "tuple") or std.mem.eql(u8, name, "Tuple")) {
        if (start_idx + 4 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return null;
        var i = start_idx + 2;
        var count: usize = 0;
        while (i < end_idx) {
            const next = parseWitType(tokens, i, end_idx) orelse return null;
            count += 1;
            i = next;
            if (i >= end_idx) return null;
            if (tokEq(tokens[i], ">")) return if (count >= 2) i + 1 else null;
            if (!tokEq(tokens[i], ",")) return null;
            i += 1;
        }
        return null;
    }

    if (std.mem.eql(u8, name, "option") or std.mem.eql(u8, name, "borrow") or std.mem.eql(u8, name, "own")) {
        if (start_idx + 2 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return null;
        const item_end = parseWitType(tokens, start_idx + 2, end_idx) orelse return null;
        if (item_end >= end_idx or !tokEq(tokens[item_end], ">")) return null;
        return item_end + 1;
    }

    if (std.mem.eql(u8, name, "_")) return start_idx + 1;
    if (hasPublicStructDecl(tokens, name)) return start_idx + 1;
    // P4: coarse do error enums in host Ok|Err results (DirError / FileError).
    // Forward refs allowed: name ends with Error (same as resource names in host params).
    if (isErrorTypeName(name)) return start_idx + 1;

    return parseWitName(tokens, start_idx, end_idx);
}


fn hasPublicStructDecl(tokens: []const lexer.Token, name: []const u8) bool {
    return findPublicStructDecl(tokens, name) != null;
}


fn findPublicStructDecl(tokens: []const lexer.Token, name: []const u8) ?StructDeclRange {
    if (!isValidDeclaredTypeName(name)) return null;

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (skipTopLevelImportBrace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        // Classic: Name { fields }
        if (i + 1 < tokens.len and tokEq(tokens[i + 1], "{")) {
            const close_idx = findMatching(tokens, i + 1, "{", "}") catch return null;
            return .{ .open_idx = i + 1, .close_idx = close_idx };
        }
        // Declarative: Name = @wasi_record|wasi_resource("…", { fields })
        if (wasiStructFieldsRange(tokens, i)) |fields| {
            return .{ .open_idx = fields.open, .close_idx = fields.close };
        }
    }
    return null;
}

const BraceRange = struct { open: usize, close: usize };

fn wasiStructFieldsRange(tokens: []const lexer.Token, name_idx: usize) ?BraceRange {
    if (name_idx + 5 >= tokens.len) return null;
    if (!tokEq(tokens[name_idx + 1], "=") or !tokEq(tokens[name_idx + 2], "@")) return null;
    if (tokens[name_idx + 3].kind != .ident) return null;
    const kind = tokens[name_idx + 3].lexeme;
    if (!std.mem.eql(u8, kind, "wasi_record") and !std.mem.eql(u8, kind, "wasi_resource")) return null;
    if (!tokEq(tokens[name_idx + 4], "(")) return null;
    const close_call = findMatching(tokens, name_idx + 4, "(", ")") catch return null;
    var j = name_idx + 5;
    while (j < close_call) : (j += 1) {
        if (!tokEq(tokens[j], "{")) continue;
        const close_brace = findMatching(tokens, j, "{", "}") catch return null;
        return .{ .open = j, .close = close_brace };
    }
    return null;
}


fn parseWitName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (tokens[start_idx].kind != .ident or !isValidWitPathName(tokens[start_idx].lexeme)) return null;
    var i = start_idx + 1;
    while (i + 1 < end_idx and tokEq(tokens[i], "-")) {
        if (tokens[i + 1].kind != .ident or !isValidWitPathName(tokens[i + 1].lexeme)) return null;
        i += 2;
    }
    return i;
}


fn isValidWitPathName(name: []const u8) bool {
    var start: usize = 0;
    while (start <= name.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, name, start, '.') orelse name.len;
        if (!isValidWitNamePart(name[start..dot_idx])) return false;
        if (dot_idx == name.len) return true;
        start = dot_idx + 1;
    }
    return false;
}


fn isValidWitNamePart(name: []const u8) bool {
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


