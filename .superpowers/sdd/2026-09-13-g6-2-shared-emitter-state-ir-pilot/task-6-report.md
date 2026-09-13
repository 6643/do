# Task 6 Gate Report

Date: 2026-09-13
Scope: private single-route G6.2 shared emitter/state-IR pilot

## Toolchain

- Zig: `0.16.0`
- wasm-tools: `1.258.0 (5c6d31c78 2026-08-24)`
- Wasmtime: `48.0.1 (7bac2c277 2026-08-24)`

All Zig commands used repository-local cache directories under
`.tmp/task-6-evidence/`.

## Gate Results

| Gate | Command/result | Status |
| --- | --- | --- |
| Zig unit | `(cd src && ... zig test main.zig)`; `1717/1717` passed | PASS |
| Release build | `(cd src && ... zig build -Doptimize=ReleaseSmall)`; exit 0 | PASS |
| Full regression | `./src/build/test/run_tests.sh`; harness `53/53` passed, overall exit 1 | BLOCKED |
| Release smoke | `./src/build/test/run_release_smoke.sh`; all smoke rows passed | PASS |
| Diff check | `git diff --check`; exit 0 | PASS |
| Component artifact | parse/embed/new/validate with current wasm-tools; all exit 0 | PASS |
| Direct runtime gate | existing Do Component gate; exit 0 | PASS |
| Rust/Wasmtime lifecycle | local-cache rerun, 10 rows; all assertions passed | PASS |
| Default/rollback | WAT/WIT byte parity, focused tests, old route gate | PASS |

## Artifact Evidence

The source `examples/p3-runtime/g6-2-owned-record-producer.do` was built into a
temporary directory with `--p3-async-component --p3-wit-output`. The generated
WIT matched `examples/p3-runtime/wit/g6-2-owned-record-producer.wit` and had
SHA-256 `6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace`.
The WAT matched `examples/p3-runtime/g6-2-owned-record-producer-canonical.wat`
and had SHA-256
`095da7cd4c131a7318fc4bf5fd87b2d99e2672bff568edc577a553e228f856c5`.

Commands were:

```text
wasm-tools parse pilot.wat -o core.wasm                 exit 0
wasm-tools component embed pilot.wit core.wasm          exit 0
wasm-tools component new embedded.wasm -o component.wasm exit 0
wasm-tools validate --features cm-async,cm-more-async-builtins component.wasm exit 0
```

The WAT had no `__arc_` marker and no canonical-boundary GC reference from the
pilot guard scan.

## Lifecycle Evidence

`test_rust_g6_2_owned_record_producer.sh` and
`test_g6_2_owned_record_producer_equivalence.sh` passed ready, pending,
sink-error-before/after, cancel-before/after-transfer,
early-drop-before/after-transfer, repeat and invalid. Each row reported
`table-empty=true`; resource, stream and future cleanup were exactly once, with
repeat exactly twice. The equivalence runner reported
`canonical/generated direct owned-record producer equivalence passed modes=10`
and `resources=1/1 drops=1/1`.

The first Rust attempt failed before execution while `zig-cc.sh` used the
default `/home/_/.cache/zig`; the linker reported missing `Scrt1.o`, libc and
runtime archives. This is environment evidence. Re-running with repository-local
`ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` passed; no runtime failure is
hidden by that retry.

## Regression Failure Classification

`run_tests.sh` output ended with `Build Summary: 12/14 steps succeeded (1
failed); 53/53 tests passed`. The failed integration case was
`GC ARC inventory`. Its retained stderr was:

```text
unclassified ARC reference: src/build/codegen_component_producer_emitter_test.zig:163: ... "__arc_"
unclassified ARC reference: src/build/codegen_component_producer_emitter.zig:57: ... "__arc_"
unclassified ARC reference: src/build/codegen_component_producer_emitter.zig:58: ... "__arc_"
```

Classification: source/inventory gate mismatch, not environment. The new
production guard intentionally rejects the marker, while the inventory scanner
requires every matching source reference to be classified. Task 6 does not
modify `doc/gc_arc_inventory.tsv` or the production emitter; changing only the
permitted emitter test file would leave the production references unclassified.
This remains an acceptance concern and is not represented as a green full
regression result.

## Scope and Rollback

The ordinary route remains on the old emitter. Pilot admission failures returned
named errors and did not accept a fallback output. Old producer focused tests
(`15/15`) and pilot focused tests (`13/13`) passed. WAT/WIT byte parity and the
capability inventory diff were clean. No route promotion, capability inventory
update, public ownership syntax, or generic/arbitrary producer work was done.

Deferred: 12-route migration, generic/arbitrary producers, public ownership
syntax, semantic-parity rewrite and D2 general async. The state-IR probe is not
a substitute for runtime equivalence.
