# Rust Runner Build Cache Reduction Design

**Status:** Verified on the pinned Rust/Wasmtime runner environment.

**Goal:** Reclaim the generated build artifacts under
`examples/p3-runtime/rust-host-runner/target` and prevent unnecessary debug
and incremental artifacts from regrowing there, without changing Do compiler
behavior, WIT semantics, or any other project's Cargo output.

## Measured Scope

`cargo metadata --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml`
resolves its target directory to the runner-local `target` path. At design
time, that directory is 130GB: approximately 111GB in `debug/deps`, 14GB in
`debug/build`, and 5GB in `debug/incremental`. The largest executable runners
are each about 224-236MB because they statically link Wasmtime with debug
information.

The runner-local `.gitignore` already ignores `/target/`. No shared Cargo
registry/cache, sibling workspace, source file, WIT fixture, or Component
artifact outside this target directory is a deletion target.

## Decision

Add this package-local Cargo development profile:

```toml
[profile.dev]
debug = 0
incremental = false
```

Then run exactly:

```bash
cargo clean --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
```

`debug = 0` removes native debug information from this runner package and its
development dependencies. `incremental = false` stops generating per-binary
incremental compilation files. Cargo may retain an empty root `incremental`
directory. Both settings apply only when Cargo is invoked with this manifest in
the normal development profile; they do not change generated Wasm, Component
ABI, WIT ownership, runner source semantics, or another project's Cargo
profile.

`cargo clean` deletes only Cargo-generated files below the target directory
resolved from this manifest. The immediate cost is a cold rebuild on the next
runner invocation. Native source-level debugging of these runner executables
will not have debug symbols until this profile is changed back.

## Verified Result

The target resolved by Cargo remained
`/home/_/._/do/examples/p3-runtime/rust-host-runner/target` throughout the
operation. Before cleanup, `du -sb` measured `138188136313` bytes (130GB).
The confirmed `cargo clean --manifest-path` command removed 132,231 generated
files (Cargo logical total 148.8GiB); immediately afterward the target
directory was absent.

The existing private Component/Rust runtime gate rebuilt from cold:

```bash
TMPDIR="$PWD/.tmp/do-tmp" \
  bash examples/p3-runtime/test_variant_resource_stream_abi.sh
```

It passed all eight modes. Immediately after that cold rebuild, the local
target measured `682365211` bytes (655MB). After the remaining verification
commands completed, the target reached its stable size of `785060069` bytes
(753MB), a reduction of `137403076244` bytes from the pre-clean measurement.
Running the same gate again left that stable size unchanged (`delta=0`). The
rebuilt `do-p3-variant-resource-stream-abi` executable is `37191512` bytes
(35MB), has no `.debug_*` ELF sections, and the retained
`target/debug/incremental` directory contains zero files (4KB directory
metadata only). No file outside the runner-local target directory was deleted.

## Rejected Alternatives

| Alternative | Decision | Reason |
| --- | --- | --- |
| Run `cargo clean` only | rejected | Frees space once, but leaves debug information and incremental caches enabled so the same target regrows. |
| Set a shared `CARGO_TARGET_DIR` | rejected | Moves rather than reduces usage, and existing scripts invoke runner binaries from the current `target/debug` location. |
| Convert all runner scripts to `--release` | rejected | Requires broad script/path migration and changes test iteration behavior without evidence that it is needed. |

## Verification And Stop Conditions

Record `du -sh examples/p3-runtime/rust-host-runner/target` before and after
the clean. After the clean, run the private variant-owned-ticket Component gate:

```bash
TMPDIR="$PWD/.tmp/do-tmp" \
  bash examples/p3-runtime/test_variant_resource_stream_abi.sh
```

The gate must rebuild the required runner and pass its Component/Rust runtime
matrix. Confirm that `cargo metadata` still resolves only the runner-local
target directory and that no file outside it was removed. Stop and report if
Cargo resolves a different target path or the runtime gate fails; do not widen
the cleanup target or alter unrelated scripts.
