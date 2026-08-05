# WIT Bindgen Do Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** add a reproducible `do wit check/bind` workflow implemented in Zig,
translating a canonical WIT model into flat project-root `wit/*.do` bindings
and metadata, with pinned upstream Rust and Go generators as differential
oracles.

**Architecture:** `src/wit/` contains the Zig WIT lexer, parser, immutable
canonical model, resolver, emitter, and CLI adapter. `src/main.zig` dispatches
`do wit` through the same `bin/do` executable, so the existing
`cd src && zig build` remains the only production compiler build. The canonical
model is the translation boundary: every emitted Do declaration and manifest
fact comes from it. `.deps/wit-bindgen` is an ignored, detached checkout of
upstream `v0.60.0` used only by opt-in probes and research; no Rust sidecar is
required to run or build Do.

**Tech Stack:** Zig `0.16.0`, pinned upstream `wit-bindgen v0.60.0` at commit
`1ae00530221542369d0e47ee4a1f4232f09d978d` for Go/Rust differential probes,
WAT/WIT validation with `wasm-tools 1.254.0`, and the existing Do regression
harness.

## Global Constraints

- The generic command is `do wit`; `wasi` is reserved for package and
  registry-specific names.
- Production WIT parsing, resolution, and emission are implemented in Zig
  under `src/wit/`.
- `.deps/wit-bindgen` is a local ignored reference checkout, not a build or
  runtime dependency of `bin/do`.
- Bootstrap the reference with the pinned tag and detached commit; refresh it
  only explicitly with `git fetch --tags` and never from `do wit` itself.
- WIT is the source of truth. Go/Rust generated source is differential evidence
  for the `WIT construct -> Do spelling -> manifest/ABI fact` translation and
  is never production input or copied runtime code.
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

### Task 1: Pin upstream Go/Rust differential probe

**Files:**
- Create: `examples/wit-bindgen-do/async-world.wit`
- Create: `examples/wit-bindgen-do/run_differential.sh`
- Create: `examples/wit-bindgen-do/README.md`
- Create: `examples/wit-bindgen-do/expected/go_api.txt`
- Create: `examples/wit-bindgen-do/expected/rust_api.txt`
- Create: `examples/wit-bindgen-do/expected/abi_matrix.txt`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `.deps/wit-bindgen` at the pinned commit and one WIT world
  containing async, future, stream, resource, result, and cancellation facts.
- Produces: a checked-in comparison of Go/Rust generated APIs, async ABI
  markers, reader/writer types, resource drop behavior, and terminal cleanup.

- [x] **Step 1: Bootstrap, pin, and verify the reference checkout.**

  Add `.deps/` to `.gitignore`. When the checkout is absent, bootstrap it with
  the pinned tag; when it exists, refresh tags explicitly and detach at the
  pinned commit. The probe must fail closed unless both tag and commit resolve
  to the expected object:

  ```bash
  mkdir -p .deps
  git clone --branch v0.60.0 --depth 1 \
    git@github.com:bytecodealliance/wit-bindgen.git .deps/wit-bindgen
  git -C .deps/wit-bindgen fetch --tags origin
  git -C .deps/wit-bindgen checkout --detach \
    1ae00530221542369d0e47ee4a1f4232f09d978d
  test "$(git -C .deps/wit-bindgen rev-parse HEAD)" = \
    1ae00530221542369d0e47ee4a1f4232f09d978d
  test "$(git -C .deps/wit-bindgen rev-parse v0.60.0^{commit})" = \
    1ae00530221542369d0e47ee4a1f4232f09d978d
  ```

- [x] **Step 2: Write the fixed WIT world.**

  Use package `do:bindgen-probe@0.1.0` and world `probe`. The interface must
  contain `resource request`, `resource response`,
  `async func send(request: request) -> result<response, error>`,
  `func completion() -> future<u32>`, and `func events() -> stream<u8>`.

- [x] **Step 3: Run the upstream generators.**

  Invoke the checked-out `wit-bindgen` CLI with its `go` and `rust` generators,
  using the fixed world. Save only stable API fragments and ABI markers; do
  not check in generated Go/Rust build trees.

- [x] **Step 4: Record the differential and translation matrix.**

  Record Future/Stream types, `[async-lower]`/`[async-lift]` markers,
  callback/task-return operations, resource move/drop rules, and cancellation
  terminal handling. For each supported shape also record the explicit
  `WIT construct -> Do spelling -> manifest/ABI fact` mapping. Mark every row as
  surface API, canonical ABI, or runtime behavior.

- [x] **Step 5: Verify reproducibility.**

  ```bash
  bash examples/wit-bindgen-do/run_differential.sh
  git diff --check
  ```

  The script must fail when the reference checkout or WIT world changes; it
  must not substitute a synchronous output.

### Task 2: Implement the Zig WIT lexer, parser, and resolver

**Files:**
- Create: `src/wit/lexer.zig`
- Create: `src/wit/parser.zig`
- Create: `src/wit/resolve.zig`
- Create: `src/wit/model.zig`
- Create: `src/wit/tests.zig`
- Modify: `src/main.zig`

**Interfaces:**
- Consumes: a WIT file or package directory and an optional world name.
- Produces: an immutable `BindingModel` containing package identity, world,
  interfaces, functions, types, async/future/stream effects, resources,
  ownership facts, and content hashes.

- [ ] **Step 1: Add lexer tests for the supported WIT grammar.**

  Cover identifiers, package versions, `use`, `include`, interface/world
  declarations, type aliases, `resource`, `record`, `variant`, `enum`,
  `flags`, `result`, `option`, `future`, `stream`, `own`, `borrow`, and
  `async func`. Reject unterminated strings, invalid version components, and
  unknown punctuation with source locations.

- [ ] **Step 2: Add parser tests for one complete world.**

  Parse the Task 1 world into typed AST nodes. Assert that async effect is a
  member fact, not a Do source modifier, and that `future<T>` and `stream<T>`
  retain their payload type.

- [ ] **Step 3: Implement package and world resolution.**

  Resolve local package files and dependency directories, select the requested
  world, canonicalize package/interface/member locators, and calculate stable
  content hashes. Reject duplicate package identities, missing `use` targets,
  unresolved world names, and cycles with named errors.

- [ ] **Step 4: Implement the immutable binding model.**

  Preserve WIT type identity rather than flattening by spelling. Store result
  arms, resource ownership mode, drop operation, future/stream operation facts,
  and an explicit unsupported-shape reason. Include the translation facts needed
  for each emitted Do type and manifest entry. The emitter must consume this
  model and never re-parse WIT strings or upstream generated source.

- [ ] **Step 5: Run Zig unit tests.**

  ```bash
  cd src
  zig test wit/tests.zig
  ```

### Task 3: Emit Do modules, manifest, and lock data in Zig

**Files:**
- Create: `src/wit/emit_do.zig`
- Create: `src/wit/emit_manifest.zig`
- Create: `src/wit/emit_lock.zig`
- Modify: `src/wit/model.zig`
- Modify: `src/wit/tests.zig`

**Interfaces:**
- Consumes: `BindingModel` from Task 2.
- Produces: deterministic `*.do`, `manifest.json`, and `wit.lock` files under
  one output directory, with no partial output on failure.

- [ ] **Step 1: Define deterministic flat names.**

  Emit each module as
  `<package>__<interface>__<world>.do`, replacing `/`, `:`, `@`, and `-` with
  `_`. Reject output-name collisions instead of overwriting a module.

- [ ] **Step 2: Emit ordinary Do declarations.**

  Map WIT `string` to `text`, `list<u8>` to `[u8]`, futures to `Future<T>`, and
  streams to `Stream<T>`. Represent resources with Do wrapper structs and
  private handle fields. Emit `@host` binding declarations with WIT metadata;
  an `async func` must never become an `async` Do declaration.

- [ ] **Step 3: Emit manifest and lock data.**

  `manifest.json` must contain schema version, package/world identity, member
  locator, WIT effect, canonical type shape, future/stream operation facts,
  resource move/drop facts, generated module path, and capability status.
  `wit.lock` must contain every resolved package version and content hash in
  stable sorted order.

- [ ] **Step 4: Make bind atomic.**

  Emit into a sibling temporary directory, validate all modules and metadata,
  then replace the output directory. A resolution or emission error must leave
  the previous `wit/` directory unchanged.

- [ ] **Step 5: Test stable output and negative shapes.**

  Generate the Task 1 world twice and assert byte-identical output. Add tests
  for name collision, unsupported nested borrowed shape, duplicate resource
  drop, malformed manifest, and failed-bind atomicity.

### Task 4: Add `do wit` to the existing Zig executable

**Files:**
- Create: `src/wit/cli.zig`
- Create: `src/wit/run.zig`
- Modify: `src/main.zig`
- Modify: `src/wit/tests.zig`

**Interfaces:**
- Consumes: the Zig resolver/emitter from Tasks 2-3.
- Produces: stable `do wit check` and `do wit bind` commands in the existing
  `bin/do` executable.

- [ ] **Step 1: Add command dispatch.**

  Add `.wit` to `Command`, dispatch `args[1..]` to `wit.run`, and update usage
  and unknown-command diagnostics. Existing command parsing and exit codes
  must remain unchanged.

- [ ] **Step 2: Define the command forms.**

  Support exactly:

  ```text
  do wit check <input> [--world <world>]
  do wit bind <input> --world <world> --out <directory>
  ```

  `check` is read-only. `bind` validates before replacing output. Reject
  missing input/world/output, extra positional arguments, and output paths that
  are files.

- [ ] **Step 3: Add CLI unit tests.**

  Cover help, unknown subcommand, missing input, missing world, check read-only
  behavior, bind output replacement, side-effect-free failed bind, and exit
  codes. The tests must invoke Zig functions directly and must not spawn Rust.

- [ ] **Step 4: Build through the existing command.**

  ```bash
  cd src
  zig build -Doptimize=ReleaseSmall
  cd ..
  ./bin/do wit check examples/wit-bindgen-do/async-world.wit --world probe
  ```

  No second production compiler or sidecar build command is allowed.

### Task 5: Integrate the root `wit/` project layout

**Files:**
- Modify: `README.md`
- Modify: `doc/start_here.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/host-binding-design.md`
- Create: `examples/wit-bindgen-do/project/main.do`
- Create: `examples/wit-bindgen-do/project/wit/README.md`
- Create: `examples/wit-bindgen-do/project/expected-imports.txt`

**Interfaces:**
- Consumes: generated modules and metadata from Tasks 3-4.
- Produces: documented project layout and an import fixture proving generated
  modules are normal local Do modules.

- [ ] **Step 1: Document the three directory roles.**

  Document `src/wit/` as compiler implementation, `.deps/wit-bindgen/` as
  ignored upstream reference, and project-root `wit/` as generated output.
  State that `wasi` is a package namespace, not the generic command name.

- [ ] **Step 2: Add the project import fixture.**

  Generate a probe module into `examples/wit-bindgen-do/project/wit/` and
  import it from `project/main.do` using the existing relative `@lib` form.
  Assert that `lib/` and `DO_LIB_ROOT` remain unchanged.

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
- Produces: a colorless async fixture using `@async/@await/@cancel` without
  an `async` source declaration, plus an explicit mismatch diagnostic.

- [ ] **Step 1: Make the binding dependency explicit.**

  State that `do wit bind` is the only WIT-to-Do generation path and that the
  colorless async compiler consumes its manifest rather than inferring async
  effects from a Do function name.

- [ ] **Step 2: Write the generated-binding fixture.**

  Import a generated async binding, create an eager `Future<T>` with `@async`,
  consume it with `@await` on the ready path, and use `@cancel` on early
  cancellation. Do not write `async foo(...) -> T` in the fixture.

- [ ] **Step 3: Reject metadata/signature mismatch.**

  Give the generated member a synchronous source signature while the manifest
  says `async func`; assert the named mismatch diagnostic and ensure no WAT is
  emitted.

### Task 7: Full verification and delivery

**Files:**
- Modify only with observed evidence: `doc/pending_blocked.md`,
  `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`
- Test: Zig unit, differential, compiler, Component, Rust/Wasmtime, and
  ReleaseSmall matrices

**Interfaces:**
- Consumes: all prior WIT bindgen and colorless async gates.
- Produces: one Zig-built toolchain checkpoint with explicit remaining WIT
  capability boundaries.

- [ ] **Step 1: Verify the pinned reference and Zig implementation.**

  ```bash
  test "$(git -C .deps/wit-bindgen rev-parse HEAD)" = \
    1ae00530221542369d0e47ee4a1f4232f09d978d
  bash examples/wit-bindgen-do/run_differential.sh
  cd src && zig test wit/tests.zig && zig test main.zig
  cd ..
  git diff --check
  ```

- [ ] **Step 2: Run the full compiler matrix.**

  ```bash
  cd src && zig build -Doptimize=ReleaseSmall
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

- [ ] **Step 4: Record residual limits.**

  Record that arbitrary WIT shapes, public `own<T>`/`borrow<T>`/`ref<T>`,
  network fetching, and generic producer lowering remain outside this plan.
  Record exact commands, pinned reference commit, and observed results before
  claiming completion.
