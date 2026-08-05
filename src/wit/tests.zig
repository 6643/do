const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("model.zig");
const parser = @import("parser.zig");
const resolve = @import("resolve.zig");

const probe_source =
    \\//@ async = true
    \\package do:bindgen-probe@0.1.0;
    \\
    \\interface api {
    \\  resource request {}
    \\  resource response {}
    \\
    \\  enum error {
    \\    failed,
    \\  }
    \\
    \\  send: async func(request: request) -> result<response, error>;
    \\  completion: func() -> future<u32>;
    \\  events: func() -> stream<u8>;
    \\}
    \\
    \\world probe {
    \\  import api;
    \\}
;

test "wit lexer records identifiers punctuation and source locations" {
    const source =
        "use dep.{record, list}; include base; type alias = option<borrow<Thing>>; " ++
        "resource item {} enum status { ready, } variant event { changed(u32), } " ++
        "flags perms { read, write, } async func run() -> future<u32>;";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(tokens.len > 20);
    try std.testing.expectEqualStrings("use", tokens[0].lexeme);
    try std.testing.expectEqualStrings("dep", tokens[1].lexeme);
    try std.testing.expectEqualStrings(".", tokens[2].lexeme);
    try std.testing.expectEqualStrings("{", tokens[3].lexeme);
    try std.testing.expectEqualStrings("record", tokens[4].lexeme);
    try std.testing.expectEqualStrings(",", tokens[5].lexeme);
    try std.testing.expectEqual(@as(usize, 1), tokens[0].line);
    try std.testing.expectEqual(@as(usize, 1), tokens[0].column);
    try std.testing.expectEqual(@as(usize, 5), tokens[1].column);
}

test "wit lexer rejects malformed strings and punctuation" {
    try std.testing.expectError(error.UnterminatedString, lexer.tokenize(std.testing.allocator, "\"unterminated"));
    try std.testing.expectError(error.InvalidPunctuation, lexer.tokenize(std.testing.allocator, "$"));
}

test "wit lexer keeps prerelease versions in one numeric token" {
    const tokens = try lexer.tokenize(std.testing.allocator, "package wasi:http@0.3.0-rc-2025-09-16;");
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqualStrings("0.3.0-rc-2025-09-16", tokens[5].lexeme);
}

test "wit parser builds the async resource future stream world" {
    var ast = try parser.parse(std.testing.allocator, probe_source);
    defer ast.deinit();

    try std.testing.expectEqualStrings("do", ast.package.namespace);
    try std.testing.expectEqualStrings("bindgen-probe", ast.package.name);
    try std.testing.expectEqual(@as(u32, 0), ast.package.version.major);
    try std.testing.expectEqual(@as(u32, 1), ast.package.version.minor);
    try std.testing.expectEqual(@as(u32, 0), ast.package.version.patch);
    try std.testing.expectEqual(@as(usize, 1), ast.interfaces.len);
    try std.testing.expectEqualStrings("api", ast.interfaces[0].name);
    try std.testing.expectEqual(@as(usize, 2), ast.interfaces[0].resources.len);
    try std.testing.expectEqual(@as(usize, 1), ast.interfaces[0].enums.len);
    try std.testing.expectEqual(@as(usize, 3), ast.interfaces[0].functions.len);

    const send = ast.interfaces[0].functions[0];
    try std.testing.expect(send.is_async);
    try std.testing.expectEqual(model.TypeKind.result, send.result.?.kind);
    try std.testing.expectEqual(model.TypeKind.named, send.params[0].type_ref.kind);

    const completion = ast.interfaces[0].functions[1];
    try std.testing.expect(!completion.is_async);
    try std.testing.expectEqual(model.TypeKind.future, completion.result.?.kind);
    try std.testing.expectEqual(model.TypeKind.u32, completion.result.?.args[0].kind);

    const events = ast.interfaces[0].functions[2];
    try std.testing.expectEqual(model.TypeKind.stream, events.result.?.kind);
    try std.testing.expectEqual(model.TypeKind.u8, events.result.?.args[0].kind);
    try std.testing.expectEqual(@as(usize, 1), ast.worlds.len);
    try std.testing.expectEqualStrings("probe", ast.worlds[0].name);
    try std.testing.expectEqual(@as(usize, 1), ast.worlds[0].imports.len);
}

test "wit parser rejects malformed package versions" {
    try std.testing.expectError(
        error.InvalidVersion,
        parser.parse(std.testing.allocator, "package do:test@1.x.0; world probe {}"),
    );
}

test "wit parser skips annotations and preserves prerelease package identity" {
    const source =
        \\@since(version = 0.3.0-rc-2025-09-16)
        \\package wasi:http@0.3.0-rc-2025-09-16;
        \\
        \\@docs("api")
        \\interface api {}
        \\
        \\world probe { import api; }
    ;
    var ast = try parser.parse(std.testing.allocator, source);
    defer ast.deinit();
    try std.testing.expectEqualStrings("rc-2025-09-16", ast.package.version.prerelease);
    try std.testing.expectEqualStrings("api", ast.interfaces[0].name);
}

test "wit parser retains interface type declarations and ownership wrappers" {
    const source =
        \\package demo:types@1.0.0;
        \\
        \\interface api {
        \\  use dep.{record, list};
        \\  include base;
        \\  type maybe = option<borrow<Thing>>;
        \\  record point { value: u32, }
        \\  variant event { changed(u32), untouched, }
        \\  enum status { ready, }
        \\  flags perms { read, write, }
        \\  take: func(value: own<Thing>) -> option<u32>;
        \\}
        \\
        \\world w { import api; }
    ;
    var ast = try parser.parse(std.testing.allocator, source);
    defer ast.deinit();

    const interface = ast.interfaces[0];
    try std.testing.expectEqual(@as(usize, 1), interface.uses.len);
    try std.testing.expectEqual(@as(usize, 1), interface.includes.len);
    try std.testing.expectEqual(@as(usize, 1), interface.aliases.len);
    try std.testing.expectEqual(model.TypeKind.option, interface.aliases[0].type_ref.kind);
    try std.testing.expectEqual(model.TypeKind.borrow, interface.aliases[0].type_ref.args[0].kind);
    try std.testing.expectEqual(model.OwnershipMode.borrowed, interface.aliases[0].type_ref.args[0].ownership);
    try std.testing.expectEqual(@as(usize, 1), interface.records.len);
    try std.testing.expectEqual(@as(usize, 1), interface.variants.len);
    try std.testing.expectEqual(@as(usize, 2), interface.variants[0].cases.len);
    try std.testing.expectEqual(@as(usize, 1), interface.enums.len);
    try std.testing.expectEqual(@as(usize, 1), interface.flags.len);
    try std.testing.expectEqual(model.TypeKind.own, interface.functions[0].params[0].type_ref.kind);
}

test "wit resolver selects world and computes stable content hash" {
    var binding = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer binding.deinit();

    try std.testing.expectEqualStrings("probe", binding.world.name);
    try std.testing.expectEqual(@as(usize, 1), binding.interfaces.len);
    try std.testing.expectEqualStrings("api", binding.interfaces[0].name);
    const zero_hash = [_]u8{0} ** 32;
    try std.testing.expect(!std.mem.eql(u8, &binding.content_hash, &zero_hash));
    try std.testing.expectEqual(@as(usize, 2), binding.interfaces[0].resources.len);
    try std.testing.expect(binding.interfaces[0].functions[0].effects.is_async);
    try std.testing.expectEqual(model.OwnershipMode.owned, binding.interfaces[0].functions[0].params[0].type_ref.ownership);
}

test "wit resolver rejects an unknown world" {
    try std.testing.expectError(
        error.WorldNotFound,
        resolve.resolve_source(std.testing.allocator, probe_source, "missing"),
    );
}

test "wit resolver accepts a file input path" {
    var binding = try resolve.resolve_input(
        std.testing.io,
        std.testing.allocator,
        "../examples/wit-bindgen-do/async-world.wit",
        "probe",
    );
    defer binding.deinit();
    try std.testing.expectEqualStrings("do", binding.package.namespace);
    try std.testing.expectEqualStrings("probe", binding.world.name);
    try std.testing.expect(binding.owns_source);
}

test "wit resolver selects the world file in a package directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.wit",
        .data =
        \\package demo:dir@1.0.0;
        \\
        \\interface api {}
        \\
        \\world probe { import api; }
        ,
    });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(path);
    var binding = try resolve.resolve_input(std.testing.io, std.testing.allocator, path, "probe");
    defer binding.deinit();
    try std.testing.expectEqualStrings("demo", binding.package.namespace);
    try std.testing.expectEqualStrings("probe", binding.world.name);
}
