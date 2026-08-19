# Host Export Manifest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a general-purpose Core Wasm host-export build mode that exposes root-module public functions and writes a machine-readable ABI manifest, without compiler knowledge of any UI library.

**Architecture:** `do build --host-export` compiles a root module without requiring or invoking `start`. It exports concrete, non-private root functions using the already-emitted function symbols, and `--host-manifest <path>` writes their source names, WAT export names, source signatures, and flattened Core Wasm ABI signature. UI and future hosts consume this generic contract; no `ui_*` name is inspected by the compiler.

**Tech Stack:** Zig 0.16, existing `do build` CLI, WAT output, JSON sidecar manifest, repository regression runner.

## Global Constraints

- Preserve ordinary `do build`: it still requires `start` and emits only `_start`.
- `--host-export` must not inspect UI library calls, strings, or host-specific names.
- Only direct root-module, concrete, non-private functions enter the first manifest; generic templates, imported functions, and private `.name` declarations do not have a standalone host ABI.
- The first manifest describes the compiler's existing flattened Core Wasm ABI. It does not claim a canonical JS ABI or ownership protocol for `text`, lists, structs, tuples, or unions.
- Reuse `function_signature_symbol_name` and the actual post-mangling emitted symbol for overload stability.

---

### Task 1: Define CLI and host-export fixtures

**Files:**
- Modify: `src/build/cli.zig`
- Modify: `src/build/test/run_tests.sh`
- Create: `src/build/test/compile_ok/340_host_export_manifest.do`
- Create: `src/build/test/compile_ok/340_host_export_manifest.host_export.expect`
- Create: `src/build/test/compile_ok/340_host_export_manifest.host_manifest.expect`

**Interfaces:**
- Consumes: `do build <input> [-o <wat>]`.
- Produces: `Args.host_export: bool` and `Args.host_manifest_path: ?[]const u8`; `--host-manifest` is rejected unless `--host-export` is present.

- [ ] **Step 1: Write CLI unit tests before parsing changes.**

```zig
test "parse_build accepts host export and manifest" {
    const args = [_][]const u8{ "build", "app.do", "--host-export", "--host-manifest", "app.host.json" };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.host_export);
    try std.testing.expectEqualStrings("app.host.json", parsed.host_manifest_path.?);
}
```

- [ ] **Step 2: Run the focused Zig test and verify it fails because the fields and flags do not exist.**

Run: `cd src && zig build test --summary none`

Expected: compilation failure naming the missing CLI contract.

- [ ] **Step 3: Implement the minimal parser contract.**

```zig
if (std.mem.eql(u8, args[i], "--host-export")) {
    host_export = true;
    continue;
}
if (std.mem.eql(u8, args[i], "--host-manifest")) {
    if (i + 1 >= args.len) return error.MissingHostManifestPath;
    i += 1;
    host_manifest_path = args[i];
    continue;
}
if (host_manifest_path != null and !host_export) return error.HostManifestRequiresHostExport;
```

- [ ] **Step 4: Add the no-`start` fixture and runner support.**

The fixture declares a public scalar callback, an overloaded public callback, and a private helper. The runner invokes the extra host-export build only when `.host_export.expect` exists, then checks the WAT and JSON sidecar against the corresponding expectation files.

- [ ] **Step 5: Run the focused fixture and CLI tests.**

Run: `./src/build/test/run_tests.sh`

Expected: the new fixture fails until Tasks 2 and 3; existing CLI cases remain green.

### Task 2: Emit generic host exports from existing function declarations

**Files:**
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/codegen_emit_expression.zig`
- Modify: `src/build/run.zig`
- Test: `src/build/test/compile_ok/340_host_export_manifest.host_export.expect`

**Interfaces:**
- Consumes: `EmitOptions.host_export`, collected/mangled `FuncDecl` values, and `FuncDecl.source_name`.
- Produces: WAT `(export "<stable-name>" (func $<emitted-symbol>))` entries for host-visible functions; host mode accepts programs without `start`.

- [ ] **Step 1: Extend `EmitOptions` and write a codegen unit test for root public selection.**

The test must prove that a concrete root `sum` is selected while `.cache`, an imported declaration, and a generic template are excluded.

- [ ] **Step 2: Run the focused test and verify it fails because no host selection helper exists.**

Run: `cd src && zig build test --summary none`

Expected: failure identifying the absent selection helper.

- [ ] **Step 3: Implement root-function selection after overload mangling.**

Selection requires `func.tokens == ctx.entry_tokens`, `!func.is_generic_template`, and a source name that does not begin with `.`. The WAT export name is `func.name`, so overloaded declarations use the existing signature-mangled symbol and non-overloaded declarations retain their source name.

- [ ] **Step 4: Emit exports after `emit_user_funcs`.**

```zig
try emit_user_funcs(allocator, ctx, &out);
if (options.host_export) try emit_host_exports(allocator, ctx, &out);
if (!options.host_export) try emit_start_func(allocator, tokens, ctx, &out);
```

`run.compile_program_wat_parts` must skip `entry.validate_start` only in host-export mode.

- [ ] **Step 5: Run the new fixture and full compiler regression suite.**

Run: `./src/build/test/run_tests.sh`

Expected: host WAT contains exports for public callbacks only; normal build behavior and all existing regressions remain unchanged.

### Task 3: Write the Core Wasm ABI manifest

**Files:**
- Create: `src/build/host_export_manifest.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_api.zig`
- Test: `src/build/test/compile_ok/340_host_export_manifest.host_manifest.expect`

**Interfaces:**
- Consumes: selected `FuncDecl` values after overload mangling.
- Produces: UTF-8 JSON written to the explicit `--host-manifest` path with schema version, `abi: "core-wasm-v1"`, and one ordered export record per WAT export.

- [ ] **Step 1: Write a serializer unit test before implementation.**

```zig
try std.testing.expectEqualStrings(
    "{\"version\":1,\"abi\":\"core-wasm-v1\",...}",
    try emit_manifest(allocator, selected),
);
```

The expected record verifies source name, WAT export name, source parameter/result types, and flattened Wasm value types.

- [ ] **Step 2: Run the focused test and verify it fails because the serializer does not exist.**

Run: `cd src && zig build test --summary none`

Expected: missing import or symbol failure.

- [ ] **Step 3: Implement a pure serializer and one shared selection API.**

Use the same selected function slice for WAT export emission and JSON serialization. Serialize only facts already determined by codegen; do not infer a JS value representation. JSON strings must use Zig's standard JSON escaping facilities.

- [ ] **Step 4: Write the sidecar only after successful WAT compilation.**

`run.run` calls the manifest serializer after `compile_program_wat` succeeds, then reports I/O errors through the existing diagnostic path. A normal build must never create a manifest.

- [ ] **Step 5: Run fixture and type-level checks.**

Run: `./src/build/test/run_tests.sh`

Expected: the fixture confirms deterministic manifest ordering, no private/imported/generic records, and matching WAT/manifest export names.

### Task 4: Synchronize the host ABI documentation and verify end to end

**Files:**
- Modify: `doc/ui.md`
- Modify: `doc/ui.do`
- Modify: `examples/ui-signal/ui.do`
- Modify: `README.md`

**Interfaces:**
- Consumes: implemented host-export CLI and manifest schema.
- Produces: documentation that identifies the generic host ABI as the prerequisite for future UI integration, without claiming a completed JS/Wasm value bridge.

- [ ] **Step 1: Update the documented build sequence.**

```text
do build app.do --host-export --host-manifest app.host.json -o app.wat
WebAssembly.instantiate(...) -> runtime.attach(exports, manifest) -> mount(...)
```

- [ ] **Step 2: State the intentionally unsupported surface.**

Document that the first manifest reports Core Wasm ABI only and does not yet supply canonical `text`, list, struct, tuple, union, ownership, or JS callback wrappers.

- [ ] **Step 3: Run all required verification.**

Run:

```bash
./src/build/test/run_tests.sh
bun run verify
git diff --check
```

Workdir for the Bun command: `examples/ui-signal`.

Expected: compiler suite passes, UI reference verification passes, and no whitespace errors exist.

- [ ] **Step 4: Inspect the actual artifacts.**

Build the host-export fixture to `/tmp/host-export.wat` and `/tmp/host-export.json`; verify every JSON export has the same name in the WAT and that no private helper appears in either artifact.
