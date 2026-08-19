# WASI Filesystem Preopen Resource Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove one real pinned WASI Component route: get a preopen descriptor, borrow it for `sync`, and drop it canonically.

**Architecture:** The resource ABI registry is the sole ownership source. A narrow opt-in target validates one source fixture and emits Core WAT plus a WIT sidecar. A Wasmtime 47 host runner stores descriptors in `ResourceTable`, so runtime evidence distinguishes borrow from ownership transfer.

**Tech Stack:** Zig, WAT, wasm-tools, Rust, Wasmtime 47 Component Model.

## Global Constraints

- No public `own<T>` / `borrow<T>`, pointer/reference, or Wasm reference type syntax.
- Use only pinned `wasi:filesystem/preopens@0.3.0` and `wasi:filesystem/types@0.3.0` facts.
- Source descriptor is opaque: `@wasi_resource("filesystem/types/descriptor", { .id i64 })`.
- `get-directories` owns the descriptor, `sync` borrows it, and canonical descriptor drop consumes it.
- No generic resource lists, arbitrary filesystem calls, HTTP, async, GC, or ARC migration.
- Shared dirty worktree: do not reset, clean, stage, or commit.

---

### Task 1: Register Exact ABI Ownership

**Files:**

- Modify: `src/build/resource_abi_registry.json`
- Modify: `src/build/resource_abi_registry.zig`
- Modify: `src/build/sema_imports.zig`
- Create: `src/build/test/check/358_wasi_preopen_descriptor_ownership.do`

**Interfaces:** `Registry.find(locator, member)` returns descriptors for `get-directories`, `descriptor.sync`, and `descriptor.drop`.

- [x] **Step 1: Add a failing registry assertion and valid source fixture**

```zig
try std.testing.expectEqual(.own, registry.find("wasi:filesystem/preopens@0.3.0", "get-directories").?.result.ownership);
try std.testing.expectEqual(.borrow, registry.find("wasi:filesystem/types@0.3.0", "descriptor.sync").?.params[0].ownership);
```

```do
.host_preopens = @host("wasi:filesystem/preopens@0.3.0", "get-directories", () -> [Tuple<Dir, text>])
.host_sync = @host("wasi:filesystem/types@0.3.0", "descriptor.sync", (Dir) -> Result<nil, FileError>)
.host_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (Dir) -> nil)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
FileError = @error { .io }
start() { dirs [Tuple<Dir, text>] = host_preopens(); dir Dir = @get(dirs, 0, 0); host_sync(dir); host_drop(dir) }
```

- [x] **Step 2: Verify red**

Run: `cd src && zig test build/resource_abi_registry.zig`

Expected: failure because no filesystem resource descriptor is loaded.

- [x] **Step 3: Add the three exact entries**

```json
{"locator":"wasi:filesystem/preopens@0.3.0","member":"get-directories","resource":"descriptor","params":[],"result":{"type":"list<tuple<descriptor,string>>","ownership":"own"},"resource_drop":false}
{"locator":"wasi:filesystem/types@0.3.0","member":"descriptor.sync","resource":"descriptor","params":[{"type":"descriptor","ownership":"borrow"}],"result":{"type":"result<_,error-code>","ownership":"none"},"resource_drop":false}
{"locator":"wasi:filesystem/types@0.3.0","member":"descriptor.drop","resource":"descriptor","params":[{"type":"descriptor","ownership":"own"}],"result":{"type":"nil","ownership":"none"},"resource_drop":true}
```

Keep registry validation strict. Add only the nested own-result shape required by preopens and require the exact public Do signatures above.

- [x] **Step 4: Verify green**

Run: `cd src && zig test build/resource_abi_registry.zig && cd .. && ./bin/do check src/build/test/check/358_wasi_preopen_descriptor_ownership.do`

### Task 2: Affine Ownership For First Preopen

**Files:**

- Modify: `src/build/sema_resource_ownership.zig`
- Create: `src/build/test/check/359_wasi_preopen_sync_borrow.do`
- Create: `src/build/test/err/367_wasi_preopen_after_drop.do`
- Create: `src/build/test/err/367_wasi_preopen_after_drop.expect`
- Create: `src/build/test/err/368_wasi_preopen_leaked.do`
- Create: `src/build/test/err/368_wasi_preopen_leaked.expect`

**Interfaces:** The exact `@get(dirs, 0, 0)` extraction activates an owned `Dir`; known sync preserves it and known drop consumes it.

- [x] **Step 1: Add red source fixtures**

```do
start() {
    dirs [Tuple<Dir, text>] = host_preopens()
    dir Dir = @get(dirs, 0, 0)
    host_sync(dir)
    host_sync(dir)
    host_drop(dir)
}
```

The check fixture must pass. A `host_sync(dir)` after `host_drop(dir)` expects `ResourceAlreadyConsumed`; omitting drop expects `ResourceDropped`.

- [x] **Step 2: Verify red**

Run: `./bin/do check src/build/test/err/368_wasi_preopen_leaked.do`

Expected: it passes until nested resource ownership is tracked.

- [x] **Step 3: Implement only the pinned extraction**

Recognize the assignment only when `dirs` was initialized by registered `get-directories` and its RHS is exactly `@get(dirs, 0, 0)`. Do not generalize arbitrary list/tuple ownership.

- [x] **Step 4: Verify green**

Run: `./bin/do check src/build/test/check/359_wasi_preopen_sync_borrow.do && ./bin/do check src/build/test/err/367_wasi_preopen_after_drop.do && ./bin/do check src/build/test/err/368_wasi_preopen_leaked.do`

### Task 3: Emit And Assemble The Component

**Files:**

- Create: `src/build/codegen_component_wasi_filesystem_preopen.zig`
- Modify: `src/build/codegen_api.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/cli.zig`
- Modify: `src/main.zig`
- Create: `examples/p3-runtime/wasi-filesystem-preopen.do`
- Create: `examples/p3-runtime/wit/wasi-filesystem-preopen.wit`

**Interfaces:** `do build source --p3-wasi-filesystem-preopen-component --p3-wit-output output.wit -o output.wat` produces the only accepted Component route.

- [x] **Step 1: Add failing emitter and CLI tests**

```zig
try std.testing.expect(std.mem.indexOf(u8, wat, "get-directories") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "descriptor.sync") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]descriptor") != null);
```

Test that the flag conflicts with `--component-core`, `--host-export`, `--p3-wait-for-component`, and `--p3-resource-probe-component`.

- [x] **Step 2: Verify red**

Run: `cd src && zig test build/codegen_component_wasi_filesystem_preopen.zig`

Expected: failure because no emitter exists.

- [x] **Step 3: Implement fixed source validation and WAT/WIT**

```wit
package do:wasi-filesystem-preopen-probe@0.1.0;
world preopen-probe {
  import wasi:filesystem/preopens@0.3.0;
  import wasi:filesystem/types@0.3.0;
  export run: func() -> u32;
}
```

Emit `run` to select the first descriptor, call sync with borrow semantics, check result tag zero, invoke `[resource-drop]descriptor` once, and return `1`. Retain `cabi_realloc`, `cabi_post_run`, and `_initialize`; return `UnsupportedWasiFilesystemPreopenComponent` for every differing source flow.

- [x] **Step 4: Verify assembly**

Run: `cd src && zig test build/codegen_component_wasi_filesystem_preopen.zig && zig test build/cli.zig && cd .. && ./bin/do build examples/p3-runtime/wasi-filesystem-preopen.do --p3-wasi-filesystem-preopen-component --p3-wit-output /tmp/preopen.wit -o /tmp/preopen.wat && wasm-tools parse /tmp/preopen.wat -o /tmp/preopen.wasm && wasm-tools component embed /tmp/preopen.wit --world preopen-probe -o /tmp/preopen.embedded.wasm /tmp/preopen.wasm && wasm-tools component new -o /tmp/preopen.component.wasm /tmp/preopen.embedded.wasm && wasm-tools validate /tmp/preopen.component.wasm`

### Task 4: Execute Typed Resource Host

**Files:**

- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_preopen.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh`

**Interfaces:** Host output is `preopen create=1`, `preopen sync=1`, and `preopen drop=1` after `ResourceTable` emptiness is verified.

- [x] **Step 1: Write red scripts**

```bash
output=$(cargo run --quiet --bin do-p3-wasi-filesystem-preopen-host-runner -- "$tmp_dir/preopen.component.wasm")
grep -Fq 'preopen create=1' <<<"$output"
grep -Fq 'preopen sync=1' <<<"$output"
grep -Fq 'preopen drop=1' <<<"$output"
```

The lowering script must mutate the accepted source and require `UnsupportedWasiFilesystemPreopenComponent`.

- [x] **Step 2: Verify red**

Run: `bash examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh`

Expected: failure because the runner and target do not exist.

- [x] **Step 3: Implement `ResourceTable` bindings**

Register `descriptor` in the `wasi:filesystem/types@0.3.0` linker instance. Preopens creates one table value; sync reads it without deletion; the destructor deletes it. Assert `run == 1`, all counters equal one, and `table.is_empty()`.

- [x] **Step 4: Verify green**

Run: `bash examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh && bash examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh`

### Task 5: Document And Regress

**Files:**

- Modify: `examples/p3-runtime/README.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/spec_rules.md`

- [x] **Step 1: Make emitted ownership facts executable**

Require scripts to find `get-directories: func() -> list<tuple<own<descriptor>, string>>`, `sync: func() -> result<_, error-code>`, and `[resource-drop]descriptor`.

- [x] **Step 2: Document only the verified scope**

Record the pinned packages, opaque source handle, fixed path, and exclusions. Do not claim generic Component, generic list, or broader filesystem support.

- [x] **Step 3: Run final verification**

Run: `cd src && zig build -Doptimize=ReleaseSmall && cd .. && bash examples/p3-runtime/test_do_resource_probe_lowering.sh && bash examples/p3-runtime/test_rust_resource_probe.sh && bash examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh && bash examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh && ./src/build/test/run_tests.sh && git diff --check`

## Plan Self-Review

- Tasks cover pinned registry facts, affine sema, Component assembly, typed host execution, and evidence-bounded documentation.
- No task broadens the work into generic resources, filesystem operations, or async support.
