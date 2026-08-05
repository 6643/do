const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("model.zig");
const parser = @import("parser.zig");
const resolve = @import("resolve.zig");
const emit_do = @import("emit_do.zig");
const emit_lock = @import("emit_lock.zig");
const emit_manifest = @import("emit_manifest.zig");
const wit_cli = @import("cli.zig");
const wit_manifest = @import("manifest.zig");

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

test "wit resolver merges local package files deterministically" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "api.wit",
        .data =
        \\package demo:multi@1.0.0;
        \\
        \\interface api {}
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.wit",
        .data =
        \\package demo:multi@1.0.0;
        \\
        \\world probe { import api; }
        ,
    });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(path);
    var binding = try resolve.resolve_input(std.testing.io, std.testing.allocator, path, "probe");
    defer binding.deinit();
    try std.testing.expectEqual(@as(usize, 1), binding.interfaces.len);
    try std.testing.expectEqualStrings("api", binding.interfaces[0].name);
}

test "wit resolver rejects duplicate package identities" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "a.wit",
        .data =
        \\package demo:a@1.0.0;
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "b.wit",
        .data =
        \\package demo:b@1.0.0;
        ,
    });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(path);
    try std.testing.expectError(
        error.DuplicatePackage,
        resolve.resolve_input(std.testing.io, std.testing.allocator, path, null),
    );
}

test "wit resolver rejects missing local use targets" {
    const source =
        \\package demo:refs@1.0.0;
        \\
        \\interface api { use missing.{item}; }
        \\
        \\world probe { import api; }
    ;
    try std.testing.expectError(
        error.UnresolvedUse,
        resolve.resolve_source(std.testing.allocator, source, "probe"),
    );
}

test "wit resolver resolves a qualified world import from a dependency package" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "deps", .default_dir);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.wit",
        .data =
        \\package demo:app@1.0.0;
        \\
        \\world app { import dep:types/types; }
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "deps/types.wit",
        .data =
        \\package dep:types@1.0.0;
        \\
        \\interface types { record item { value: u32, } get: func() -> item; }
        ,
    });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(path);
    var binding = try resolve.resolve_input(std.testing.io, std.testing.allocator, path, "app");
    defer binding.deinit();
    try std.testing.expectEqualStrings("types", binding.interfaces[0].name);
    try std.testing.expectEqualStrings("dep", binding.interfaces[0].package.?.namespace);
    const generated = try emit_do.render_module(std.testing.allocator, binding, binding.interfaces[0]);
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "dep:types/types@1.0.0") != null);
    const manifest = try emit_manifest.render(std.testing.allocator, binding, "dep_types__types__app.do");
    defer std.testing.allocator.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"package\":\"dep:types@1.0.0\"") != null);
    const lock = try emit_lock.render(std.testing.allocator, binding);
    defer std.testing.allocator.free(lock);
    try std.testing.expect(std.mem.indexOf(u8, lock, "package=dep:types@1.0.0") != null);
}

test "wit resolver rejects include cycles" {
    const source =
        \\package demo:cycle@1.0.0;
        \\
        \\interface a { include b; }
        \\interface b { include a; }
        \\
        \\world probe { import a; }
    ;
    try std.testing.expectError(
        error.IncludeCycle,
        resolve.resolve_source(std.testing.allocator, source, "probe"),
    );
}

test "wit emitter translates the probe world into deterministic Do bindings" {
    var binding = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer binding.deinit();

    const name = try emit_do.module_name(std.testing.allocator, binding.package, binding.world, binding.interfaces[0]);
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("do_bindgen_probe__api__probe.do", name);

    const source = try emit_do.render_module(std.testing.allocator, binding, binding.interfaces[0]);
    defer std.testing.allocator.free(source);
    try std.testing.expect(std.mem.indexOf(u8, source, "Request = @wasi_resource") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "send = @host(\"do:bindgen-probe/api@0.1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "Response | ApiError") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "-> Future<Response | ApiError>") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "Future<u32>") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "Stream<u8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "async send") == null);
}

test "wit emitter renders stable manifest and lock records" {
    var binding = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer binding.deinit();

    const manifest = try emit_manifest.render(std.testing.allocator, binding, "do_bindgen_probe__api__probe.do");
    defer std.testing.allocator.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"schema\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"world\":\"probe\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"async\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"future\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"stream\"") != null);
    var parsed_manifest = try wit_manifest.parse(std.testing.allocator, manifest);
    defer parsed_manifest.deinit(std.testing.allocator);
    try wit_manifest.validate_binding(std.testing.allocator, &parsed_manifest, binding);

    const lock = try emit_lock.render(std.testing.allocator, binding);
    defer std.testing.allocator.free(lock);
    try std.testing.expectEqualStrings(
        "schema=1\npackage=do:bindgen-probe@0.1.0\nsha256=",
        lock[0.."schema=1\npackage=do:bindgen-probe@0.1.0\nsha256=".len],
    );
    try std.testing.expectEqual(@as(usize, 64), lock["schema=1\npackage=do:bindgen-probe@0.1.0\nsha256=".len..].len);
}

test "wit emitter writes modules atomically and preserves old output on failure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const output = try std.fs.path.join(std.testing.allocator, &.{ root, "wit" });
    defer std.testing.allocator.free(output);

    var binding = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer binding.deinit();
    try emit_do.emit_all(std.testing.io, std.testing.allocator, binding, output);

    const generated_path = try std.fs.path.join(std.testing.allocator, &.{ output, "do_bindgen_probe__api__probe.do" });
    defer std.testing.allocator.free(generated_path);
    const generated = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, generated_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "send = @host") != null);
    const first_output = try std.testing.allocator.dupe(u8, generated);
    defer std.testing.allocator.free(first_output);
    try emit_do.emit_all(std.testing.io, std.testing.allocator, binding, output);
    const regenerated = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, generated_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(regenerated);
    try std.testing.expectEqualStrings(first_output, regenerated);

    const marker = try std.fs.path.join(std.testing.allocator, &.{ output, "marker.txt" });
    defer std.testing.allocator.free(marker);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = marker, .data = "keep" });

    const unsupported_source =
        \\package demo:unsupported@1.0.0;
        \\
        \\interface api { flags perms { read, } }
        \\
        \\world probe { import api; }
    ;
    var unsupported = try resolve.resolve_source(std.testing.allocator, unsupported_source, "probe");
    defer unsupported.deinit();
    try std.testing.expectError(
        error.UnsupportedShape,
        emit_do.emit_all(std.testing.io, std.testing.allocator, unsupported, output),
    );
    const preserved = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, marker, std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(preserved);
    try std.testing.expectEqualStrings("keep", preserved);
}

test "wit emitter rejects flat module name collisions" {
    const source =
        \\package demo:collision@1.0.0;
        \\
        \\interface a-b {}
        \\interface a_b {}
        \\
        \\world probe { import a-b; import a_b; }
    ;
    var binding = try resolve.resolve_source(std.testing.allocator, source, "probe");
    defer binding.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const output = try std.fs.path.join(std.testing.allocator, &.{ root, "wit" });
    defer std.testing.allocator.free(output);
    try std.testing.expectError(
        error.OutputNameCollision,
        emit_do.emit_all(std.testing.io, std.testing.allocator, binding, output),
    );
}

test "wit cli parses check and bind forms without accepting extra arguments" {
    const check = try wit_cli.parse(&.{ "check", "api.wit", "--world", "probe" });
    try std.testing.expectEqual(wit_cli.Action.check, check.action);
    try std.testing.expectEqualStrings("api.wit", check.input_path.?);
    try std.testing.expectEqualStrings("probe", check.world.?);
    try std.testing.expect(check.output_path == null);
    const checked_manifest = try wit_cli.parse(&.{ "check", "api.wit", "--world", "probe", "--manifest", "wit/manifest.json" });
    try std.testing.expectEqualStrings("wit/manifest.json", checked_manifest.manifest_path.?);

    const bind = try wit_cli.parse(&.{ "bind", "api.wit", "--world", "probe", "--out", "wit" });
    try std.testing.expectEqual(wit_cli.Action.bind, bind.action);
    try std.testing.expectEqualStrings("wit", bind.output_path.?);
    try std.testing.expectError(error.MissingWorld, wit_cli.parse(&.{ "bind", "api.wit", "--out", "wit" }));
    try std.testing.expectError(error.MissingOutput, wit_cli.parse(&.{ "bind", "api.wit", "--world", "probe" }));
    try std.testing.expectError(error.UnexpectedArgument, wit_cli.parse(&.{ "check", "api.wit", "extra" }));
}
