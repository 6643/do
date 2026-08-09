# Borrow Capability Refresh Design

Date: 2026-08-09
Status: evidence-only refresh; no compiler promotion

## Goal

Record the current pinned Component-tool capability boundary for borrowed and
owned resource shapes after the inline scalar async-call checkpoint. This
refresh does not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax and does
not add a Do compiler registry entry.

## Pinned Evidence

The probes were run with:

```text
wasm-tools 1.255.0 (76e20611d 2026-07-30)
binary: /home/_/.local/bin/wasm-tools
sha256: 6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013
```

The stable canonical WIT inputs are:

```text
examples/p3-runtime/wit/list-borrow-canonical.wit
sha256: 586e30e439459f23c3f9713998fb92e59ba527b16de331271a2e5fdba33e304e

examples/p3-runtime/wit/future-owned-canonical.wit
sha256: 99e2f7d3b836a0bff011a32d5dd3a48c78805746e514ca65df5ad86e1bca1bd4

examples/p3-runtime/wit/record-resource-stream-borrowed-probe.wit
sha256: c55427d7079644aebc9ff391829f149d7ee0213f4a469328c47161c270575fd0
```

The matrix script generates its eight WIT inputs in a temporary directory;
the script identity and generated-input hashes used for this run are:

```text
examples/p3-runtime/test_borrow_capability_matrix.sh
sha256: 4fa28f6862f31d8cc97dee28e9282f0483e11bfc75b4003d82c7398ab568f983

direct       6ccf0eaa4744b8164666cd1c8bc4becdbdc2ede0b3ffb8a17652fd0575b8db09
record       a15dc63b96427d91d18553ad01382bfa9c0c187a5bbc070a5357b4896e59dde1
variant      e60af4c04336579c2210b2294766d3d273d68bd839865b48053aef78afbc23ef
list         63b4501b3fb323bc49d55bad9efcfa358973ff403bee1d0f16533dcc6b18b33e
future-owned f84c0aff3e8f144ad0c516874d33efa22eea016323ed0d1388cb0ead7ba7a95b
stream-owned ffb500d6e080751a7ecb6d01ff4014f679abdf1362e2322c7c92370fcae43fe5
stream       4a4807982cc9d0941f2d1413d73871d33b9300908f19495a13e950eae5734a52
future       25b546e891b8f85d8feb613f56e7d0b8668f2e96182f98062ac55b8460da994a
```

The two canonical probe scripts are also pinned by source hash:

```text
examples/p3-runtime/test_list_borrow_canonical_abi.sh
sha256: 367bb26a269b25f99ccc31c8deb766b8616a657605ee0e22b5efecc3d8a88d78

examples/p3-runtime/test_future_owned_canonical_abi.sh
sha256: 053ae7983a68b8df50274b11f46127e5c544c72420f0dd1d098bf045c9c7cb0c

examples/p3-runtime/test_do_borrowed_resource_rejection.sh
sha256: 96db7a7ac86e425ad3167d1b0c9af837758078313ef345e484c760c39648fa0a
```

The capability matrix gate was:

```bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 \
  bash examples/p3-runtime/test_borrow_capability_matrix.sh
bash examples/p3-runtime/test_list_borrow_canonical_abi.sh
bash examples/p3-runtime/test_future_owned_canonical_abi.sh
```

All three commands passed. The list probe measured `ptr=64` and a 4-byte
borrowed resource representation; the future-owned probe measured payload
offset `12`, ticket offset `16`, and presence offset `20`, with ready/pending/
cancel cleanup and an empty resource table.

The matrix output was:

```text
direct=accepted
record=accepted
variant=accepted
list=accepted
future-owned=accepted
stream-owned=accepted
stream=rejected-at-embed
future=rejected-at-embed
borrow capability matrix: PASS
```

## Matrix

| Shape | Result | Meaning |
| --- | --- | --- |
| `borrow<ticket>` | accepted | Component tool capability only |
| borrowed record | accepted | Component tool capability only |
| borrowed variant | accepted | Component tool capability only |
| `list<borrow<ticket>>` | accepted | synchronous canonical list probe is green |
| `future<own<ticket>>` | accepted and runtime-probed | existing private future-owned slice only |
| `stream<record { ticket: own<ticket> }>` | accepted by tool | no generic Do promotion |
| `stream<record { ticket: borrow<ticket> }>` | rejected at `component embed` | exact diagnostic: `contains a \`borrow<T>\` which is not supported` |
| `future<borrow<ticket>>` | rejected at `component embed` | exact diagnostic: `contains a \`borrow<T>\` which is not supported` |

For the generated matrix rows, the complete rejection diagnostics (temporary
file paths intentionally omitted) were:

```text
error: function `read` returns a type which contains a `borrow<T>` which is not supported
     --> stream.wit:6:3
      |
    6 |   read: func() -> stream<entry>;
      |   ^---

error: function `read` returns a type which contains a `borrow<T>` which is not supported
     --> future.wit:5:3
      |
    5 |   read: func() -> future<borrow<ticket>>;
      |   ^---
```

The compiler-generated borrowed-resource stream rejection uses the same pinned
diagnostic and points to `read-via-stream` in the checked-in WIT:

```text
error: function `read-via-stream` returns a type which contains a `borrow<T>` which is not supported
     --> record-resource-stream-borrowed-probe.wit:14:3
      |
   14 |   read-via-stream: func() -> tuple<stream<resource-entry>, future<result<_, error-code>>>;
      |   ^--------------
```

## Boundary And Recovery

`list<borrow<T>>` is proven only for the synchronous canonical list call. Its
owner remains live through the call and is dropped once after return. This is
not evidence for a borrowed stream or borrowed future, and it does not imply a
source-level borrow type.

`future<own<T>>` is proven only by the private `Future<Ticket>` compiler/runtime
slice with its measured frame layout. It does not admit generic owned futures or
change the ordinary Do type surface.

The rejected borrowed stream/future rows remain an external toolchain boundary.
Reconsideration requires a newly pinned `wasm-tools` revision whose
`component embed` and `component new` gates accept the exact shape, followed by
a separate canonical WIT/Core-WAT probe, ownership matrix, positive/negative
fixtures, and Component/Rust/Wasmtime cleanup gate. No registry, sema, codegen,
or public ownership change is authorized by this refresh.

## Verification

The existing compiler drift guards also remain green:

```bash
cd src && zig test build/p3_async_manifest.zig
cd ..
bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
```
