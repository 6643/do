# Generated Async Manifest Lowering Design

**Status:** proposed, design-approved

**Date:** 2026-08-06

## Goal

Connect one generated WIT async binding to the existing colorless async
Component runtime without making arbitrary WIT async functions executable.
The first admitted shape is a private, unit-payload operation:

```wit
interface host {
  work: async func();
}
```

The generated Do declaration remains an ordinary host binding. The caller uses
the already admitted three-operation runtime shape so this design does not
silently expand the generic analyzer:

```do
work = @host("do:generic-async-runtime-probe/host@0.1.0", "work", () -> Future<nil>)

run() -> nil {
    first Future<nil> = work()
    @await(first)
    second Future<nil> = work()
    @await(second)
    cancelled Future<nil> = work()
    @cancel(cancelled)
}
```

The generated binding never uses `async name(...) -> T`, and callers never
wrap an already-async binding in `@async`.

## Current Evidence

The repository already has these independent facts:

- `do wit check/bind` parses WIT, resolves worlds, emits flat Do modules,
  `manifest.json`, and `wit.lock`.
- Generated module hashes, package/world identity, host signatures, and
  async/future/stream/resource effects are validated before import admission.
- The private descriptor
  `do:generic-async-runtime-probe/host@0.1.0::work` has pinned
  `[async-lower]work` and `task-return` metadata.
- The descriptor-backed generic runtime has real pending, ready, and cancel
  Component/Rust/Wasmtime gates.
- Generic payload, Stream, resource, arbitrary producer, `own<T>`, `borrow<T>`,
  and `ref<T>` lowering remain rejected.

This design links those facts; it does not claim that WIT metadata alone proves
runtime support.

## Alternatives

### A: Explicit manifest lowering capability (recommended)

Add a versioned lowering record to generated metadata. The compiler consumes
that record only for a named capability whose ABI has a pinned probe. This
keeps WIT identity, source signature, canonical import names, and runtime
admission in one checked contract.

### B: Infer canonical imports from the host locator

The compiler would derive `[async-lower]member` and the completion protocol from
the locator and function name. This is rejected: a locator is source identity,
not evidence that a runtime implements a particular Component ABI.

### C: Translate upstream Rust/Go generated source

The production compiler would parse a second backend's generated source to find
async imports. This is rejected: helper names and layout are backend details,
Cargo/toolchain availability would become a production dependency, and source
translation would duplicate the Zig WIT model.

## Manifest Contract

Metadata-only generated bindings continue to use manifest schema 1. A binding
with an executable lowering capability uses schema 2 so an older reader cannot
silently ignore required runtime facts.

Schema 2 adds an `async_lowerings` array. Each entry contains:

| Field | Contract |
| --- | --- |
| `capability` | Exactly `component-async-unit-v1` for this phase |
| `member` | The generated member locator, such as `host.work` |
| `source_signature` | Canonical Do signature, exactly `() -> Future<nil>` |
| `wit_package` | Fully qualified WIT package identity |
| `wit_world` | Resolved world name |
| `wit_interface` | Resolved interface name |
| `wit_member` | WIT operation name |
| `async_import_module` | Pinned Component core import module |
| `async_import_name` | Pinned `[async-lower]work` import name |
| `completion` | Exactly `task-return` |
| `wit_sha256` | Hash of the source WIT model used for the binding |

The lowering entry must reference an `async` member with no parameters, no
resource, no Stream, no nested future, and a unit result. A schema 2 manifest
with any other shape is invalid for this capability; it is not downgraded to a
synchronous host import.

`do wit check --manifest` validates both schema versions. Schema 2 validation
also checks that every lowering entry maps to one manifest member, that the
member signature/effect agrees, and that the generated module hash and WIT hash
match the input. Unknown capabilities are rejected before any Do source is
admitted.

## Compiler Data Flow

```text
WIT source
  -> BindingModel
  -> generated Do module + manifest schema 2
  -> import resolver validates module/hash/signature/effect/lowering
  -> generic async admission consumes ManifestAsyncDescriptor
  -> existing unit-payload Component runtime emitter
```

The resolver produces an immutable `ManifestAsyncDescriptor` containing only
the fields needed by the generic async analyzer. The analyzer remains
responsible for the existing source-shape checks: ordinary root function, three
distinct Future bindings, two sequential `@await` operations, one terminal
`@cancel`, and no extra async operation. The emitter does not parse manifest
JSON or infer ABI names; it receives the validated descriptor and reuses the
existing descriptor-backed runtime template.

The existing pinned P3 registry remains the source for descriptor-specific
WASI lowering. Generated manifest capabilities are an additional admission
path for this one unit shape, not a replacement for the registry and not a
general host-import escape hatch.

## Runtime Gate

Add a generated version of the private generic runtime probe. The gate must:

1. run `do wit bind` from the WIT source into a temporary `wit/` directory;
2. validate the schema 2 manifest and generated module hashes;
3. compile a caller using the generated `work` binding;
4. componentize with pinned `wasm-tools 1.254.0`;
5. run the existing Rust/Wasmtime host in pending, immediate, and cancel modes;
6. observe the same exactly-once terminal cleanup markers as the current
   descriptor probe.

The positive gate proves metadata-driven admission and runtime behavior
together. A standalone WAT marker check is insufficient.

## Negative Boundaries

Each case must fail before WAT emission with a named diagnostic:

- missing sibling manifest;
- schema 2 lowering entry removed or unknown capability;
- module hash, WIT hash, package/world/member, effect, or signature drift;
- changed Core async import or completion name;
- async operation with a parameter or non-unit payload;
- `future<T>`, `stream<T>`, resource, borrowed field, or nested future;
- a second active Future, aggregate await, branch/loop await, or async root
  declaration;
- generated custom host locator without the pinned capability.

Existing schema 1 metadata-only bindings and existing pinned WASI descriptors
must retain their current behavior.

## Non-goals

This phase does not add public `own<T>`, `borrow<T>`, or `ref<T>`, does not
implement arbitrary WIT async lowering, does not infer rollback or cancellation
semantics, and does not change the rule that cancellation observes terminal ABI
state without rolling back external side effects.

## Acceptance Criteria

- Schema 1 and schema 2 manifest unit tests pass.
- Positive generated unit-async Component/Rust/Wasmtime gate passes in all
  pending/ready/cancel modes.
- Every listed drift and unsupported-shape fixture is rejected before codegen.
- Existing compiler, WIT, Component, Rust/Wasmtime, and ReleaseSmall matrices
  remain green.
- Documentation states that this is a bounded capability and retains all
  current generic async and G6.2 residual boundaries.
