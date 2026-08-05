# WIT Bindgen Do Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** add a reproducible `do wit check/bind` workflow that resolves WIT,
generates flat project-root `wit/*.do` bindings, and emits the metadata consumed
by the colorless async and Component lowering paths.

**Architecture:** `do wit` is a thin Zig CLI facade. A separate Rust
`wit-bindgen-do` sidecar reuses the official `wit-parser` and
`wit-bindgen-core` crates for resolution and canonical WIT facts, then emits Do
source, `manifest.json`, and `wit.lock` atomically. The Do compiler continues
to own source semantics, ARC, task scheduling, and `@async/@await/@cancel`
lowering.

**Tech Stack:** Zig `0.16.0`, Rust `1.97.1`, pinned `wit-bindgen` release
`0.60.0`, `wit-parser 0.254.0`, `wit-bindgen-core 0.60.0`, WAT/WIT validation
with `wasm-tools 1.254.0`, and the existing Do regression harness.

## Global Constraints

- The generic command is `do wit`; `wasi` is reserved for package and
  registry-specific names.
- Generated Do files are flat under the project-root `wit/` directory.
- Generated output includes `manifest.json` and `wit.lock` beside the `*.do`
  files.
- WIT source input may be `wit/src/` or an external directory; generated files
  are never used as the input tree.
- No WIT language syntax or standard is modified.
- No generated binding is written into `lib/` or `src/build/p3_wit`.
- WIT `async func` metadata never emits the migration-only Do declaration
  `async name(...) -> T`.
- Public generated calls use Do `Future<T>`, `Stream<T>`, and the intrinsic
  operations `@async`, `@await`, and `@cancel`.
- Unsupported WIT shapes fail with a named capability diagnostic; they are not
  silently emitted as synchronous declarations.
- Existing bounded Component/Rust/Wasmtime gates remain unchanged until a new
  generated shape has its own gate.

---

### Task 1: Pin Go/Rust differential probe

**Files:**
- Create: `examples/wit-bindgen-do/async-world.wit`
- Create: `examples/wit-bindgen-do/run_differential.sh`
- Create: `examples/wit-bindgen-do/README.md`
- Create: `examples/wit-bindgen-do/expected/go_api.txt`
- Create: `examples/wit-bindgen-do/expected/rust_api.txt`
- Create: `examples/wit-bindgen-do/expected/abi_matrix.txt`

**Interfaces:**
- Consumes: one pinned WIT world containing an `async func`, `future<T>`,
  `stream<T>`, resource parameters, a result payload, and a cancellation path.
- Produces: a checked-in comparison of Go and Rust generated APIs, async ABI
  markers, reader/writer types, resource drop behavior, and terminal cleanup.

- [ ] **Step 1: Write the fixed WIT world.**

  Use package `do:bindgen-probe@0.1.0` and world `probe`. The interface must
  contain `resource request`, `resource response`, `result<response, error>`,
  `async func send(request: request)`, `func completion() -> future<u32>`, and
  `func events() -> stream<u8>`. Keep this world independent of the pinned
  WASI registry so the comparison measures generator behavior rather than a
  descriptor-specific compiler shortcut.

- [ ] **Step 2: Run the pinned Go and Rust generators.**

  Run the `wit-bindgen 0.60.0` CLI from a locked checkout with the `go` and
  `rust` generators, using `async-world.wit` and world `probe`. Save only the
  stable API fragments needed by the report; do not check in generated Go or
  Rust build trees.

- [ ] **Step 3: Record the differential matrix.**

  Record the generated Future/Stream type names, `[async-lower]` and
  `[async-lift]` markers, callback/task-return operations, resource move/drop
  rules, and cancellation terminal behavior. Mark each fact as surface API,
  canonical ABI, or runtime behavior.

- [ ] **Step 4: Verify the probe is reproducible.**

  ```bash
  bash examples/wit-bindgen-do/run_differential.sh
  git diff --check
  ```

  The script must fail when either generator is missing or the pinned WIT world
  changes; it must not substitute a synchronous output.

### Task 2: Create the Rust resolver sidecar

**Files:**
- Create: `tools/wit-bindgen-do/Cargo.toml`
- Create: `tools/wit-bindgen-do/Cargo.lock`
- Create: `tools/wit-bindgen-do/src/main.rs`
- Create: `tools/wit-bindgen-do/src/cli.rs`
- Create: `tools/wit-bindgen-do/src/resolve.rs`
- Create: `tools/wit-bindgen-do/src/model.rs`
- Create: `tools/wit-bindgen-do/tests/resolve.rs`

**Interfaces:**
- Consumes: a WIT file or package directory and an optional world name.
- Produces: a resolved `BindingModel` containing package identity, world,
  interfaces, functions, type definitions, async/future/stream effects,
  resource ownership, and content hashes.

- [ ] **Step 1: Define the sidecar CLI.**

  Implement exactly these forms:

  ```text
  wit-bindgen-do check <input> [--world <world>]
  wit-bindgen-do bind <input> --world <world> --out <directory>
  ```

  Reject missing input, missing world, extra positional arguments, and output
  paths that are files. Diagnostics must identify the input path and WIT world.

- [ ] **Step 2: Resolve with the official parser.**

  Use `wit_parser::Resolve` with `wit-parser 0.254.0` and
  `wit-bindgen-core 0.60.0`, both recorded in `Cargo.lock`. Resolve package dependencies, select the requested world, and
  calculate a stable content hash over the resolved package files. Do not infer
  async or ownership from function names or generated source text.

- [ ] **Step 3: Build the immutable binding model.**

  `BindingModel` must preserve the WIT package/interface/member locator,
  source type, result arms, future/stream payload, resource ownership mode,
  drop operation, and unsupported-shape reason. The emitter consumes this
  model and never re-parses WIT strings.

- [ ] **Step 4: Add resolver tests.**

  Cover successful world selection, missing world, dependency hash changes,
  async member recognition, future/stream payload recognition, own resource
  parameters, and a nested borrowed shape rejected with the named capability
  error.

- [ ] **Step 5: Run sidecar tests.**

  ```bash
  cd tools/wit-bindgen-do
  cargo test --locked
  ```

### Task 3: Emit Do modules and binding metadata

**Files:**
- Create: `tools/wit-bindgen-do/src/emit_do.rs`
- Create: `tools/wit-bindgen-do/src/emit_manifest.rs`
- Create: `tools/wit-bindgen-do/src/emit_lock.rs`
- Modify: `tools/wit-bindgen-do/src/main.rs`
- Modify: `tools/wit-bindgen-do/src/model.rs`
- Create: `tools/wit-bindgen-do/tests/emit.rs`

**Interfaces:**
- Consumes: `BindingModel` from Task 2.
- Produces: deterministic `*.do`, `manifest.json`, and `wit.lock` files under
  one output directory, with no partial output on failure.

- [ ] **Step 1: Define deterministic file names.**

  Flatten each generated module to
  `<package>__<interface>__<world>.do`, replacing `/`, `:`, `@`, and `-` with
  `_`. Reject two WIT modules that map to the same output name instead of
  overwriting one.

- [ ] **Step 2: Emit ordinary Do declarations.**

  Emit Do type declarations and `@host` binding declarations for the supported
  model. Map WIT `string` to `text`, `list<u8>` to `[u8]`, WIT futures to
  `Future<T>`, and WIT streams to `Stream<T>`. Resource values remain opaque Do
  handles with metadata-driven drop facts. WIT `async func` produces an
  ordinary binding whose manifest records async lowering; it never produces an
  `async` Do declaration.

- [ ] **Step 3: Emit manifest and lock data.**

  `manifest.json` must contain schema version, package/world identity, member
  locator, WIT effect, canonical type shape, future/stream operation facts,
  resource move/drop facts, generated module path, and capability status.
  `wit.lock` must contain every resolved package version and content hash in
  stable sorted order.

- [ ] **Step 4: Make bind atomic.**

  Emit into a sibling temporary directory, fsync files, then replace the output
  directory only after all modules, manifest, and lock data validate. A WIT
  resolution or emission error must leave the previous `wit/` directory
  unchanged.

- [ ] **Step 5: Test stable output.**

  Generate the fixed probe twice and assert byte-identical `*.do`, manifest,
  and lock files. Add a collision fixture, unsupported borrowed-shape fixture,
  and failed-bind atomicity fixture.

### Task 4: Add the `do wit` Zig facade

**Files:**
- Create: `src/wit/run.zig`
- Create: `src/wit/cli.zig`
- Modify: `src/main.zig`
- Create: `src/build/test/cli_wit.zig`
- Create: `src/build/test/cli_wit_bind.sh`

**Interfaces:**
- Consumes: `wit-bindgen-do check/bind` sidecar commands.
- Produces: stable `do wit check` and `do wit bind` user commands with Do
  diagnostics and project-relative output behavior.

- [ ] **Step 1: Add command dispatch.**

  Add `.wit` to `Command`, dispatch `args[1..]` to `wit.run`, and update usage
  and unknown-command diagnostics in `src/main.zig`. Existing command parsing
  and exit codes must remain unchanged.

- [ ] **Step 2: Resolve the sidecar executable.**

  Check `DO_WIT_BINDGEN_DO` first, then a `wit-bindgen-do` sibling next to the
  running `do` executable, then `PATH`. Report one deterministic missing-tool
  error with the selected path and required command. Never download a tool at
  runtime.

- [ ] **Step 3: Forward validated arguments.**

  Support only:

  ```text
  do wit check <input> [--world <world>]
  do wit bind <input> --world <world> --out <directory>
  ```

  Resolve a relative output path from the current working directory, reject
  paths outside the project only when the user explicitly requests a policy
  mode, and pass the canonical absolute path to the sidecar.

- [ ] **Step 4: Add CLI tests.**

  Test help, missing sidecar, check argument validation, bind argument
  validation, sidecar exit-code propagation, and successful generation into a
  temporary root `wit/` directory.

- [ ] **Step 5: Run the focused Zig tests.**

  ```bash
  cd src
  zig test main.zig
  cd ..
  bash src/build/test/cli_wit_bind.sh
  ```

### Task 5: Integrate the root `wit/` layout and imports

**Files:**
- Modify: `README.md`
- Modify: `doc/start_here.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/host-binding-design.md`
- Create: `examples/wit-bindgen-do/project/main.do`
- Create: `examples/wit-bindgen-do/project/wit/README.md`
- Create: `examples/wit-bindgen-do/project/expected-imports.txt`

**Interfaces:**
- Consumes: generated modules and manifest from Task 3 plus `do wit` from
  Task 4.
- Produces: documented project layout and an import fixture proving generated
  modules are normal local Do modules.

- [ ] **Step 1: Document the directory contract.**

  Document `wit/*.do`, `wit/manifest.json`, `wit/wit.lock`, optional `wit/src/`,
  and the distinction between generic `wit` and WASI-specific `wasi` names.
  State that compiler-pinned `src/build/p3_wit` is an internal registry and is
  not the project output directory.

- [ ] **Step 2: Add the project import fixture.**

  Generate a probe module into `examples/wit-bindgen-do/project/wit/` and
  import it from `project/main.do` with the existing relative `@lib` form.
  Assert that the generated module is resolved without modifying `lib/` or
  `DO_LIB_ROOT`.

- [ ] **Step 3: Verify source/build separation.**

  Run `do wit bind` with input under `wit/src/` and output under `wit/`; assert
  that generated `.do` files are not re-read as WIT input and that a failed
  bind preserves the previous output.

### Task 6: Connect generated metadata to colorless async

**Files:**
- Modify: `docs/superpowers/specs/2026-08-05-colorless-async-core-design.md`
- Modify: `docs/superpowers/plans/2026-08-05-colorless-async-core.md`
- Create: `src/build/test/compile_ok/421_wit_generated_colorless_async.do`
- Create: `src/build/test/compile_err/421_wit_generated_async_shape.do`
- Create: `src/build/test/compile_err/421_wit_generated_async_shape.expect`

**Interfaces:**
- Consumes: `manifest.json` async metadata and generated ordinary Do
  declarations from Tasks 3-5.
- Produces: a colorless async fixture that uses `@async/@await/@cancel`
  without an `async` source declaration, plus an explicit mismatch diagnostic.

- [ ] **Step 1: Add the binding dependency to the async design.**

  State that `do wit bind` is the only supported WIT-to-Do generation path and
  that Task 5 of the colorless async plan consumes its manifest rather than
  inferring async behavior from a Do function name.

- [ ] **Step 2: Write the generated-binding fixture.**

  Import a generated async binding, create an eager `Future<T>` with
  `@async`, consume it with `@await` on the ready path, and use `@cancel` on
  the early-cancel path. Do not write `async foo(...) -> T` in the fixture.

- [ ] **Step 3: Reject metadata/signature mismatch.**

  Give the generated member a synchronous source signature while the manifest
  says `async func`; assert the named mismatch diagnostic and ensure no WAT is
  emitted.

- [ ] **Step 4: Run the focused async and binding gates.**

  ```bash
  ./bin/do check src/build/test/compile_ok/421_wit_generated_colorless_async.do
  ./bin/do check src/build/test/compile_err/421_wit_generated_async_shape.do
  bash examples/p3-runtime/test_do_async_resource_result.sh
  bash examples/p3-runtime/test_rust_async_resource_result.sh
  ```

### Task 7: Full verification and delivery

**Files:**
- Modify only with observed evidence: `doc/pending_blocked.md`,
  `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`
- Test: sidecar, CLI, compiler, Component, Rust/Wasmtime, and ReleaseSmall
  matrices

**Interfaces:**
- Consumes: all prior WIT bindgen and colorless async gates.
- Produces: a reproducible toolchain checkpoint with explicit remaining WIT
  capability boundaries.

- [ ] **Step 1: Run sidecar and focused command gates.**

  ```bash
  cd tools/wit-bindgen-do && cargo test --locked
  cd ../..
  bash examples/wit-bindgen-do/run_differential.sh
  bash src/build/test/cli_wit_bind.sh
  git diff --check
  ```

- [ ] **Step 2: Run the compiler matrix.**

  ```bash
  cd src && zig test main.zig
  cd ..
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  ```

- [ ] **Step 3: Verify existing runtime gates.**

  Re-run the existing variant, resource Result, stream, filesystem, socket,
  and async cancellation Component/Rust/Wasmtime scripts. A new generated
  binding failure must not be recorded as a regression in an unrelated bounded
  descriptor.

- [ ] **Step 4: Update the roadmap with residual limits.**

  Record that arbitrary WIT shapes, public `own<T>`/`borrow<T>`/`ref<T>`,
  network fetching, and generic producer lowering remain outside this plan.
  Record exact commands and pinned versions before claiming completion.

- [ ] **Step 5: Commit the bounded change.**

  ```bash
  git add docs/superpowers/specs/2026-08-05-wit-bindgen-do-design.md \
    docs/superpowers/plans/2026-08-05-wit-bindgen-do.md \
    tools/wit-bindgen-do src/wit src/main.zig \
    examples/wit-bindgen-do README.md doc
  git commit -m "Add WIT to Do binding generation plan"
  ```
