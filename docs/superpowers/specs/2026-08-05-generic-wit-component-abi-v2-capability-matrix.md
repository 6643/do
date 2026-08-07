# Generic WIT/Component ABI v2 Capability Matrix

This matrix records what the current pinned `wasm-tools 1.255.0` toolchain can
accept without adding a Do compiler registry entry. It is a capability probe,
not a claim that Do source or the generic Component emitter supports these
shapes. The earlier 1.254.0 result remains a historical comparison in the
pending boundary record.

## Toolchain

- `wasm-tools 1.255.0 (76e20611d 2026-07-30)`
- Probe: `bash examples/p3-runtime/test_borrow_capability_matrix.sh`
- The script uses an empty valid Core module so the result isolates WIT
  Component embedding and does not depend on a host implementation.

## Results

| Shape | Minimal WIT value | Pinned result |
| --- | --- | --- |
| direct borrow | `borrow-value: func(ticket: borrow<ticket>) -> u32` | `component embed` and `component new` accepted |
| borrowed record | `record entry { ticket: borrow<ticket> }` | `component embed` and `component new` accepted |
| borrowed variant | `variant maybe-ticket { ticket(borrow<ticket>), none }` | `component embed` and `component new` accepted |
| borrowed list | `list<borrow<ticket>>` | `component embed` and `component new` accepted |
| owned future | `future<own<ticket>>` | `component embed` and `component new` accepted |
| owned stream record | `stream<record { ticket: own<ticket> }>` | `component embed` and `component new` accepted |
| borrowed stream record | `stream<record { ticket: borrow<ticket> }>` | rejected during `component embed` |
| borrowed future | `future<borrow<ticket>>` | rejected during `component embed` |

The two rejected shapes must contain the exact diagnostic:

```text
contains a `borrow<T>` which is not supported
```

The accepted rows prove only that the pinned toolchain can represent and
assemble the WIT shape. This includes the two owned async rows, but it does not
prove canonical async frame layout, transfer/drop behavior, Do ownership
semantics, resource cleanup, or Wasmtime host execution.

## Boundary

The direct, record, variant, list, owned future, and owned stream rows remain
outside the current Do compiler registry until each has a separate measured ABI
descriptor, source admission rule, ownership plan, negative fixtures, and
Component/Rust/Wasmtime cleanup gate. The borrowed stream and future rows
remain explicitly blocked by the pinned toolchain. A toolchain upgrade or a
new canonical WIT shape must rerun this matrix before either rejected row can
enter the registry.
