# WIT Bindgen Do Design

**Status:** approved for implementation planning; revised to pin and use the
upstream checkout as a translation oracle.

**Goal:** provide a reproducible WIT-to-Do binding workflow without changing
the WIT language, while keeping the production implementation in the Zig
toolchain.

## Naming and Scope

The generic command and project directory use `wit`:

```text
do wit check ...
do wit bind ...
project/wit/
```

`wasi` remains a package/ecosystem namespace for official WASI interfaces. It
is not the name of the generic binding command or output directory. A future
WASI-specific registry command may live below `do wasi`, but it must not
replace `do wit`.

This design does not add syntax or commands to the WIT specification itself.
It adds a Do toolchain command and a Do-specific binding generator.

## Upstream Reference Checkout

The official `wit-bindgen` repository is kept as a local, ignored reference
checkout at `.deps/wit-bindgen`. The pinned reference is tag `v0.60.0` at
commit `1ae00530221542369d0e47ee4a1f4232f09d978d`. Its Rust and Go generators
are used for differential probes and ABI research; they are not runtime or
build dependencies of `bin/do`.

The checkout is bootstrapped explicitly and then detached at the pinned
commit:

```bash
mkdir -p .deps
git clone --branch v0.60.0 --depth 1 \
  git@github.com:bytecodealliance/wit-bindgen.git .deps/wit-bindgen
git -C .deps/wit-bindgen checkout --detach \
  1ae00530221542369d0e47ee4a1f4232f09d978d
```

For an existing checkout, refresh tags and re-pin it with
`git -C .deps/wit-bindgen fetch --tags origin` followed by the same detached
checkout. The production `do wit` command never fetches or executes this
checkout; only the opt-in differential probe may build its CLI. A missing or
mismatched checkout is a closed failure, never a request to silently use a
different version.

## Project Layout

The generated Do bindings are placed directly in the project-root `wit/`
directory so they can be reviewed, committed, and imported as normal Do
modules:

```text
project/
  wit/
    wasi_http_client.do
    wasi_filesystem.do
    custom_metrics.do
    manifest.json
    wit.lock
    src/                 # optional local WIT source tree
```

All generated `*.do` files are flat and have deterministic names derived from
the WIT package, interface, and world. WIT source files may be kept under
`wit/src/` or supplied from another path; generated files must not be used as
the input source tree. The compiler's pinned internal WIT remains under
`src/build/p3_wit` and is not moved into the project directory.

Generated modules are imported explicitly with the existing local import
form, for example:

```do
Http = @lib("./wit/wasi_http_client.do", Http)
```

The first version does not add a new `@wit` source syntax or an implicit import
search path.

## Command Contract

The public commands are:

```bash
do wit check <wit-input> [--world <world>]
do wit bind <wit-input> --world <world> --out <project/wit>
```

`check` resolves packages, validates the selected world, and reports the
version/hash and unsupported WIT shapes without writing generated source.
`bind` performs the same validation and writes only deterministic generated
files under the requested output directory. Existing generated files are
replaced only after successful validation and emission.

The output contract is:

- one or more generated Do modules with ordinary function declarations;
- `manifest.json` containing package/world/member identity, WIT effect,
  future/stream metadata, resource ownership/drop facts, and the generated
  module map;
- `wit.lock` containing the resolved package versions and content hashes.

WIT `async func` is represented in metadata. Generated Do declarations do not
use the migration-only `async name(...) -> T` declaration. Their call/lowering
contract uses `@async`, `@await`, and `@cancel` from the colorless async core.

## Generator Boundary

The implementation is split into two layers:

```text
do wit check/bind
        |
        v
src/wit (Zig generator)
        |
        +-- WIT lexer/parser/resolver
        +-- Do source emitter
        +-- manifest and lock emitter
```

The Zig implementation owns WIT resolution, canonical type facts, Do source
emission, diagnostics, and atomic output. It is a Do-specific generator rather
than a claim to replace every upstream language generator.

WIT remains the source of truth. The resolver first constructs an immutable
canonical model, then translates each supported WIT shape through an explicit
`WIT construct -> Do spelling -> manifest/ABI fact` mapping. Generated Go or
Rust source is not parsed as production input and is never copied into the Do
toolchain; it is evidence used to validate that mapping.

The checked-in reference generators are differential oracles, not copied
runtimes:

- Go is the surface oracle for ordinary generated APIs and hidden async wait
  plumbing.
- Rust is the ABI oracle for canonical lowering, Future/Stream reader/writer
  shapes, resource ownership, borrow/drop, and terminal cleanup.
- Do owns the public syntax, affine Future rules, ARC integration, scheduler,
  and cancellation semantics.

The first implementation supports only the WIT shapes covered by pinned
fixtures. Unsupported shapes produce named capability errors. A new WIT
feature is admitted only after the Zig model, Go/Rust differential output, and
Do/Component gate agree.

## Acceptance Gates

The design is complete only when all of the following are verified:

1. the same pinned WIT world is generated by Go, Rust, and Do probes;
2. Do output contains deterministic ordinary declarations and metadata;
3. WIT async/future/stream/resource facts match the differential report;
4. generated files are placed flat under `wit/` with stable names;
5. `do wit check` is read-only and rejects unsupported shapes;
6. `do wit bind` is atomic on validation failure and emits `manifest.json` and
   `wit.lock` together with the generated modules;
7. a generated async binding reaches the existing `@async/@await/@cancel`
   lowering gates without a source `async` declaration;
8. existing compiler, Component, Rust, and Wasmtime gates remain unchanged.

## Non-Goals

- no public `own<T>`, `borrow<T>`, or `ref<T>` syntax;
- no automatic WIT network fetching in the first command version;
- no generic WIT lowering claim beyond the individually pinned and tested
  shapes;
- no production Rust sidecar or second compiler command;
- no replacement of `do build --p3-wit-output` for Do-to-WIT/component output;
- no WASI-only command surface for generic WIT packages.
