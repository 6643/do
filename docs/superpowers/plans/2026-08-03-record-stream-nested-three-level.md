# Three-Level Nested Owned Resource Record Stream Plan

> Historical slice: the four-level follow-up is now the active nested-depth
> boundary, with fifth-level paths still rejected.

## Scope

Implement the bounded `inner -> deep -> deeper -> own<ticket>` record-stream
consumer gate. Do not widen public ownership syntax or admit arbitrary nested
depth.

## Tasks

- [x] Add a failing manifest test for exactly three nested container levels and
  retain a deeper-shape rejection case.
- [x] Raise the manifest depth ceiling to three and add registry acceptance and
  emitter WAT/WIT tests.
- [x] Add the private Do/WIT fixture and Component lowering script.
- [x] Add the Rust/Wasmtime nested-three runtime variant and pending/ready/error
  assertions for exactly-once cleanup.
- [x] Synchronize roadmap/blocker/changelog documentation and run the complete
  focused and repository verification matrix.

## Verification commands

```bash
cd src && zig test build/p3_async_manifest.zig --test-filter 'nested owned resource'
cd src && zig test build/codegen_component_record_stream.zig --test-filter 'three nested owned resource levels'
bash examples/p3-runtime/test_do_record_resource_stream_nested_three_level_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_nested_three_level_probe.sh
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
bash src/build/test/run_release_smoke.sh
```
