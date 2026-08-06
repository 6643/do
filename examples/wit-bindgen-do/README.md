# WIT Bindgen Differential Probe

This probe fixes one WIT world and compares the pinned upstream Go and Rust
generators with the Do binding design. The upstream checkout is kept at
`.deps/wit-bindgen` and must be `v0.60.0` at commit
`1ae00530221542369d0e47ee4a1f4232f09d978d`.

Bootstrap the ignored reference checkout once from the repository root:

```bash
mkdir -p .deps
git clone --branch v0.60.0 --depth 1 \
  git@github.com:bytecodealliance/wit-bindgen.git .deps/wit-bindgen
git -C .deps/wit-bindgen checkout --detach \
  1ae00530221542369d0e47ee4a1f4232f09d978d
```

To refresh an existing checkout, run `git -C .deps/wit-bindgen fetch --tags
origin` and repeat the detached checkout. The probe does not update or replace
the checkout automatically.

Run:

```bash
bash examples/wit-bindgen-do/run_differential.sh
```

The probe records stable API and ABI markers only. WIT remains the source of
truth for the Do translation; Go and Rust output is differential evidence, not
production input. It does not claim that either runtime is the Do runtime, and
cancellation remains a runtime terminal protocol rather than a WIT member.

## Generated async binding gate

`generic-async-runtime.wit` is the private, pinned unit-async world admitted by
the current generated binding contract. Run:

```bash
bash examples/wit-bindgen-do/test_generated_async_lowering.sh
```

The gate generates `wit/*.do` plus a schema 2 manifest, imports the generated
`work` binding from `project/generic_async_main.do`, assembles and validates a
Component, and runs the pinned Rust/Wasmtime host in pending, immediate, and
cancel modes. The manifest capability is exactly
`component-async-unit-v1`; module/WIT hashes, source signature, async import,
completion, and capability drift are rejected before WAT emission.

This is a bounded runtime proof for one zero-parameter `async func()` member.
Payloads, streams, resources, aggregate await, and general generated WIT
async lowering remain outside the admitted surface.

## Generated async scalar binding gate

`test_generated_async_scalar_lowering.sh` exercises the second private,
descriptor-backed generated capability: `do:generic-async-scalar-probe@0.1.0`
`host.completion: func() -> future<u32>`. The script runs `do wit bind` into a
temporary project-root `wit/`, imports the generated
`./wit/do_generic_async_scalar_probe__host__probe.do` module, validates the
schema 2 scalar payload metadata, assembles a Component, and runs the shared
Rust/Wasmtime host in ready, pending, and cancel modes.

The observed markers are:

```text
mode=ready value=42 polls=2 wakes=0 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true
mode=pending value=42 polls=3 wakes=1 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true
mode=cancel value=42 polls=3 wakes=0 completions=1 future-drops=2 pending-future-drops=1 frame-drops=1 table-empty=true
```

Module/WIT hashes, scalar payload offset/width/alignment/encoding, source
signature, canonical async imports, completion name, and capability drift are
rejected before WAT emission. This remains a bounded scalar shape
(`Future<u32>` and the separately pinned `Future<i64>` companion): generic
`Future<T>`, text/list/record/resource payloads, Stream, aggregate await,
timeout, branching/loops, and unrestricted generated WIT lowering remain
unsupported.

The i64 companion is `do:generic-async-scalar-i64-probe@0.1.0`
`host.completion: func() -> future<s64>`. Its capability is
`component-async-scalar-i64-v1` with package hash
`861990fea33b55fecd08573ef94f4088296b2cb2bca3356813a2d2157251f3ba` and
payload descriptor `offset=16`, `byte-size=8`, `alignment=8`,
`encoding=core-s64`. Run
`bash examples/wit-bindgen-do/test_generated_async_scalar_i64_lowering.sh` to
reproduce generated binding validation, Component assembly, and the same
ready/pending/cancel cleanup matrix.
