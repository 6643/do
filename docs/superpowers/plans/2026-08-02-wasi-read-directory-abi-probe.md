# WASI Read-Directory ABI Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Freeze the pinned `descriptor.read-directory` Core ABI and its non-scalar stream element without claiming that G6.2 lowering is implemented.

**Architecture:** Generate a legacy async callback dummy Core module directly from the vendored WASI filesystem WIT with `wasm-tools 1.254.0`. Assert the descriptor method, stream index `0`, future index `1`, canonical function signatures, and the `directory-entry` record in the embedded component type. Keep this as an ABI evidence probe; the compiler registry, source syntax, and generic async lowering remain unchanged.

**Tech Stack:** Vendored WIT, `wasm-tools 1.254.0`, shell assertions, repository blocker documentation.

## Global Constraints

- Keep `own<T>`, `borrow<T>`, `ref<T>`, pointers, and references out of Do source syntax.
- Do not register `descriptor.read-directory` as compiler-lowerable.
- Do not add a generic stream/future/resource lowering path in this probe.
- Preserve the existing G6.2 blocked boundary until generic record streams and completion cleanup are implemented.
- Work in the existing dirty checkout; do not reset, clean, commit, or push.

---

### Task 1: Add The Pinned ABI Probe

**Files:**
- Create: `examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh`

**Interfaces:**
- Consumes: `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16` and world `wasi:filesystem/imports`.
- Produces: a temporary legacy async Core WAT and assertions for the read-directory ABI.

- [x] **Step 1: Generate the dummy Core surface.**

Run:

```bash
wasm-tools component embed \
  src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16 \
  --world wasi:filesystem/imports \
  --dummy-names legacy --async-callback \
  --features cm-async,cm-more-async-builtins -t -o "$tmp_dir/filesystem.wat"
```

Require `wasm-tools 1.254.0` before generation.

- [x] **Step 2: Assert the method, stream, and future imports.**

Require these exact module/name pairs:

```text
wasi:filesystem/types@0.3.0-rc-2025-09-16 [async-lower][method]descriptor.read-directory
wasi:filesystem/types@0.3.0-rc-2025-09-16 [stream-new-0][method]descriptor.read-directory
wasi:filesystem/types@0.3.0-rc-2025-09-16 [async-lower][stream-read-0][method]descriptor.read-directory
wasi:filesystem/types@0.3.0-rc-2025-09-16 [future-new-1][method]descriptor.read-directory
wasi:filesystem/types@0.3.0-rc-2025-09-16 [async-lower][future-read-1][method]descriptor.read-directory
wasi:filesystem/types@0.3.0-rc-2025-09-16 [future-drop-readable-1][method]descriptor.read-directory
```

Use the generated type declarations to require `(i32, i32) -> i32` for the
method and future-read callbacks, `() -> i64` for each indexed `new`, and
`(i32, i32, i32) -> i32` for stream-read. Require readable and writable drop
imports for both indexes so cleanup is not inferred from a single endpoint.

- [x] **Step 3: Assert the non-scalar stream element.**

Require the embedded component type to contain `directory-entry` with a
`descriptor-type` field and a `string` `name` field. The probe must fail if the
generated WIT no longer describes a record stream or if `read-directory` is
silently changed to `stream<u8>`.

### Task 2: Record The Stop Point

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/pending_blocked.md`

- [x] **Step 1: Replace the stale blocker wording.**

State that the pinned async method and indexed stream/future ABI are now
observed, while G6.2 remains blocked by generic `directory-entry` record-stream
layout, async frame/result handling, resource ownership, and exactly-once
completion/stream cleanup.

- [x] **Step 2: Preserve the compiler boundary.**

Keep `descriptor.read-directory` known-but-unsupported in the WASI registry and
keep the ordinary compiler diagnostic unchanged.

### Task 3: Verification Closure

- [x] **Step 1:** Run the ABI probe and `bash examples/p3-runtime/test.sh`.
- [x] **Step 2:** Run `./src/build/test/run_tests.sh` and `git diff --check`.
- [x] **Step 3:** Record the exact command and result in the blocker section.

## Phase Exit Criteria

- The exact pinned method, stream index, future index, and callback signatures
  are reproducibly asserted.
- The `directory-entry` record shape is evidenced from the embedded component
  type.
- No source syntax, registry admission, or generic lowering support is added.
- G6.2 remains explicitly blocked with a more precise recovery condition.
