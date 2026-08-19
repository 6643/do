# Generic WIT/Component ABI v2 Design

**Status:** design approved for planning; no v1 lowering changes in this phase.

**Goal:** build a reusable internal ABI and ownership model so Do can grow from
descriptor-specific WIT slices to generic WIT/Component support without
changing the stable v1 source contract or deleting the existing runtime gates.

## Scope

The target is a generic internal model for WIT/Component values and lifetimes:

- scalar, tuple, record, option, result, variant, list, and text values;
- resource handles with `own` transfer and direct-call `borrow` use;
- canonical layout facts such as tag, payload, size, alignment, indirection,
  and `cabi_realloc` ownership;
- future/stream endpoint operations, terminal states, and exactly-once
  cleanup plans.

This phase does not promise complete WASI 0.3 service coverage. Service
coverage remains a later matrix built on this ABI layer.

## Non-goals

- no public `own<T>`, `borrow<T>`, or `ref<T>` syntax;
- no replacement of the v1 emitter or default `do build` path;
- no silent lowering of an unmeasured WIT shape;
- no rollback or compensation behavior for cancellation;
- no external-network runtime fixtures;
- no assumption that a pinned toolchain accepts borrowed fields inside
  `stream`, `future`, `list`, `record`, or `variant` values.

## Architecture

The new path is an internal planning pipeline with explicit boundaries:

1. `AbiType` describes the logical WIT shape independently of source syntax.
2. `LayoutPlan` records measured canonical ABI facts and indirect allocation
   operations. It is immutable after validation.
3. `OwnershipPlan` records move, borrow, release, and scope/async liveness
   actions. Every owned resource has one release authority.
4. `AsyncPlan` records future/stream poll, pending, ready, error, cancellation,
   and endpoint-drop transitions.
5. Existing descriptor emitters consume adapters from these plans during
   migration. They remain the ABI oracles until the generic path passes the
   same gates.

The first modules are pure Zig data and validation helpers:

- `src/build/wit_abi_types.zig`
- `src/build/wit_abi_layout.zig`
- `src/build/wit_abi_ownership.zig`
- `src/build/wit_abi_async.zig`

The existing `p3_async_registry.json` remains the source of pinned facts during
the migration. It is not replaced by inference from a source signature.

## Borrow boundary

The pinned environment is Zig `0.16.0`, Rust `1.97.1`, `wasm-tools 1.254.0`,
and Wasmtime `47.0.2`. Direct function parameters containing `borrow<T>` are
already verified. The same toolchain rejects a `borrow<T>` nested in a stream
record during `wasm-tools component embed`, so that shape remains an explicit
capability gate. The compiler must not work around this by exposing public
borrow syntax or by converting a borrow into an own silently.

The capability matrix will distinguish direct borrow support from nested
borrow rejection. A toolchain upgrade invalidates the old matrix and requires
all affected Component and Rust/Wasmtime gates to be rerun.

## Migration order

1. Record the current v1 regression and all pinned capability probes.
2. Add and test the pure `AbiType` and `LayoutPlan` model without changing
   lowering.
3. Add `OwnershipPlan` for scalar resources, `own` transfer, and direct-call
   `borrow`; keep nested borrowed values rejected.
4. Add `AsyncPlan` for the already admitted future/stream terminal matrix.
5. Migrate one existing private descriptor at a time, comparing generated WAT
   and runtime cleanup with the old emitter.
6. Only after multiple descriptors are green may the generic path become the
   default for those descriptors.

## Acceptance and stop conditions

The phase is successful only when the new plans can reproduce existing pinned
layout and cleanup facts without changing their values. Every migrated shape
needs positive and negative source fixtures, Core WAT markers, Component
validation, Rust/Wasmtime pending/ready/error/early-drop coverage, and exact
resource/stream/future drop counts.

If a WIT shape lacks a pinned layout, a valid ownership proof, or toolchain
support, it remains rejected with an explicit diagnostic and does not enter the
generic registry.
