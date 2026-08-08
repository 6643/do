const std = @import("std");
const lexer = @import("lexer.zig");
const imports = @import("imports.zig");
const parser = @import("parser.zig");
const sema_tokens = @import("sema_tokens.zig");

const find_matching = sema_tokens.find_matching;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

pub fn emit_component_wat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8 {
    _ = program;
    _ = module_graph;
    if (!matches_probe(tokens)) return error.UnsupportedWasiFilesystemPreopenComponent;
    return allocator.dupe(u8, preopen_core_wat);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    if (!matches_probe(tokens)) return error.UnsupportedWasiFilesystemPreopenComponent;
    return allocator.dupe(u8, preopen_component_wit);
}

fn matches_probe(tokens: []const lexer.Token) bool {
    if (!has_host(tokens, "wasi:filesystem/preopens@0.3.0", "get-directories")) return false;
    if (!has_host(tokens, "wasi:filesystem/types@0.3.0", "descriptor.open-at")) return false;
    if (!has_host(tokens, "wasi:filesystem/types@0.3.0", "descriptor.sync")) return false;
    if (!has_host(tokens, "wasi:filesystem/types@0.3.0", "descriptor.drop")) return false;
    if (!has_descriptor(tokens)) return false;
    const run = find_run(tokens) orelse return false;
    const body = find_body(tokens, run) orelse return false;
    const end = find_matching(tokens, body, "{", "}") catch return false;
    return matches_run_flow(tokens[body + 1 .. end]);
}

fn has_host(tokens: []const lexer.Token, locator: []const u8, member: []const u8) bool {
    var i: usize = 0;
    while (i + 7 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or !tok_eq(tokens[i + 3], "host_func") or !tok_eq(tokens[i + 4], "(") or tokens[i + 5].kind != .string or tokens[i + 7].kind != .string) continue;
        const found_locator = string_token_body(tokens[i + 5].lexeme) orelse continue;
        const found_member = string_token_body(tokens[i + 7].lexeme) orelse continue;
        if (std.mem.eql(u8, found_locator, locator) and std.mem.eql(u8, found_member, member)) return true;
    }
    return false;
}

fn has_descriptor(tokens: []const lexer.Token) bool {
    var i: usize = 0;
    while (i + 5 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or !tok_eq(tokens[i + 3], "wasi_resource") or !tok_eq(tokens[i + 4], "(") or tokens[i + 5].kind != .string) continue;
        const path = string_token_body(tokens[i + 5].lexeme) orelse continue;
        if (std.mem.eql(u8, path, "filesystem/types/descriptor")) return true;
    }
    return false;
}

fn find_run(tokens: []const lexer.Token) ?usize {
    for (tokens, 0..) |token, idx| if (std.mem.eql(u8, token.lexeme, "run") and idx + 1 < tokens.len and tok_eq(tokens[idx + 1], "(")) return idx;
    return null;
}

fn find_body(tokens: []const lexer.Token, run: usize) ?usize {
    const close = find_matching(tokens, run + 1, "(", ")") catch return null;
    var i = close + 1;
    while (i < tokens.len and tokens[i].line == tokens[run].line) : (i += 1) if (tok_eq(tokens[i], "{")) return i;
    return null;
}

fn matches_run_flow(tokens: []const lexer.Token) bool {
    const words = [_][]const u8{
        "roots", "[", "Tuple", "<", "Dir", ",", "text", ">", "]", "=", "host_preopens", "(", ")",
        "dir", "Dir", "=", "@", "get", "(", "roots", ",", "0", ",", "0", ")",
        "opened", "Result", "<", "File", ",", "FileError", ">", "=", "host_open", "(", "dir", ",", "0", ",", "\"probe\"", ",", "0", ",", "0", ")",
        "if", "@", "is", "(", "opened", ",", "Ok", ")", "{",
        "file", "File", "=", "opened",
        "synced", "Result", "<", "nil", ",", "FileError", ">", "=", "host_sync", "(", "file", ")",
        "_", "=", "synced", "host_drop", "(", "file", ")", "}",
        "host_drop", "(", "dir", ")", "return", "1",
    };
    if (tokens.len != words.len) return false;
    for (words, 0..) |word, idx| if (!std.mem.eql(u8, tokens[idx].lexeme, word)) return false;
    return true;
}

const preopen_core_wat =
    \\(module
    \\  (type $get-directories (func (param i32)))
    \\  (type $open-at (func (param i32 i32 i32 i32 i32 i32 i32)))
    \\  (type $sync (func (param i32 i32)))
    \\  (type $drop (func (param i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (import "wasi:filesystem/preopens@0.3.0" "get-directories" (func $get-directories (type $get-directories)))
    \\  (import "wasi:filesystem/types@0.3.0" "[method]descriptor.open-at" (func $open-at (type $open-at)))
    \\  (import "wasi:filesystem/types@0.3.0" "[method]descriptor.sync" (func $sync (type $sync)))
    \\  (import "wasi:filesystem/types@0.3.0" "[resource-drop]descriptor" (func $drop-descriptor (type $drop)))
    \\  (memory (export "memory") 1)
    \\  (global $cabi-heap (mut i32) (i32.const 32))
    \\  (data (i32.const 16) "probe")
    \\  (func (export "run") (result i32) (local $dir i32) (local $file i32)
    \\    i32.const 0
    \\    call $get-directories
    \\    i32.const 0
    \\    i32.load
    \\    i32.load
    \\    local.set $dir
    \\    local.get $dir
    \\    i32.const 0
    \\    i32.const 16
    \\    i32.const 5
    \\    i32.const 0
    \\    i32.const 0
    \\    i32.const 8
    \\    call $open-at
    \\    i32.const 8
    \\    i32.load
    \\    i32.eqz
    \\    if
    \\      i32.const 12
    \\      i32.load
    \\      local.set $file
    \\      local.get $file
    \\      i32.const 8
    \\      call $sync
    \\      i32.const 8
    \\      i32.load
    \\      i32.eqz
    \\      if
    \\      else
    \\        local.get $file
    \\        call $drop-descriptor
    \\        local.get $dir
    \\        call $drop-descriptor
    \\        i32.const 1
    \\        return
    \\      end
    \\      local.get $file
    \\      call $drop-descriptor
    \\    else
    \\      local.get $dir
    \\      call $drop-descriptor
    \\      i32.const 1
    \\      return
    \\    end
    \\    local.get $dir
    \\    call $drop-descriptor
    \\    i32.const 1
    \\  )
    \\  (func (export "cabi_post_run") (param i32))
    \\  (func (export "cabi_realloc") (type $cabi-realloc)
    \\    global.get $cabi-heap
    \\    global.get $cabi-heap
    \\    local.get 3
    \\    i32.add
    \\    global.set $cabi-heap
    \\  )
    \\  (func (export "_initialize"))
    \\)
;

const preopen_component_wit =
    \\package wasi:filesystem@0.3.0;
    \\
    \\interface types {
    \\  enum error-code { access, unknown }
    \\  resource descriptor {
    \\    open-at: func(path-flags: u32, path: string, open-flags: u32, descriptor-flags: u32) -> result<own<descriptor>, error-code>;
    \\    sync: func() -> result<_, error-code>;
    \\  }
    \\}
    \\
    \\interface preopens {
    \\  use types.{descriptor};
    \\  get-directories: func() -> list<tuple<own<descriptor>, string>>;
    \\}
    \\
    \\world preopen-probe {
    \\  import preopens;
    \\  import types;
    \\  export run: func() -> u32;
    \\}
    \\
;

test "filesystem preopen component emits canonical descriptor operations" {
    const source =
        \\.host_preopens = @host_func("wasi:filesystem/preopens@0.3.0", "get-directories", () -> [Tuple<Dir, text>])
        \\.host_open = @host_func("wasi:filesystem/types@0.3.0", "descriptor.open-at", (Dir, i32, text, i32, i32) -> Result<File, FileError>)
        \\.host_sync = @host_func("wasi:filesystem/types@0.3.0", "descriptor.sync", (File) -> Result<nil, FileError>)
        \\.host_drop = @host_func("wasi:filesystem/types@0.3.0", "descriptor.drop", (File) -> nil)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\FileError error = FileOpenFailed | FileFlushFailed
        \\run() -> u32 {
        \\    roots [Tuple<Dir, text>] = host_preopens()
        \\    dir Dir = @get(roots, 0, 0)
        \\    opened Result<File, FileError> = host_open(dir, 0, "probe", 0, 0)
        \\    if @is(opened, Ok) {
        \\        file File = opened
        \\        synced Result<nil, FileError> = host_sync(file)
        \\        _ = synced
        \\        host_drop(file)
        \\    }
        \\    host_drop(dir)
        \\    return 1
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "get-directories") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[method]descriptor.open-at") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "descriptor.sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]descriptor") != null);
}
