# Async Runtime Baseline (2026-08-05)

## Scope

This is the Task 8 Step 3 runtime baseline for the already admitted
descriptor-specific Component slices. It is an independent release gate for
the generic async lowering plan; it does not make arbitrary `Future<T>`,
`Stream<T>`, resource, or async function shapes lowerable.

## Command and Toolchain

```text
bash examples/p3-runtime/test_task8_step3_baseline.sh
```

Observed toolchain:

| Tool | Version |
| --- | --- |
| Zig | 0.16.0 |
| wasm-tools | 1.254.0 (`bb58fdf91`, 2026-07-20) |
| Wasmtime | 47.0.2 (`90fed3c6a`, 2026-07-21) |
| Rust | 1.97.1 (`8bab26f4f`, 2026-07-14) |

## Gate Results

| Gate | Result | Evidence | Unblock condition |
| --- | --- | --- | --- |
| `cancel-wait-for` | PASS | Rust/Wasmtime pending and immediate cancellation; one terminal cleanup | Keep the pinned cancellation ABI and exactly-once cleanup assertions green |
| `scalar-result` | PASS | `Result<i32, i32>` pending/ready/error path and no rollback marker | Narrow/unsigned task-return payloads remain a separate pinned-toolchain limitation |
| `resource-result` | PASS | Pending, immediate `Ok`, ready `Err`, and empty `ResourceTable` | Do not generalize private resource result layout without a new descriptor gate |
| `stream-reader` | PASS | Registered stream reader Component and Rust host execution | Additional stream producers/shapes require independent admission and cleanup evidence |
| `stream-writer` | PASS | CLI stdout writer Component and Rust/Wasmtime adapter | General producer expressions and broader writer shapes remain rejected |
| `filesystem` | PASS | Filesystem preopen Component/Rust host smoke | General filesystem async methods remain outside this baseline |
| `sockets` | PASS | TCP and UDP loopback create/bind/drop smoke, including create/bind failures and empty resource table | D2 remains in progress for broader WASI networking/async coverage |

The first run exposed a stale `types.wit` SHA-256 constant in
`src/build/p3_sockets_wit_manifest.zig`; the checked-in WIT source had only
whitespace normalization relative to the recorded source. Updating the
constant to the current source hash (`02be1588...f37b1d88`) restored the
socket gate. The socket unit suite then passed `36/36`, and the complete
baseline passed all seven gates.

## Boundary

`AsyncLoweringUnavailable` remains the ordinary `do build` guard for generic
async source shapes. This report proves the existing descriptor-specific
runtime slices only; it is not evidence for the generic resumable lowering
planned in `docs/superpowers/plans/2026-08-05-generic-async-lowering.md`.
