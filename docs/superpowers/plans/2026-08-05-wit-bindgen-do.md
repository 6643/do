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

**Revision (2026-08-05):** The upstream checkout is present at
`.deps/wit-bindgen` with SSH remote `git@github.com:bytecodealliance/wit-bindgen.git`,
detached at the pinned commit, and ignored by Git. This is the appropriate
location because it is a reproducibility-only reference and must not become a
production source dependency under `src/wit/` or `tools/`. The upstream Go/Rust
implementations are used to observe the WIT surface and canonical ABI facts;
the Do implementation translates the WIT model directly in Zig. This revision
also moves the generated-module locator gate ahead of the root-project fixture.

**Current checkpoint (2026-08-06):** The Zig lexer, parser, dependency
resolver, Do/manifest/lock emitters, and `do wit check/bind` dispatch are
present and verified. Generated custom locators pass the ordinary Do checker
while the strict WASI/P3 registry gates remain unchanged. The pinned Go/Rust
differential probe, root-layout probe, and manifest contract probes are green.
The full ReleaseSmall, compiler, Wasm, and LSP regression matrices are green.
The remaining implementation boundary is generic colorless async lowering;
explicit `do wit check --manifest` remains the WIT/model preflight. Compiler
imports already discover a sibling generated manifest and reject missing,
stale, or effect/signature-drifted metadata. Existing `async` source
declarations remain guarded until resumable lowering exists.

**Translation contract (2026-08-05 revision):** `wit-bindgen` is a semantic
reference, not a source-code template. The production data flow is

```text
WIT source -> Zig BindingModel -> Do modules + manifest.json + wit.lock
                      ^
                      | differential checks against pinned Go/Rust output
```

The Go/Rust generators answer whether a WIT construct has the expected public
surface, resource operation, async marker, or canonical ABI fact. They are not
parsed back into Do, and their generated source is never copied into the
project. This keeps the Do spelling and the manifest schema stable when an
upstream language backend changes its helper names.

**Approaches considered:**

- **A (recommended): Zig parser/resolver/emitter plus a pinned upstream
  differential oracle.** One production build, deterministic output, and a
  direct place to reject unsupported WIT shapes with Do diagnostics.
- **B (not recommended): run the Rust `wit-bindgen` CLI and translate its Go or
  Rust source.** Generated helper names and layout are backend details; this
  would make Cargo, a second compiler, and source parsing part of `bin/do`.
- **C (future option, not this phase): a Rust helper that emits a versioned
  canonical JSON model consumed by Zig.** This could reduce parser coverage,
  but it introduces a second production toolchain and an ABI/schema contract
  before the Do model is stable.

The current phase therefore adopts A. `.deps/wit-bindgen` may be fetched,
built, and executed only by explicit differential/bootstrap scripts; `do wit`
and `bin/do` must remain self-contained Zig production paths.

**Task dependency order:** Task 1 establishes the oracle and translation
matrix; Tasks 2-4 form the Zig production path; Tasks 5-6 validate generated
locators and the root `wit/` layout; Task 7 links generated async metadata to
the existing colorless async gates; Task 8 is the release matrix. Task 7 is
not allowed to claim completion until a manifest/signature mismatch is
rejected before WAT emission.

**Open blockers recorded for this plan:**

1. Generic manifest-to-lowering support is not present; explicit
   `do wit check --manifest` remains required for WIT/model preflight.
   Existing `async` source declarations remain guarded by
   `AsyncLoweringUnavailable` until resumable lowering exists.
2. Generic `own<T>`, `borrow<T>`, public `ref<T>`, arbitrary producer lowering,
   network fetching, and unrestricted P3 host binding remain outside this
   phase. They must be rejected or recorded as capability limits, never
   silently lowered.

**Verification evidence (2026-08-06, refreshed after the upstream checkout):**

- `zig test wit/tests.zig`: 22/22; `zig test wit/manifest_test.zig`: 8/8.
- `zig test main.zig`: 263/263; `zig test build/sema_imports.zig`:
  113/113; `zig test build/import_resolution.zig`: 11/11.
- `zig build -Doptimize=ReleaseSmall`: pass; release smoke: pass.
- `bash examples/wit-bindgen-do/run_differential.sh`: pass at the pinned
  commit; manifest contract and project-layout probes: pass.
- `./src/build/test/run_tests.sh`: 1095 pass, 0 fail, 3 skip;
  `RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh`: 1097 pass, 0
  fail, 3 skip; wasm smoke 6/6.
- `./src/build/test/run_release_smoke.sh`: pass.
- Automatic `Task 7` manifest-to-lowering for unrestricted generic lowering
  remains open; `Task 8 Step 3` runtime gate reruns are green. These results
  do not claim unrestricted generic async lowering.

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
- The upstream checkout is never fetched, built, or executed by `bin/do`; only
  an explicit bootstrap or differential command may access `.deps/wit-bindgen`.
- A custom WIT locator is valid input to ordinary generated `@host` declarations;
  WASI/P3 lowering still requires its existing pinned descriptor/registry gate.

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

  Before invoking Cargo, the bootstrap/probe must also fail closed on a
  changed remote or attached branch:

  ```bash
  test "$(git -C .deps/wit-bindgen remote get-url origin)" = \
    git@github.com:bytecodealliance/wit-bindgen.git
  test "$(git -C .deps/wit-bindgen rev-parse HEAD)" = \
    1ae00530221542369d0e47ee4a1f4232f09d978d
  ```

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

- [x] **Step 1: Add lexer tests for the supported WIT grammar.**

  Cover identifiers, package versions, `use`, `include`, interface/world
  declarations, type aliases, `resource`, `record`, `variant`, `enum`,
  `flags`, `result`, `option`, `future`, `stream`, `own`, `borrow`, and
  `async func`. Reject unterminated strings, invalid version components, and
  unknown punctuation with source locations.

- [x] **Step 2: Add parser tests for one complete world.**

  Parse the Task 1 world into typed AST nodes. Assert that async effect is a
  member fact, not a Do source modifier, and that `future<T>` and `stream<T>`
  retain their payload type.

- [x] **Step 3: Implement package and world resolution.**

  The resolver merges local package files and dependency directories,
  canonicalizes package/interface/member locators, and rejects duplicate
  package identities, missing `use` targets, and include cycles with named
  errors. Use the pinned upstream generators only as a behavioral oracle for
  the same input; do not import Rust AST types, generated Go/Rust files, or a
  Cargo-built resolver into the Zig build.

- [x] **Step 4: Implement the immutable binding model.**

  Preserve WIT type identity rather than flattening by spelling. Store result
  arms, resource ownership mode, drop operation, future/stream operation facts,
  and an explicit unsupported-shape reason. Include the translation facts needed
  for each emitted Do type and manifest entry. The emitter must consume this
  model and never re-parse WIT strings or upstream generated source.

- [x] **Step 5: Run Zig unit tests.**

  ```bash
  cd src
  zig test wit/tests.zig
  ```

### Task 3: Emit Do modules, manifest, and lock data in Zig

**Files:**
- Create: `src/wit/emit_do.zig`
- Create: `src/wit/emit_manifest.zig`
- Create: `src/wit/emit_lock.zig`
- Create: `src/wit/manifest.zig`
- Create: `src/wit/manifest_test.zig`
- Create: `src/wit/signature.zig`
- Modify: `src/wit/model.zig`
- Modify: `src/wit/tests.zig`

**Interfaces:**
- Consumes: `BindingModel` from Task 2.
- Produces: deterministic `*.do`, `manifest.json`, and `wit.lock` files under
  one output directory, with no partial output on failure.

- [x] **Step 1: Define deterministic flat names.**

  Emit each module as
  `<package>__<interface>__<world>.do`, replacing `/`, `:`, `@`, and `-` with
  `_`. Reject output-name collisions instead of overwriting a module.

- [x] **Step 2: Emit ordinary Do declarations.**

  Map WIT `string` to `text`, `list<u8>` to `[u8]`, futures to `Future<T>`, and
  streams to `Stream<T>`. Represent resources with Do wrapper structs and
  private handle fields. Emit `@host` binding declarations with WIT metadata;
  an `async func` must never become an `async` Do declaration. Every mapping
  must have a row in the Task 1 translation matrix and be derived from
  `BindingModel`, never from Rust/Go helper names.

- [x] **Step 3: Emit manifest and lock data.**

  `manifest.json` must contain schema version, package/world identity, member
  locator, WIT effect, canonical type shape, future/stream operation facts,
  resource move/drop facts, generated module path, and capability status.
  `wit.lock` must contain every resolved package version and content hash in
  stable sorted order. The manifest is the only later compiler input for
  generated async/resource capability checks; generated source is not scanned
  to reconstruct these facts.

- [x] **Step 4: Make bind atomic.**

  Emit into a sibling temporary directory, validate all modules and metadata,
  then replace the output directory. A resolution or emission error must leave
  the previous `wit/` directory unchanged.

- [x] **Step 5: Test stable output and negative shapes.**

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

- [x] **Step 1: Add command dispatch.**

  Add `.wit` to `Command`, dispatch `args[1..]` to `wit.run`, and update usage
  and unknown-command diagnostics. Existing command parsing and exit codes
  must remain unchanged.

- [x] **Step 2: Define the command forms.**

  Support exactly:

  ```text
  do wit check <input> [--world <world>] [--manifest <manifest.json>]
  do wit bind <input> --world <world> --out <directory>
  ```

  `check` is read-only; when `--manifest` is supplied it validates the
  generated binding contract against the resolved WIT model. `bind` validates
  before replacing output. Reject missing input/world/output, extra positional
  arguments, and output paths that are files.

- [x] **Step 3: Add CLI unit tests.**

  Cover help, unknown subcommand, missing input, missing world, check read-only
  behavior, manifest validation, bind output replacement, side-effect-free
  failed bind, and exit codes. The tests must invoke Zig functions directly and
  must not spawn Rust.

- [x] **Step 4: Build through the existing command.**

  ```bash
  cd src
  zig build -Doptimize=ReleaseSmall
  cd ..
  ./bin/do wit check examples/wit-bindgen-do/async-world.wit --world probe
  ```

  No second production compiler or sidecar build command is allowed.

### Task 5: Admit generated custom WIT locators

**Files:**
- Modify: `src/build/import_resolution.zig`
- Modify: `src/build/sema_imports.zig`
- Create: `src/build/test/check/422_wit_generated_custom_locator.do`
- Create: `src/build/test/check/423_wit_malformed_locator.do`
- Create: `src/build/test/check/423_wit_malformed_locator.expect`

**Interfaces:**
- Consumes: generated `@host("do:bindgen-probe/api@0.1.0", member, sig)`
  declarations from `do wit bind`.
- Produces: generic locator parsing for ordinary host declarations, while
  preserving the strict descriptor/registry checks used by WASI/P3 lowering;
  generated WIT host declarations are importable, but `env` host declarations
  remain non-reexportable through `@lib`.

- [x] **Step 1: Add the failing generated-locator fixture.**

  Bind the fixed probe world and run the existing checker against the emitted
  module. Record the current failure as the red test:

  ```bash
  cd src && zig build -Doptimize=ReleaseSmall
  cd ..
  rm -rf .tmp/wit-bindgen-generated
  ./bin/do wit bind examples/wit-bindgen-do/async-world.wit \
    --world probe --out .tmp/wit-bindgen-generated
  ./bin/do check .tmp/wit-bindgen-generated/do_bindgen_probe__api__probe.do
  ```

  Before the implementation this command must exit non-zero with
  `InvalidImportDecl` for the custom `do:` locator.

- [x] **Step 2: Separate generic locator syntax from WASI descriptor lookup.**

  Add one guarded parser for
  `<namespace>:<package>/<interface>@<version>` (including prerelease
  versions) and use it for ordinary `@host` declarations. Keep
  `wasi_target_from_host_parts` and the existing registry lookup as a later
  lowering guard; do not turn an unknown `wasi:` package into a permitted P3
  call merely because its locator parses.

- [x] **Step 3: Add malformed-locator diagnostics.**

  Reject empty namespace/package/interface, missing `@version`, whitespace,
  and extra path segments with `InvalidImportDecl`. Keep the source span on
  the locator token so the existing diagnostic reports the offending string.

- [x] **Step 4: Verify generated bindings and legacy WASI gates.**

  Run the positive and negative fixtures, then the existing host import tests:

  ```bash
  ./bin/do check .tmp/wit-bindgen-generated/do_bindgen_probe__api__probe.do
  ./bin/do check src/build/test/check/423_wit_malformed_locator.do
  cd src && zig test build/sema_imports.zig && zig test build/codegen_host_imports.zig
  ```

  The generated custom locator must pass; malformed input must fail; existing
  registered WASI/P3 fixtures must retain their previous results.

  Also run the import-resolution boundary test:

  ```bash
  cd src && zig test build/import_resolution.zig
  ```

  It must accept a WIT-shaped locator and reject an `env` host alias target.

  This task intentionally stops at semantic acceptance. Generic host WAT or
  Component lowering is a later task and must not be inferred from this green
  checker gate.

### Task 6: Integrate the root `wit/` project layout

**Files:**
- Modify: `README.md`
- Modify: `doc/start_here.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/host-binding-design.md`
- Create: `examples/wit-bindgen-do/project/main.do`
- Create: `examples/wit-bindgen-do/project/wit/README.md`
- Create: `examples/wit-bindgen-do/project/expected-imports.txt`
- Create: `examples/wit-bindgen-do/test_project_layout.sh`

**Interfaces:**
- Consumes: generated modules and metadata from Tasks 3-5.
- Produces: documented project layout and an import fixture proving generated
  modules are normal local Do modules.

- [x] **Step 1: Document the three directory roles.**

  Document `src/wit/` as compiler implementation, `.deps/wit-bindgen/` as
  ignored upstream reference, and project-root `wit/` as generated output.
  State that `wasi` is a package namespace, not the generic command name.

- [x] **Step 2: Add the project import fixture.**

  Generate a probe module into `examples/wit-bindgen-do/project/wit/` and
  import it from `project/main.do` using the existing relative `@lib` form.
  Assert that `lib/` and `DO_LIB_ROOT` remain unchanged.

- [x] **Step 3: Verify source/build separation.**

  Run `do wit bind` with input under `wit/src/` and output under `wit/`; assert
  that generated `.do` files are not re-read as WIT input and that a failed
  bind preserves the previous output.

  The executable regression is:

  ```bash
  examples/wit-bindgen-do/test_project_layout.sh
  ```

### Task 7: Connect generated metadata to colorless async

**Files:**
- Modify: `docs/superpowers/specs/2026-08-05-colorless-async-core-design.md`
- Modify: `docs/superpowers/plans/2026-08-05-colorless-async-core.md`
- Modify: `src/wit/manifest.zig`
- Modify: `src/wit/emit_manifest.zig`
- Modify: `src/wit/emit_do.zig`
- Modify: `src/wit/run.zig`
- Modify: `src/build/import_resolution.zig`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/wit/manifest_test.zig` with generated module drift coverage
- Create: `examples/wit-bindgen-do/project/async_main.do`
- Create: `examples/wit-bindgen-do/test_generated_async_manifest.sh`

**Interfaces:**
- Consumes: `manifest.json` async metadata and generated ordinary Do
  declarations from Tasks 3-6.
- Produces: a colorless async fixture using `@async/@await/@cancel` without
  an `async` source declaration, plus an explicit mismatch diagnostic.

- [x] **Step 1: Define and validate the manifest contract.**

  `do wit bind` is the only WIT-to-Do generation path. The versioned reader in
  `src/wit/manifest.zig` validates package/locator identity, deterministic
  generated module paths, canonical member signatures, and
  `async`/future/stream/resource effects. `do wit bind` round-trips and
  validates its own manifest before replacing output; `do wit check --manifest`
  validates an external manifest. Missing, malformed, stale, or drifted
  metadata is a named diagnostic and cannot silently downgrade an async member
  to a synchronous host call.

- [x] **Step 2: Write the generated-binding fixture.**

  Import a generated async binding, create an eager `Future<T>` with `@async`,
  consume it with `@await` on the ready path, and use `@cancel` on early
  cancellation. Do not write `async foo(...) -> T` in the fixture.

  The fixture must use the generated locator and manifest from
  `examples/wit-bindgen-do/project/wit/`; it must not hand-write a second
  host declaration. `do check` may validate the source shape before lowering,
  while `do build` must retain the existing `AsyncLoweringUnavailable` guard
  until resumable lowering is implemented.

- [x] **Step 3: Reject metadata/signature mismatch.**

  The focused `test_generated_async_manifest.sh` mutates only a temporary
  generated module and asserts `ManifestGeneratedModuleMismatch`; it also
  mutates the WIT effect and asserts `ManifestBindingMismatch`. Both checks
  happen before any caller relies on the generated binding. The module hash is
  recorded in manifest schema 1 as `module_hashes` and is validated relative
  to the manifest path.

- [x] **Step 4: Record the lowering boundary.**

  Document that manifest linkage proves metadata consistency only. It does not
  prove P3 host binding, scheduler delivery, Component GC crossing, resource
  drop execution, or Wasmtime cancellation until each has its own host-driven
  gate in Task 8.

**Task 7 execution order after the current checkpoint:**

1. Generate a temporary root `wit/`, validate its manifest and module hashes,
   then run `do check` on a caller importing the generated `completion` host
   function with `@async/@await/@cancel`.
2. Mutate only the temporary generated module and WIT source; reject both
   module-content and WIT effect drift before source admission.
3. Keep `do build` rejected by `AsyncLoweringUnavailable`; this gate proves
   metadata and frontend consistency only, not frame or Component lowering.

### Task 8: Full verification and delivery

**Files:**
- Modify only with observed evidence: `doc/pending_blocked.md`,
  `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`
- Test: Zig unit, differential, compiler, Component, Rust/Wasmtime, and
  ReleaseSmall matrices

**Interfaces:**
- Consumes: all prior WIT bindgen and colorless async gates.
- Produces: one Zig-built toolchain checkpoint with explicit remaining WIT
  capability boundaries.

- [x] **Step 1: Verify the pinned reference and Zig implementation.**

  ```bash
  test "$(git -C .deps/wit-bindgen rev-parse HEAD)" = \
    1ae00530221542369d0e47ee4a1f4232f09d978d
  test "$(git -C .deps/wit-bindgen remote get-url origin)" = \
    git@github.com:bytecodealliance/wit-bindgen.git
  bash examples/wit-bindgen-do/run_differential.sh
  cd src && zig test wit/tests.zig && zig test main.zig
  cd ..
  git diff --check
  ```

- [x] **Step 2: Run the full compiler matrix.**

  ```bash
  cd src && zig build -Doptimize=ReleaseSmall
  cd ..
  ./src/build/test/run_tests.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  ```

  Observed on 2026-08-06: normal matrix 1095 pass, 0 fail, 3 skip; Wasm
  matrix 1097 pass, 0 fail, 3 skip; wasm smoke 6/6; ReleaseSmall smoke
  passed.

- [x] **Step 3: Verify existing runtime gates.**

  Re-run the existing variant, resource Result, stream, filesystem, socket,
  and async cancellation Component/Rust/Wasmtime scripts. A new generated
  binding failure must not be recorded as a regression in an unrelated bounded
  descriptor.

  `bash examples/p3-runtime/test_task8_step3_baseline.sh` passed all seven
  registered runtime gates on 2026-08-06. The canonical async scanner migration
  also passed the nested record-resource lowering, borrowed-resource rejection,
  and G6.2 boundary gates.

- [x] **Step 4: Record residual limits.**

  Record that arbitrary WIT shapes, public `own<T>`/`borrow<T>`/`ref<T>`,
  network fetching, and generic producer lowering remain outside this plan.
  Also record that the upstream checkout is a differential oracle rather than
  a production dependency. Record exact commands, pinned reference commit, and
  observed results before claiming completion.
