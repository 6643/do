# D2 `descriptor.set-size` Implementation Plan

> **For agentic workers:** execute one checked task at a time. Keep the
> checkboxes current and stop on a pinned ABI or ownership no-go.

**Goal:** Add one private opt-in `descriptor.set-size` Component async slice
with a pinned ABI probe, exact Do admission, generated Component validation,
and Rust/Wasmtime mutation/cancellation cleanup coverage.

**Architecture:** Keep `descriptor.set-size` as an independent registry row,
sema predicate, planner/emitter module, and fixed Core/WIT templates. Reuse
only stable error-code/resource helpers; do not widen `descriptor.sync`, add a
generic filesystem lowering path, or expose ownership syntax.

**Toolchain:** Zig compiler and unit tests, Do fixtures, WIT/Core WAT,
`wasm-tools 1.255.0`, Rust `1.97.1`, Wasmtime `47.0.2`, and the existing
`src/build/test/run_tests.sh` harness.

## Global Constraints

- Pin upstream filesystem WIT SHA-256
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`.
- Pin `wasm-tools 1.255.0` SHA-256
  `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
- Admit only `(File, u64) -> nil | SetSizeError` with one direct `@await` and
  a synchronous empty `start`.
- Keep the target under `--p3-async-component`; default emission remains
  fail-closed with `AsyncLoweringUnavailable`.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference,
  lifetime, or generic filesystem async lowering.
- Cancellation releases guest-owned state only and never rolls back an issued
  host file-size mutation.

---

### Task 1: Pin the set-size ABI probe

**Files:**

- Create: `examples/p3-runtime/wit/wasi-filesystem-set-size.wit`
- Create: `examples/p3-runtime/wit/wasi-filesystem-set-size-cancel.wit`
- Create: `examples/p3-runtime/test_d2_wasi_filesystem_set_size_abi.sh`
- Create: `examples/p3-runtime/wasi-filesystem-set-size.core.wat`
- Create: `examples/p3-runtime/wasi-filesystem-set-size-cancel.core.wat`

**Interfaces:** Consume the pinned filesystem source and emit the measured
async method import, result-area, task-return, frame offsets, mirror hashes,
and validated regular/cancel Core templates.

- [x] Write the WIT mirrors with the complete `error-code` order, `filesize =
  u64`, only `descriptor.set-size`, and separate regular/cancel probe worlds.
- [x] Write the ABI script with strict tool/source/mirror hash checks and
  assertions for one `descriptor.set-size` method, the async callback imports,
  the unit/error result, and no unrelated filesystem method.
- [x] Run the script before Core templates exist. Preserve the expected
  failure as the red probe boundary.
- [x] Generate and inspect the Core templates with current
  `wasm-tools component embed --dummy-names legacy --async-callback` and
  `cm-async,cm-more-async-builtins`; the measured flat signature is
  `(i32,i64,i32)->i32`.
- [x] Re-run the ABI gate. Parse, embed, assemble, validate, and print both
  Components; require exactly one `descriptor.set-size` method and the
  measured result/task-return layout.

**Verification:**

```bash
bash examples/p3-runtime/test_d2_wasi_filesystem_set_size_abi.sh
```

Do not touch compiler registry/codegen until this gate is green. The five probe
files are now an independent green boundary; commit them before Task 2.

### Task 2: Add manifest, planner, and admission tests

**Files:**

- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/test/compile_ok/552_wasi_filesystem_set_size_component.do`
- Create: `src/build/test/compile_ok/552_wasi_filesystem_set_size_component.expect`
- Create: `src/build/test/compile_err/553` through `563` set-size fixtures and
  matching `.expect` files

- [x] Add the positive fixture first and run the focused test before the
  registry row. It must be rejected as unsupported by the opt-in planner.
- [x] Add negative fixtures for unregistered/wrong-version member, wrong
  receiver, wrong size type, `Result<T,E>` source spelling, borrowed result,
  second await, branch/loop, extra host binding, and async root. Verify each
  fails for its intended reason before implementation.
- [x] Add a distinct `filesystem-set-size` manifest row with the pinned source
  hash and measured method/task-return fields. Add manifest tests for exact
  row equality and ABI drift.
- [x] Add a pure shape validator for locator/member/version, `File` resource,
  `u64` size, `nil | SetSizeError` result, and fixed control-flow topology.
- [x] Route only `@host_async_func` through `FilesystemSetSizePlan.analyze`;
  keep `@host_func`, wrong markers, unknown members, and wrong versions on the
  existing fail-closed diagnostic path.

**Verification:**

```bash
cd src && zig test build/p3_async_manifest.zig
cd src && zig test build/codegen_component_async.zig --test-filter 'set-size'
```

Expected end state: manifest and target classification pass; emission remains
unsupported until Task 3.

### Task 3: Implement the fixed compiler WIT/Core emitter

**Files:**

- Create: `src/build/codegen_component_wasi_filesystem_set_size.zig`
- Create: `src/build/wasi_filesystem_set_size_component_template.wat`
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/sema_imports.zig` only for shared exact diagnostics
- Modify: positive/negative set-size expectations as diagnostics stabilize

- [x] Add planner unit tests for one host binding, one direct await,
  synchronous root, exact resource shell, and all negative topology cases.
- [x] Mirror the existing bounded descriptor planners and return only names
  required by the fixed set-size template; do not add generic fallback logic.
- [x] Emit the measured indirect/direct host import, copy the `u64` size into
  the frame, preserve the descriptor until unified termination, join one
  subtask, decode unit/error result, and clean up exactly once on ready,
  error, pending, cancel, and Store-disposal paths.
- [x] Emit generated WIT with
  `set-size: async func(size: filesize) -> result<_, error-code>` and an
  owned-descriptor `run` export. Keep cancel-only WIT test code separate.
- [x] Keep default emission rejected and require the opt-in flag for the
  positive fixture.

**Verification:** Run the ABI gate, focused Zig tests, and the positive/negative
compile fixture harness. The positive WAT must contain exactly one set-size
method import and no neighboring filesystem method.

Closeout evidence: `zig test main.zig` passed `359/359`; the default full
harness passed `pass=1243 fail=0 skip=3`; `RUN_WASM=1` passed
`pass=1245 fail=0 skip=3` with WASM smoke `6/6`; the ABI gate and the
Rust/Wasmtime set-size gate passed; and `run_release_smoke.sh` passed all
ReleaseSmall build/test/check/fmt/run/LSP smoke rows. The compiler template
hash is `db09b4c2fe6f1f0a8c26f582759e9937249e352b6c852c40dc88ff753ce29385`;
the generated WIT hash is
`201038081bc51c5aeae77eca36fc4f873522e2357c2ec25c222e3ce31f486bef`.

### Task 4: Add the Rust/Wasmtime mutation and cancellation oracle

**Files:**

- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_set_size.rs`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_set_size.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`

- [x] Register the measured set-size method with `func_wrap_concurrent`.
  Copy the `u64` size before returning the future and accept only the
  configured descriptor handle.
- [x] Use a temporary file and assert ready, pending, error, repeat, cancel,
  and Store-disposal rows. Count host calls, observed sizes, polls, wakes,
  completions, future drops, pending future drops, and descriptor drops.
- [x] Assert exactly-once cleanup and explicit mutation semantics. A cancel
  row must never claim rollback of a host call already issued.
- [x] Compile the generated positive Do Component, parse/embed/validate it
  with the pinned tool, run all generated modes, and keep hand-authored cancel
  coverage separate unless its ABI is independently measured.

**Verification:**

```bash
bash examples/p3-runtime/test_rust_wasi_filesystem_set_size.sh
```

### Task 5: Close the slice and preserve pending boundaries

**Files:**

- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/start_here.md`
- Modify: `CHANGELOG.md` if the project convention requires a release entry

- [x] Record the upstream/tool/mirror hashes, measured ABI, compiler target,
  runtime counters, and cancellation mutation boundary.
- [x] Keep general filesystem async, arbitrary producer expressions, borrowed
  payload/resource lowering, external HTTP, and public ownership syntax
  explicitly pending.
- [x] Run focused ABI/compiler/runtime gates, `cd src && zig test main.zig`,
  the default full harness, the WASM full harness, and ReleaseSmall smoke.
- [x] Review `git diff --check`, inspect all changed files, commit the complete
  slice, and push only after the verification outputs are recorded.
