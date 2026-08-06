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
