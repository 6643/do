# Generic ABI v2 Promotion Profile Design

**Status:** approved for implementation planning.

**Goal:** expose the two independently verified private Generic ABI v2
Component shapes through one deliberate runtime profile, while preserving the
existing v1 default dispatch and rejecting every other target before WAT
emission.

## Scope

The profile is invoked as:

```text
do build <input.do> --p3-async-component-v2 --p3-wit-output <output.wit> -o <output.wat>
```

It recognizes exactly these source/registry identities:

1. `do:variant-resource-stream-canonical@0.1.0`,
   `read-via-stream`, with the pinned `ticket | idle | failed(error-code)`
   event layout.
2. Generated `do:generic-async-scalar-i64-probe@0.1.0`, `host.completion`,
   with the validated `Future<i64>` manifest payload facts: `offset=16`,
   `byte_size=8`, `alignment=8`, and `core-s64`.

The profile dispatches the first identity to the variant v2 adapter and the
second to the scalar-i64 v2 adapter. The adapter constructors remain the
authority for layout, ownership, async transition, and manifest validation.

## Non-goals

- Do not switch `--p3-async-component` to v2. It remains the v1 registry
  dispatch path.
- Do not admit scalar-u32, unit, HTTP, filesystem, generic producer,
  arbitrary payload, resource, list, text, Stream, or unmeasured ABI shapes.
- Do not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- Do not reinterpret nested `borrow<T>` support; pinned `wasm-tools 1.254.0`
  still rejects borrowed stream/future shapes.
- Do not add cancellation rollback or external-network tests.

## Profile Contract

`--p3-async-component-v2` is a mutually exclusive P3 Component target. It
cannot be combined with `--p3-async-component`, the legacy private
`--p3-async-v2-scalar-i64`, other special targets, `--component-core`, or
`--host-export`. The legacy scalar flag remains temporarily supported as the
single-shape compatibility entrypoint; both paths render the same scalar v2
artifact for the exact scalar-i64 input.

The new profile uses the existing `emit_p3_async_component_wit` route. This is
safe because both admitted identities already have their WIT sidecar selected
by the same pinned target analysis.

Target selection is fail-closed. The profile first classifies the full source
with the existing registry and generated-manifest graph, then accepts only the
two identities above. Any other target returns a named v2 promotion diagnostic
before WAT output is created. It never falls back to v1 and never uses a
descriptor name alone as evidence.

## Data Flow

```text
CLI profile
  -> EmitOptions.p3_async_component_v2
  -> emit_component_wat_v2
  -> target_for_tokens_with_graph
  -> exact variant v2 adapter | exact scalar-i64 v2 adapter
  -> existing Component WIT sidecar emitter
```

The dispatch function is deliberately separate from `emit_component_wat`, so
the default v1 path cannot change accidentally. It accepts `program`, `tokens`,
and `module_graph`; generated manifest drift therefore continues to fail during
graph loading or scalar adapter analysis before an artifact is emitted.

## Verification

Unit coverage proves all of the following:

- the CLI accepts the v2 profile and rejects mixed targets;
- v2 dispatch chooses the independent variant template for the exact private
  resource-stream descriptor;
- v2 dispatch chooses the independent scalar-i64 template for the exact
  generated manifest;
- v1 dispatch remains byte-for-byte on its existing route;
- scalar-u32 and an unrelated registered v1 target fail closed through the
  v2 profile.

Runtime coverage runs the existing variant ticket/idle/failed/pending/error
matrix and scalar-i64 ready/pending/cancel matrix through the new profile, then
checks WAT parse/embed/new/validate and exact Rust/Wasmtime cleanup counts. A
manifest payload mutation must still fail before a WAT file exists.

## Promotion Boundary

This closes only the registry/runtime promotion checkpoint for these two
private shapes. It is not generic WIT lowering. Borrowed stream/future
re-evaluation and generic producer/payload expansion remain independent open
work with their own pinned WIT, layout, ownership, and runtime gates.
