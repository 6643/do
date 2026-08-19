# WASI Filesystem Open-At Resource Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify one pinned Component flow where preopen Dir borrows into `descriptor.open-at`, receives owned File in `Result<File, FileError>`, syncs it, and drops File before Dir.

**Architecture:** Extend the resource registry and affine pass with the real `open-at` owned result. Extend the existing fixed preopen Component fixture and Wasmtime `ResourceTable` runner rather than building a generic filesystem path.

**Tech Stack:** Zig, WAT, wasm-tools, Rust, Wasmtime 47 Component Model.

## Global Constraints

- Do exposes no `own<T>` / `borrow<T>`, pointer/reference, or Wasm reference type syntax.
- Only pinned `wasi:filesystem@0.3.0` facts and one fixed source flow are accepted.
- Dir/File remain opaque `@wasi_resource("filesystem/types/descriptor", { .id i64 })` shells.
- Open-at borrows Dir; its Ok File owner must drop before Dir.
- Exclude generic results/lists/resources, arbitrary filesystem methods, async, Component-GC, and ARC migration.
- Shared dirty worktree: do not reset, clean, stage, or commit.

---

### Task 1: Register And Check Open-At Ownership

**Files:**

- Modify: `src/build/resource_abi_registry.json`
- Modify: `src/build/resource_abi_registry.zig`
- Modify: `src/build/sema_resource_ownership.zig`
- Create: `src/build/test/check/360_wasi_open_at_child_ownership.do`
- Create: `src/build/test/err/369_wasi_open_at_file_leaked.do`
- Create: `src/build/test/err/369_wasi_open_at_file_leaked.expect`

**Interfaces:** `descriptor.open-at` accepts `(Dir, i32, text, i32, i32)`, preserves the Dir owner, and yields an owned File through `Result<File, FileError>`.

- [x] **Step 1: Write red tests**

```zig
const open_at = registry.find("wasi:filesystem/types@0.3.0", "descriptor.open-at").?;
try std.testing.expectEqual(.borrow, open_at.params[0].ownership);
try std.testing.expectEqual(.own, open_at.result.ownership);
```

```do
opened Result<File, FileError> = host_open(dir, 0, "probe", 0, 0)
file File = opened
host_sync(file)
host_drop(file)
host_drop(dir)
```

- [x] **Step 2: Verify red**

Run: `cd src && zig test build/resource_abi_registry.zig`

Expected: missing open-at descriptor fails.

- [x] **Step 3: Implement only fixed Result ownership**

Register `borrow<descriptor> -> result<own<descriptor>, error-code>`. Activate File only from the registered fixed open-at result extraction; preserve Dir through open-at; apply existing borrow/drop rules to both owners.

- [x] **Step 4: Verify green**

Run: `cd src && zig test build/sema_resource_ownership.zig && cd .. && ./bin/do check src/build/test/check/360_wasi_open_at_child_ownership.do && ! ./bin/do check src/build/test/err/369_wasi_open_at_file_leaked.do`

### Task 2: Emit The Fixed Open-At Component

**Files:**

- Modify: `src/build/codegen_component_wasi_filesystem_preopen.zig`
- Modify: `examples/p3-runtime/wasi-filesystem-preopen.do`
- Modify: `examples/p3-runtime/wit/wasi-filesystem-preopen.wit`
- Modify: `examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh`

**Interfaces:** Existing `--p3-wasi-filesystem-preopen-component` emits `[method]descriptor.open-at`, sync, and canonical descriptor drops for the only accepted source.

- [x] **Step 1: Write red emitter assertions**

```zig
try std.testing.expect(std.mem.indexOf(u8, wat, "[method]descriptor.open-at") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]descriptor") != null);
```

- [x] **Step 2: Verify red**

Run: `cd src && zig test build/codegen_component_wasi_filesystem_preopen.zig`

Expected: WAT has no open-at import.

- [x] **Step 3: Emit canonical result flow**

```wit
resource descriptor {
  open-at: func(path-flags: u32, path: string, open-flags: u32, descriptor-flags: u32) -> result<own<descriptor>, error-code>;
  sync: func() -> result<_, error-code>;
}
```

Core WAT gets the first Dir, calls open-at with fixed `"probe"` and zero flags, decodes tag/File from the result area, traps on Err, syncs File, drops File, then drops Dir. A changed fixture returns `UnsupportedWasiFilesystemPreopenComponent`.

- [x] **Step 4: Verify assembly**

Run: `bash examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh`

Expected: WIT/Core assemble and altered source is rejected.

### Task 3: Run Two Owners In Wasmtime

**Files:**

- Modify: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_preopen.rs`
- Modify: `examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh`
- Modify: `examples/p3-runtime/README.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/spec_rules.md`

**Interfaces:** Host reports `preopen create=1`, `preopen open=1`, `preopen sync=1`, `preopen drop=2` after table emptiness.

- [x] **Step 1: Write red host assertions**

```bash
for marker in 'preopen create=1' 'preopen open=1' 'preopen sync=1' 'preopen drop=2'; do
  grep -Fq "$marker" <<<"$output"
done
```

- [x] **Step 2: Verify red**

Run: `bash examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh`

Expected: current host lacks open-at and reports one drop.

- [x] **Step 3: Implement typed open-at**

`HostDescriptor::open_at` validates borrowed Dir with `ResourceTable.get`, inserts File, and returns `Ok(Resource<Descriptor>)`. Sync validates File; drop deletes either owner. Assert result `1`, counts `1/1/1/2`, and `table.is_empty()`.

- [x] **Step 4: Verify and document the exact boundary**

Run: `cd src && zig build -Doptimize=ReleaseSmall && cd .. && bash examples/p3-runtime/test_do_resource_probe_lowering.sh && bash examples/p3-runtime/test_rust_resource_probe.sh && bash examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh && bash examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh && ./src/build/test/run_tests.sh && git diff --check`

Document only `Dir -> File -> sync -> two drops`; retain exclusions for generic filesystem and async support.

## Plan Self-Review

- Task 1 proves static registry and lifetime semantics.
- Task 2 proves canonical Component assembly and source rejection.
- Task 3 proves typed `ResourceTable` execution and records only verified scope.
