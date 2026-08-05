//! Source facts for the pinned wasi:filesystem package used by P3 lowering.
//!
//! This module is deliberately narrow. It verifies the checked-in WIT source
//! and exposes only the record mirror needed by the admitted read-directory
//! slice. It is not a general WIT parser or a license to lower arbitrary
//! record streams.
const std = @import("std");

pub const source_commit = "90fed3c6adf53f112c4dea56851728557bb73799";
pub const source_path = "src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16";
pub const directory_types_path = source_path ++ "/deps/filesystem/types.wit";
pub const directory_world_path = source_path ++ "/deps/filesystem/world.wit";
pub const preopens_path = source_path ++ "/deps/filesystem/preopens.wit";

pub const directory_types_sha256 = "8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f";
pub const directory_world_sha256 = "22a2958e41ca0d982add92116c5ba9d3d9ff46ff1df23f4633c6fc36f492ee49";
pub const preopens_sha256 = "941830f054859fa1322ffbc36289cb43f1d798a232dec913ee3ca2dda05546a8";

pub const directory_entry_target = "filesystem/types/directory-entry";
pub const directory_entry_name = "directory-entry";

pub const RecordField = struct {
    source_name: []const u8,
    source_type: []const u8,
    do_name: []const u8,
    do_type: []const u8,
};

pub const directory_entry_fields = [_]RecordField{
    .{ .source_name = "%type", .source_type = "descriptor-type", .do_name = "type", .do_type = "i32" },
    .{ .source_name = "name", .source_type = "string", .do_name = "name", .do_type = "text" },
};

/// Verify the checked-in package and the exact source record used by the
/// admitted record-stream descriptor.
pub fn validate() !void {
    const types = @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit");
    try verify_sha256(types, directory_types_sha256);
    try verify_sha256(@embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/world.wit"), directory_world_sha256);
    try verify_sha256(@embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/preopens.wit"), preopens_sha256);
    try validate_record_source(types);
    if (std.mem.indexOf(u8, types, "read-directory: async func() -> tuple<stream<directory-entry>, future<result<_, error-code>>>;") == null) {
        return error.InvalidPinnedFilesystemWit;
    }
}

pub fn record_field_count() usize {
    return directory_entry_fields.len;
}

pub fn record_field(index: usize) ?RecordField {
    if (index >= directory_entry_fields.len) return null;
    return directory_entry_fields[index];
}

fn validate_record_source(source: []const u8) !void {
    const body = find_record_body(source, directory_entry_name) orelse return error.InvalidPinnedFilesystemWit;
    var compact: [256]u8 = undefined;
    const compact_body = compact_wit_body(source[body.open..body.close], &compact) catch return error.InvalidPinnedFilesystemWit;
    const expected = "%type:descriptor-type,name:string,";
    if (!std.mem.eql(u8, compact_body, expected)) return error.InvalidPinnedFilesystemWit;
}

const BodyRange = struct { open: usize, close: usize };

fn find_record_body(source: []const u8, name: []const u8) ?BodyRange {
    var pos: usize = 0;
    while (pos < source.len) {
        const record_pos = std.mem.indexOfPos(u8, source, pos, "record") orelse return null;
        const before_ok = record_pos == 0 or !is_name_char(source[record_pos - 1]);
        const after_record = record_pos + "record".len;
        if (!before_ok or after_record >= source.len or !is_space(source[after_record])) {
            pos = after_record;
            continue;
        }

        var cursor = skip_space(source, after_record);
        const name_start = cursor;
        while (cursor < source.len and is_name_char(source[cursor])) : (cursor += 1) {}
        if (!std.mem.eql(u8, source[name_start..cursor], name)) {
            pos = cursor;
            continue;
        }
        cursor = skip_space(source, cursor);
        if (cursor >= source.len or source[cursor] != '{') return null;
        const open = cursor;
        cursor += 1;
        while (cursor < source.len and source[cursor] != '}') : (cursor += 1) {}
        if (cursor >= source.len) return null;
        return .{ .open = open + 1, .close = cursor };
    }
    return null;
}

fn compact_wit_body(body: []const u8, buffer: *[256]u8) ![]const u8 {
    var length: usize = 0;
    var i: usize = 0;
    while (i < body.len) {
        if (body[i] == '/' and i + 1 < body.len and body[i + 1] == '/') {
            i += 2;
            while (i < body.len and body[i] != '\n') : (i += 1) {}
            continue;
        }
        if (is_space(body[i])) {
            i += 1;
            continue;
        }
        if (length >= buffer.len) return error.InvalidPinnedFilesystemWit;
        buffer[length] = body[i];
        length += 1;
        i += 1;
    }
    return buffer[0..length];
}

fn is_space(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}

fn is_name_char(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or
        (byte >= 'A' and byte <= 'Z') or
        (byte >= '0' and byte <= '9') or
        byte == '-' or byte == '_';
}

fn skip_space(source: []const u8, start: usize) usize {
    var cursor = start;
    while (cursor < source.len and is_space(source[cursor])) : (cursor += 1) {}
    return cursor;
}

fn verify_sha256(bytes: []const u8, expected: []const u8) !void {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});

    var actual: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 = undefined;
    for (digest, 0..) |byte, index| {
        actual[index * 2] = hex_digit(byte >> 4);
        actual[index * 2 + 1] = hex_digit(byte & 0x0f);
    }
    if (!std.mem.eql(u8, &actual, expected)) return error.InvalidPinnedFilesystemWit;
}

fn hex_digit(value: u8) u8 {
    return if (value < 10) '0' + value else 'a' + (value - 10);
}

test "pinned filesystem source preserves directory-entry record" {
    try validate();
    try std.testing.expectEqualStrings("filesystem/types/directory-entry", directory_entry_target);
    try std.testing.expectEqualStrings("%type", directory_entry_fields[0].source_name);
    try std.testing.expectEqualStrings("descriptor-type", directory_entry_fields[0].source_type);
    try std.testing.expectEqualStrings("type", directory_entry_fields[0].do_name);
    try std.testing.expectEqualStrings("i32", directory_entry_fields[0].do_type);
    try std.testing.expectEqualStrings("name", directory_entry_fields[1].source_name);
    try std.testing.expectEqualStrings("string", directory_entry_fields[1].source_type);
    try std.testing.expectEqualStrings("text", directory_entry_fields[1].do_type);
}

test "filesystem source record parser rejects drift" {
    const source =
        "record directory-entry { %type: descriptor-type, name: u32, }";
    const body = find_record_body(source, "directory-entry") orelse return error.TestUnexpectedResult;
    var compact: [256]u8 = undefined;
    const compact_body = try compact_wit_body(source[body.open..body.close], &compact);
    try std.testing.expect(!std.mem.eql(u8, compact_body, "%type:descriptor-type,name:string,"));
}
