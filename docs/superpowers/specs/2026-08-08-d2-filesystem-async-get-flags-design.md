# D2 `descriptor.get-flags` Async Probe

## Scope

This is a private ABI and runtime probe for one no-resource-payload WASI
filesystem method. It does not add a registry row, semantic admission, codegen
branch, public `own<T>`/`borrow<T>`/`ref<T>` syntax, or general filesystem async
lowering.

The only method under test is:

```wit
descriptor.get-flags: async func() -> result<descriptor-flags, error-code>
```

The probe world imports an owned `descriptor` and exports one async `run`
operation. The descriptor is created by the Rust host from a temporary file or
directory. The host implementation returns a fixed flags value, `no-entry` for
the error path, and a controlled pending future for the cancellation path.

## ABI Gate

The hand-written Core module is admitted only after both pinned toolchains
produce compatible metadata for the same WIT snapshot:

- current `wasm-tools 1.255.0` (hash
  `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`),
- legacy `wasm-tools 1.254.0` (hash
  `cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6`).

The gate records the upstream filesystem source hash, the WIT mirror hash, the
`[async-lower][method]descriptor.get-flags` Core signature, the task completion
signature, the result variant tag/payload encoding, the descriptor drop import,
and the async lift/callback exports. The six-flag value is one byte in the
canonical result area (tag at byte 0, payload at byte 1) and one promoted i32
word in the flat `task.return` signature. The Core WAT must parse, assemble,
and validate with `cm-async,cm-more-async-builtins` on both toolchains.

The probe must not infer the flags encoding from a Do source type. It uses only
the measured Component metadata and keeps result storage and cleanup explicit.

## Runtime Gate

The Rust/Wasmtime runner exercises four modes:

| Mode | Host completion | Result | Required cleanup |
| --- | --- | --- | --- |
| `ready` | immediate | `Ok(read|write)` | one future drop, one descriptor drop, empty table |
| `pending` | one external wake | `Ok(read|write)` | one future drop, one descriptor drop, empty table |
| `error` | immediate | `Err(no-entry)` | one future drop, one descriptor drop, empty table |
| `cancel` | never ready, then subtask cancel | no result | one pending future drop, one descriptor drop, empty table |

Cancellation only releases live Component resources. It never rolls back an
external filesystem effect; this method is observational and issues no mutation.

## Promotion Rule

Only a green ABI and runtime gate can authorize a separate Task 5 design for a
private registry/codegen adapter. A pinned rejection, unstable result layout,
or duplicate/missing cleanup is an explicit no-go and leaves the current
`get-type` and `sync` adapters unchanged.
