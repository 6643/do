const std = @import("std");
const manifest = @import("manifest.zig");
const async_lowering = @import("async_lowering.zig");
const resolve = @import("resolve.zig");
const emit_manifest = @import("emit_manifest.zig");
const emit_do = @import("emit_do.zig");

const probe_source =
    \\package do:bindgen-probe@0.1.0;
    \\
    \\interface api {
    \\  send: async func() -> result<u32, u8>;
    \\  completion: func() -> future<u32>;
    \\}
    \\
    \\world probe { import api; }
;

const pinned_async_source =
    \\package do:generic-async-runtime-probe@0.1.0;
    \\
    \\interface host {
    \\  work: async func();
    \\}
    \\
    \\world probe { import host; }
;

const pinned_async_manifest_prefix =
    "{\"schema\":2,\"package\":\"do:generic-async-runtime-probe@0.1.0\",\"world\":\"probe\",\"modules\":[\"host.do\"]," ++
    "\"sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"members\":[" ++
    "{\"package\":\"do:generic-async-runtime-probe@0.1.0\",\"member\":\"host.work\",\"effect\":\"async\",\"async\":true,\"future\":false,\"stream\":false,\"resource\":false,\"signature\":\"() -> Future<nil>\"}],\"async_lowerings\":[";

test "schema 2 accepts the pinned unit async capability" {
    const source = pinned_async_manifest_prefix ++
        "{\"capability\":\"component-async-unit-v1\",\"member\":\"host.work\",\"source_signature\":\"() -> Future<nil>\",\"wit_package\":\"do:generic-async-runtime-probe@0.1.0\",\"wit_world\":\"probe\",\"wit_interface\":\"host\",\"wit_member\":\"work\",\"async_import_module\":\"do:generic-async-runtime-probe/host@0.1.0\",\"async_import_name\":\"[async-lower]work\",\"completion\":\"task-return\",\"wit_sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\"}]}";
    var parsed = try manifest.parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 2), parsed.document.schema);
    try std.testing.expectEqual(@as(usize, 1), parsed.document.async_lowerings.len);
    const lowering = parsed.document.async_lowerings[0];
    try std.testing.expectEqualStrings("component-async-unit-v1", lowering.capability);
    try std.testing.expectEqualStrings("[async-lower]work", lowering.async_import_name);
    try std.testing.expectEqualStrings("task-return", lowering.completion);
}

test "schema 1 remains metadata-only" {
    const source =
        "{\"schema\":1,\"package\":\"do:bindgen-probe@0.1.0\",\"world\":\"probe\",\"modules\":[\"api.do\"]," ++
        "\"sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"members\":[]}";
    var parsed = try manifest.parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), parsed.document.schema);
    try std.testing.expectEqual(@as(usize, 0), parsed.document.async_lowerings.len);
}

test "schema 2 rejects an unknown capability" {
    const source = pinned_async_manifest_prefix ++
        "{\"capability\":\"unknown-v1\",\"member\":\"host.work\",\"source_signature\":\"() -> Future<nil>\",\"wit_package\":\"do:generic-async-runtime-probe@0.1.0\",\"wit_world\":\"probe\",\"wit_interface\":\"host\",\"wit_member\":\"work\",\"async_import_module\":\"do:generic-async-runtime-probe/host@0.1.0\",\"async_import_name\":\"[async-lower]work\",\"completion\":\"task-return\",\"wit_sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\"}]}";
    try std.testing.expectError(error.ManifestLoweringMismatch, manifest.parse(std.testing.allocator, source));
}

test "schema 2 rejects a changed completion import" {
    const source = pinned_async_manifest_prefix ++
        "{\"capability\":\"component-async-unit-v1\",\"member\":\"host.work\",\"source_signature\":\"() -> Future<nil>\",\"wit_package\":\"do:generic-async-runtime-probe@0.1.0\",\"wit_world\":\"probe\",\"wit_interface\":\"host\",\"wit_member\":\"work\",\"async_import_module\":\"do:generic-async-runtime-probe/host@0.1.0\",\"async_import_name\":\"[async-lower]work\",\"completion\":\"changed-return\",\"wit_sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\"}]}";
    try std.testing.expectError(error.ManifestLoweringMismatch, manifest.parse(std.testing.allocator, source));
}

test "capability detection rejects payload and non-pinned async models" {
    var payload = try resolve.resolve_source(std.testing.allocator, "package do:generic-async-runtime-probe@0.1.0; interface host { work: async func() -> u32; } world probe { import host; }", "probe");
    defer payload.deinit();
    const payload_capabilities = try async_lowering.detect(std.testing.allocator, payload);
    defer async_lowering.deinit(std.testing.allocator, payload_capabilities);
    try std.testing.expectEqual(@as(usize, 0), payload_capabilities.len);

    var other = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer other.deinit();
    const other_capabilities = try async_lowering.detect(std.testing.allocator, other);
    defer async_lowering.deinit(std.testing.allocator, other_capabilities);
    try std.testing.expectEqual(@as(usize, 0), other_capabilities.len);
}

test "wit emitter emits schema 2 for the pinned unit async binding" {
    var binding = try resolve.resolve_source(std.testing.allocator, pinned_async_source, "probe");
    defer binding.deinit();
    const source = try emit_manifest.render(
        std.testing.allocator,
        binding,
        "do_generic_async_runtime_probe__host__probe.do",
    );
    defer std.testing.allocator.free(source);
    try std.testing.expect(std.mem.startsWith(u8, source, "{\"schema\":2,"));
    try std.testing.expect(std.mem.indexOf(u8, source, "\"async_lowerings\":[{\"capability\":\"component-async-unit-v1\"") != null);
    var parsed = try manifest.parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);
    try manifest.validate_binding(std.testing.allocator, &parsed, binding);
}

test "wit bindgen manifest accepts a valid async member" {
    const source =
        "{\"schema\":1,\"package\":\"do:bindgen-probe@0.1.0\",\"world\":\"probe\",\"modules\":[\"do_bindgen_probe__api__probe.do\"]," ++
        "\"sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"members\":[" ++
        "{\"package\":\"do:bindgen-probe@0.1.0\",\"member\":\"api.send\",\"effect\":\"async\",\"async\":true,\"future\":false,\"stream\":false,\"resource\":true,\"signature\":\"() -> Future<u32 | u8>\"}]}";
    var parsed = try manifest.parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), parsed.document.schema);
    try std.testing.expectEqual(@as(usize, 1), parsed.document.members.len);
    try std.testing.expect(parsed.document.members[0].is_async);
}

test "wit bindgen manifest rejects async effect flag mismatch" {
    const source =
        "{\"schema\":1,\"package\":\"do:bindgen-probe@0.1.0\",\"world\":\"probe\",\"modules\":[\"api.do\"]," ++
        "\"sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"members\":[" ++
        "{\"package\":\"do:bindgen-probe@0.1.0\",\"member\":\"api.send\",\"effect\":\"async\",\"async\":false,\"future\":false,\"stream\":false,\"resource\":false,\"signature\":\"() -> Future<u32 | u8>\"}]}";
    try std.testing.expectError(
        error.ManifestEffectMismatch,
        manifest.parse(std.testing.allocator, source),
    );
}

test "wit bindgen manifest matches the resolved binding model" {
    var binding = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer binding.deinit();
    const source = try emit_manifest.render(std.testing.allocator, binding, "do_bindgen_probe__api__probe.do");
    defer std.testing.allocator.free(source);
    var parsed = try manifest.parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);
    try manifest.validate_binding(std.testing.allocator, &parsed, binding);
}

test "wit bindgen manifest rejects generated module path drift" {
    var binding = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer binding.deinit();
    const source = try emit_manifest.render(std.testing.allocator, binding, "do_bindgen_probe__api__probe.do");
    defer std.testing.allocator.free(source);

    const module_name = "do_bindgen_probe__api__probe.do";
    const module_offset = std.mem.indexOf(u8, source, module_name) orelse return error.TestExpectedEqual;
    const drifted_source = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(drifted_source);
    drifted_source[module_offset] = 'x';

    var parsed = try manifest.parse(std.testing.allocator, drifted_source);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.ManifestBindingMismatch,
        manifest.validate_binding(std.testing.allocator, &parsed, binding),
    );
}

test "wit bindgen manifest records canonical member signatures" {
    var binding = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer binding.deinit();
    const source = try emit_manifest.render(std.testing.allocator, binding, "do_bindgen_probe__api__probe.do");
    defer std.testing.allocator.free(source);

    try std.testing.expect(std.mem.indexOf(
        u8,
        source,
        "\"member\":\"api.completion\",\"effect\":\"sync\",\"async\":false,\"future\":true,\"stream\":false,\"resource\":false,\"signature\":\"() -> Future<u32>\"",
    ) != null);
}

test "wit bindgen manifest rejects member signature drift" {
    var binding = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer binding.deinit();
    const source = try emit_manifest.render(std.testing.allocator, binding, "do_bindgen_probe__api__probe.do");
    defer std.testing.allocator.free(source);

    const signature_marker = "\"signature\":\"() -> Future<u32>\"";
    const signature_offset = std.mem.indexOf(u8, source, signature_marker) orelse return error.TestExpectedEqual;
    const drifted_source = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(drifted_source);
    const payload_offset = signature_offset + std.mem.indexOf(u8, signature_marker, "u32").?;
    drifted_source[payload_offset + 2] = '8';

    var parsed = try manifest.parse(std.testing.allocator, drifted_source);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.ManifestSignatureMismatch,
        manifest.validate_binding(std.testing.allocator, &parsed, binding),
    );
}

test "wit bindgen manifest rejects generated module content drift" {
    var binding = try resolve.resolve_source(std.testing.allocator, probe_source, "probe");
    defer binding.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const output = try std.fs.path.join(std.testing.allocator, &.{ root, "wit" });
    defer std.testing.allocator.free(output);
    try emit_do.emit_all(std.testing.io, std.testing.allocator, binding, output);

    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ output, "manifest.json" });
    defer std.testing.allocator.free(manifest_path);
    const manifest_source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, manifest_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(manifest_source);
    var parsed = try manifest.parse(std.testing.allocator, manifest_source);
    defer parsed.deinit(std.testing.allocator);
    try manifest.validate_generated_modules(std.testing.io, std.testing.allocator, &parsed, manifest_path);

    const module_path = try std.fs.path.join(std.testing.allocator, &.{ output, parsed.document.modules[0] });
    defer std.testing.allocator.free(module_path);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = module_path, .data = "changed generated binding\n" });
    try std.testing.expectError(
        error.ManifestGeneratedModuleMismatch,
        manifest.validate_generated_modules(std.testing.io, std.testing.allocator, &parsed, manifest_path),
    );
}
