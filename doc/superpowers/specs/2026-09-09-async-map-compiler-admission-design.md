# Private Async Map Compiler Admission

Date: 2026-09-09
Status: approved bounded promotion; implementation and verification complete

## Goal

Promote exactly one measured WIT async map shape into an opt-in compiler route:

```wit
submit: async func(values: map<u32, u32>) -> u32;
```

The route is private and fail-closed. It does not change ordinary GC-only
compilation, the existing synchronous map route, or generic async lowering.

## Source Contract

The accepted Do fixture is
`examples/p3-runtime/async-map-component.do`. It uses the existing
`HashMap<K,V>` library representation, constructs exactly two pairs `[7,70]`
and `[9,90]`, calls one registered `@host_async_func`, and awaits through one
helper and one root task. The helper and root both return `u32`; no `start`
entry, branch, loop, second child, dynamic map, or second host operation is
admitted.

The analyzer matches tokens and the pinned descriptor. It does not infer an ABI
from the host name or from a structural map type. Any changed alias, map key or
value, pair count, literal, operation count, async declaration, ownership
syntax, or producer expression returns `UnsupportedP3AsyncMapComponent` before
WAT emission.

## Pinned Descriptor And ABI

The descriptor is added to `src/build/p3_async_registry.json` and validated by
`p3_async_manifest.zig`:

```text
locator: demo:map-async-probe/api@0.1.0
member: submit
effect: async-map-u32-u32
params: [HashMap<u32,u32>]
result: u32
WIT: demo:map-async-probe@0.1.0 / api.submit / probe / values
WIT hash: 821f5a1d20b600284efca10ad78f16e64d3ca5f42df566d4f045ef5b5348d3a0
Core import: (i32 ptr, i32 len, i32 result_area) -> i32
completion: task-return(i32)
async import: demo:map-async-probe/api@0.1.0 [async-lower]submit
```

`ptr,len` address a temporary pair-list with two eight-byte entries. The
temporary is valid only for the host call and is overwritten immediately after
the call returns. The frame result slot is independent of that temporary.

```mermaid
flowchart LR
    Source[HashMap<u32,u32> fixture] --> Plan[Strict token + descriptor plan]
    Plan --> Copy[Pair-list copy before host call]
    Copy --> Host[async host submit(ptr,len,result_area)]
    Host --> Frame[Root GC frame + waitable/subtask state]
    Frame --> Terminal[ready / pending / cancel / drop cleanup]
```

## Compiler Boundary

The CLI flag is `--p3-async-map-component`. It is mutually exclusive with all
other special targets, `--component-core`, and `--host-export`. The route emits
the checked-in WIT shape and the measured canonical Core WAT template. The
normal target still returns `AsyncLoweringUnavailable` for the fixture.

The implementation is isolated in:

- `codegen_component_async_map_plan.zig`: descriptor lookup and source facts;
- `codegen_component_async_map.zig`: fixed WAT/WIT emission;
- `async_map_component_template.wat`: canonical frame/copy/cleanup template.

No public `own<T>`, `borrow<T>`, `ref<T>`, lifetime, pointer, or reference
syntax is introduced. No generic `map<K,V>`, text/list/resource/variant map,
Stream map buffer, or arbitrary producer is accepted.

## Lifecycle And Verification

The route reuses the existing async-map capability WIT/Rust/Wasmtime gate. The
compiler gate must additionally prove:

1. generated WIT and WAT match the pinned snapshots;
2. Core parse, Component embed/new/validate, and current toolchain checks pass;
3. host input copy occurs before the async call and the overwrite occurs after;
4. result-area copy and root task-return use the measured `u32` slot;
5. ready/pending/cancel/drop each free the frame once and leave an empty
   `ResourceTable`;
6. the default build rejects the same source and negative shapes fail before
   WAT.

Rollback is limited to the new flag, descriptor, plan/emitter/template,
fixture, focused tests, harness case, and this document. Existing synchronous
map, async scalar, resource, and GC routes remain untouched.
