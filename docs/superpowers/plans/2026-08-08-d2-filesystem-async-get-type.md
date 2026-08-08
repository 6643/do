# D2 Bounded Filesystem Async `descriptor.get-type` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove one real D2 filesystem async scalar method, `descriptor.get-type`, from pinned WIT/Core ABI through a local Rust/Wasmtime runtime matrix, and promote it behind a private descriptor only if every ABI and cleanup gate is green.

**Architecture:** The phase starts with a hand-authored `wasi:filesystem@0.3.0-rc-2025-09-16` probe for `descriptor.get-type: async func() -> result<descriptor-type, error-code>`. The probe freezes the actual async task-return layout before any compiler change. A later isolated adapter may recognize only that descriptor and one straight-line Do source shape; it must reuse the existing async frame/cleanup helpers and must not generalize async calls, borrowed payloads, lists, or resources beyond the receiver descriptor.

**Tech Stack:** Zig 0.16.0, Do compiler, WIT/Core WAT, `wasm-tools` 1.255.0 capability probe plus the pinned legacy async toolchain where required, Rust 1.97.1, Wasmtime 47.0.2, Bash regression harness.

## Global Constraints

- Keep ordinary Do result APIs as `T | E` (or `nil | E`); `Result<T, E>` remains private to WIT/Component ABI probes.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointers, references, or lifetime syntax.
- Admit exactly one method: `wasi:filesystem/types@0.3.0-rc-2025-09-16`, `descriptor.get-type`.
- Use one `Component` and one `Store` per Rust runner; use only a temporary directory supplied through `DO_D2_FILESYSTEM_ROOT`.
- Cancellation ends the guest task/future and releases live Component resources; it never rolls back a filesystem observation or other host side effect.
- Do not change the normal target dispatch until the hand-authored ABI probe and Rust/Wasmtime probe both pass.
- Unknown descriptors, borrowed/list/variant payloads, multiple async children, loops, branches, and arbitrary producer expressions remain fail-closed.
- If a pinned tool rejects the ABI, stop before registry/codegen work and record the exact diagnostic and recovery condition in `doc/pending_blocked.md`.

## File Map

### Probe and design

- Create: `docs/superpowers/specs/2026-08-08-d2-filesystem-async-get-type-design.md`
- Create: `examples/p3-runtime/wit/wasi-filesystem-get-type.wit`
- Create: `examples/p3-runtime/wasi-filesystem-get-type.core.wat`
- Create: `examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh`

### Runtime

- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_get_type.rs`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh`
- Create: `examples/p3-runtime/wit/wasi-filesystem-get-type-cancel.wit`
- Create: `examples/p3-runtime/wasi-filesystem-get-type-cancel.core.wat`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only if the existing Wasmtime async feature set is insufficient for the runner.

### Conditional compiler promotion

- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Create: `src/build/codegen_component_wasi_filesystem_get_type.zig`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/codegen_api.zig` only when a public emitter entry is required by the existing dispatch pattern.
- Modify: `src/build/cli.zig`, `src/build/run.zig`, and `src/main.zig` only if the adapter needs a new explicit opt-in flag; prefer the existing `--p3-async-component` route.
- Create: `src/build/test/compile_ok/459_wasi_filesystem_get_type_component.do`
- Create: `src/build/test/compile_err/459_wasi_filesystem_get_type_unregistered.do`
- Create: `src/build/test/compile_err/459_wasi_filesystem_get_type_unregistered.expect`
- Create: `src/build/test/compile_err/460_wasi_filesystem_get_type_wrong_result.do`
- Create: `src/build/test/compile_err/460_wasi_filesystem_get_type_wrong_result.expect`
- Create: `src/build/test/compile_err/461_wasi_filesystem_get_type_borrowed_payload.do`
- Create: `src/build/test/compile_err/461_wasi_filesystem_get_type_borrowed_payload.expect`

### Status and evidence

- Modify only after the gates: `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`.

## Task 1: Freeze the current baseline and source contract

**Files:**

- Inspect: `doc/start_here.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/host_abi_blockers.md`
- Inspect: `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit`
- Inspect: `src/build/codegen_component_wasi_filesystem_read_directory.zig`, `src/build/p3_async_manifest.zig`
- Modify only for observed drift: the status files listed in the File Map.

**Interfaces:**

- Consumes: the green G6.2 batched producer baseline and current D2 local-host matrix.
- Produces: a reproducible baseline and an exact source signature for the candidate method.

- [x] **Step 1: Run the baseline commands.**

```bash
cd src && zig test main.zig
cd ..
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Record the observed counts without replacing newer checked-in evidence with an older number. Any failure is a baseline blocker and must be diagnosed before this plan proceeds.

- [x] **Step 2: Confirm the pinned WIT source fact.**

```bash
rg -n -A4 -B3 'get-type: async func' \
  src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit
```

The source must contain `get-type: async func() -> result<descriptor-type, error-code>;`. Do not substitute the older synchronous `wasi:filesystem@0.3.0` descriptor API.

- [x] **Step 3: Write the design contract.**

`docs/superpowers/specs/2026-08-08-d2-filesystem-async-get-type-design.md` must state the exact package/version, world name, method signature, receiver ownership, task-return payload representation, error tags, pending/ready/error/cancel behavior, and the rejection boundary. It must explicitly say that no compiler registry entry exists until Tasks 2 and 3 pass.

## Task 2: Build and validate the hand-authored canonical ABI probe

**Files:**

- Create: `examples/p3-runtime/wit/wasi-filesystem-get-type.wit`
- Create: `examples/p3-runtime/wasi-filesystem-get-type.core.wat`
- Create: `examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh`

**Interfaces:**

- Consumes: the pinned filesystem WIT declaration from Task 1.
- Produces: a validated Component fixture and a machine-readable record of the exact async imports, task-return parameters, result layout, and drop names.

- [x] **Step 1: Write the minimal WIT world.**

Use this shape; do not add `stream`, `future` payloads, or a second method:

```wit
package wasi:filesystem@0.3.0-rc-2025-09-16;

interface types {
  enum descriptor-type { unknown, directory, regular-file }
  enum error-code { io, no-entry }
  resource descriptor {
    get-type: async func() -> result<descriptor-type, error-code>;
  }
}

interface probe {
  use types.{descriptor, descriptor-type, error-code};
  run: async func(directory: own<descriptor>) -> result<descriptor-type, error-code>;
}

world get-type-probe {
  import types;
  export probe;
}
```

The world is a private probe. `own<descriptor>` is WIT syntax only and must not be added to Do grammar or ordinary source declarations.

- [x] **Step 2: Write the Core module from measured canonical names.**

The module must expose one async root export, import the descriptor resource drop, import the method's async-lower/task-return operations, and include one result buffer. Keep the result as the measured scalar enum/error representation; do not guess offsets from the synchronous `descriptor.sync` ABI. Add stable comments for `get-type-call`, `get-type-ready`, `get-type-pending`, `get-type-error`, `get-type-cancel`, and `descriptor-drop`.

- [x] **Step 3: Run the pinned ABI gate.**

```bash
bash examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh
```

The script must verify the exact `wasm-tools` version and SHA-256, parse the WIT, assemble/embed/new/validate the Component, and print the measured ABI record. It must fail closed for a changed package hash, changed method signature, a missing async import, a missing resource drop, or a result layout different from the recorded probe.

- [x] **Step 4: Stop on a no-go.**

If `wasm-tools` rejects the receiver or async result, do not create the registry entry, emitter, or positive fixture. Append the command, complete diagnostic, pinned versions, and recovery condition to `doc/pending_blocked.md`; leave `descriptor.get-type` blocked as an ABI capability issue.

## Task 3: Run the real local Rust/Wasmtime matrix

**Files:**

- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_get_type.rs`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh`

**Interfaces:**

- Consumes: the Component produced by Task 2 and the existing `run_concurrent`/Accessor drive-loop conventions.
- Produces: deterministic local filesystem evidence for descriptor receiver ownership, result delivery, cancellation, and final table cleanup.

- [x] **Step 1: Create isolated temporary fixtures.**

The shell script must create a temporary root with one regular file and one subdirectory, export `DO_D2_FILESYSTEM_ROOT`, and remove it with a trap. The runner must reject a missing environment variable and must never read the repository tree or `/`.

- [x] **Step 2: Implement the host descriptor state.**

The host `Descriptor` state carries a `PathBuf` and a drop counter. `get-type` accepts only a live descriptor, maps `metadata().is_dir()` to `directory` or `regular-file`, maps a missing path to `no-entry`, and records one host call. Descriptor destruction removes the handle from the `ResourceTable` exactly once.

- [x] **Step 3: Implement five drive modes.**

The binary must accept `ready-directory`, `ready-regular`, `pending`, `error`, and `cancel`. `pending` must require one host wake before completion. `cancel` uses the test-only control Component described in the design; it requests async `[subtask-cancel]` before completion, waits for the root callback, releases the task/descriptor exactly once, and never reports a second completion. All modes must print `table-empty=true` before exit.

- [x] **Step 4: Run the focused runtime gate.**

```bash
bash examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh
```

Require exact markers for result tag, host-call count, poll/wake count, completion or cancellation count, descriptor drop count, and empty resource table in every mode. The script also parses and validates the test-only cancel Component and runs `rustfmt --check` for the runner.

## Task 4: Promote only the measured private compiler slice

**Files:**

- Modify: `src/build/p3_async_manifest.zig`, `src/build/p3_async_registry.json`
- Create: `src/build/codegen_component_wasi_filesystem_get_type.zig`
- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/test/compile_ok/459_wasi_filesystem_get_type_component.do`
- Create: `src/build/test/compile_err/459_wasi_filesystem_get_type_unregistered.do`
- Create: `src/build/test/compile_err/459_wasi_filesystem_get_type_unregistered.expect`
- Create: `src/build/test/compile_err/460_wasi_filesystem_get_type_wrong_result.do`
- Create: `src/build/test/compile_err/460_wasi_filesystem_get_type_wrong_result.expect`
- Create: `src/build/test/compile_err/461_wasi_filesystem_get_type_borrowed_payload.do`
- Create: `src/build/test/compile_err/461_wasi_filesystem_get_type_borrowed_payload.expect`

**Interfaces:**

- Consumes: the measured descriptor/package hash, canonical import set, result layout, and cleanup order from Tasks 2-3.
- Produces: one descriptor-driven lowering under the existing `--p3-async-component` profile; ordinary `do build` and all existing targets remain unchanged.

- [x] **Step 1: Add manifest admission tests first.**

Register exactly `wasi:filesystem/types@0.3.0-rc-2025-09-16` / `descriptor.get-type`, its WIT hash, the measured receiver/result metadata, and the exact canonical async import names. Add tests that reject package/version drift, wrong enum/error result, missing resource metadata, and unknown locators before WAT emission.

- [x] **Step 2: Add the isolated target and minimal source shape.**

Recognize only a private Do fixture equivalent to:

```do
get_type = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-type", (Dir) -> DescriptorType | FileError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
DescriptorType error = Unknown | Directory | RegularFile
FileError error = Io | NoEntry

run(directory Dir) -> nil {
    pending Future<DescriptorType | FileError> = get_type(directory)
    result DescriptorType | FileError = @await(pending)
}
start() {}
```

The adapter must use the Task 2 frame offsets and Task 3 cleanup order. It must reject a second await, a second child, branches/loops, payload resources, `borrow<T>`, `list<T>`, and arbitrary call expressions.

- [x] **Step 3: Add positive and negative compiler gates.**

```bash
./bin/do build src/build/test/compile_ok/459_wasi_filesystem_get_type_component.do \
  --p3-async-component --p3-wit-output /tmp/d2-filesystem-get-type.wit \
  -o /tmp/d2-filesystem-get-type.wat
for fixture in 459_wasi_filesystem_get_type_unregistered \
  460_wasi_filesystem_get_type_wrong_result \
  461_wasi_filesystem_get_type_borrowed_payload; do
  if ./bin/do build "src/build/test/compile_err/${fixture}.do" \
    --p3-async-component -o "/tmp/${fixture}.wat"; then
    echo "unexpected success: ${fixture}"
    exit 1
  fi
done
```

The positive WAT must contain only the registered method, task-return, result, and descriptor-drop imports. Every negative fixture must fail before WAT output with its stable diagnostic.

- [x] **Step 4: Run the compiler-generated Component/Rust/Wasmtime gate.**

Extend `examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh` to build the Do fixture, assemble it with the pinned tools, and run the hand-written five-mode matrix plus the generated ready-directory, ready-regular, pending, and error modes against the same Rust runner. Do not mark the registry entry complete until generated and hand-authored Components produce the same ABI and cleanup counts.

## Task 5: Synchronize status and close the phase

**Files:**

- Modify: `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`

**Interfaces:**

- Consumes: the complete probe, runtime, compiler, and regression evidence, or the explicit no-go from Task 2.
- Produces: a truthful D2 checkpoint that does not imply general filesystem async, generic producer lowering, or public ownership syntax.

- [x] **Step 1: Run focused and full verification.**

```bash
cd src && zig test main.zig
cd ..
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Also rerun the existing G6.2 C-min/dynamic/batched producer scripts and all current D2 local file/dir/CLI/socket scripts. Any unrelated regression blocks closeout.

- [x] **Step 2: Record only observed status.**

If Tasks 2-4 pass, mark only the private `descriptor.get-type` slice as verified and keep `read/write/stat/open-at` generalization, borrowed async payloads, arbitrary producer expressions, external HTTP, independent guest tasks, and public ownership syntax pending. If Task 2 or Task 3 fails, record the exact blocker and leave compiler files and registry unchanged.

- [x] **Step 3: Verify plan boundaries.**

```bash
rg -n 'generic|own<T>|borrow<T>|ref<T>|external HTTP|independent guest' \
  docs/superpowers/plans/2026-08-08-d2-filesystem-async-get-type.md
git diff --check
```

The plan is complete only when every step is either green or has a recorded no-go with evidence and recovery condition; a green hand-authored probe alone is not a compiler promotion.

## Explicitly Deferred Follow-up

1. G6.2 next producer/resource shape: requires a separate design, pinned probe, manifest/sema admission, positive/negative fixtures, and Component/Rust/Wasmtime cleanup matrix.
2. General filesystem async (`read`, `write`, `stat`, `open-at`, directory mutation, or stream variants): each method needs its own measured ABI and must not be inferred from `get-type`.
3. Borrowed async payloads and public `own<T>`/`borrow<T>`/`ref<T>` syntax: remain blocked by the pinned Component/toolchain and ownership/lifetime boundary.
4. Arbitrary producer expressions, unrestricted async-call composition, independent guest child tasks, and external HTTP: require new architecture/design gates and are not part of this phase.
