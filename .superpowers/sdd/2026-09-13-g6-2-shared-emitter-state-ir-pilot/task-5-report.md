# Task 5 Report: Shared Emitter Pilot

Date: 2026-09-13
Scope: direct owned-record producer route only

## Status

Implemented the private-by-convention `emit_component_wat_pilot` adapter and
shared `emit_pilot_wat` emitter. The default `emit_component_wat` and
`emit_component_wit` paths remain unchanged, and no CLI dispatch was added.

## TDD Evidence

1. RED: before implementation, the required pilot command failed because
   `codegen_component_producer_emitter.zig` did not exist. The test module was
   then corrected for Zig 0.16's redundant top-level `comptime` diagnostic.
2. GREEN: after the emitter and adapter were added, the pilot filter passed
   11/11 tests.
3. Regression: the old producer filter passed 15/15 tests after importing the
   direct producer module in the test root. This makes the existing exact-source
   and negative admission tests execute under the requested filter.

## Implemented Gates

- Direct route identity is fixed to `owned-record-direct` and
  `do:g6-2-owned-record-producer@0.1.0`.
- The descriptor hash must be non-empty and equal to the contract hash.
- Source, sink, record payload, ownership, list, and runtime shape checks are
  restricted to the measured direct route.
- `RouteFrameFacts` are borrowed from the existing direct mapping entry; the
  adapter supplies the plan descriptor identity.
- The emitter constructs `FrameMapInput`, `CanonicalFrameMap`, and
  `LifecycleStateIR` in fail-closed order before fragment assembly.
- The route template is represented by five explicit prefix/payload/lifecycle/
  metadata/suffix spans with marker coverage. The adapter passes the immutable
  template as the assembly source and golden bytes as the parity oracle.
- ARC runtime markers and GC reference type tokens are rejected before parity
  success. Temporary assembled output is freed on every rejection path.
- Pilot failures return explicit `PilotError` values and never call the old
  emitter as a fallback.

## Focused Verification

Focused test commands were run from `src/` with the repository-local Zig
caches. Formatting and repository checks were run from the repository root:

```text
TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer shared emitter pilot"
=> All 11 tests passed.

TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "owned record producer"
=> All 15 tests passed.

zig fmt --check src/build/codegen_component_producer_emitter.zig src/build/codegen_component_producer_emitter_test.zig src/build/codegen_component_owned_record_stream_producer.zig src/main.zig
=> an initial attempt from `src/` with root-prefixed paths failed with exit 1
   (`FileNotFound`); the corrected root-directory command exited 0.

git diff --check
=> exit 0
```

## Residual Boundary

The full compiler/integration harness, `wasm-tools` Component validation, and
Rust/Wasmtime lifecycle matrix were not run in this focused task. Default route
promotion is intentionally not implemented. `PilotFacts.template_wat` is an
optional compatibility field that keeps the public shape usable for standalone
callers while allowing the adapter to keep canonical source bytes separate
from the golden parity bytes.
