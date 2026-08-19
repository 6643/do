# WIT Resource Ownership Design

## Goal

Add the first real Component Model resource ownership path for do: a named
opaque resource can be created, borrowed for one host call, transferred to an
owning host call, and explicitly dropped exactly once. This is a foundation for
HTTP resources, not an HTTP implementation.

## Scope

The initial WIT fixture is a private package,
`do:resource-probe@0.1.0`, with a `ledger` interface and a `ticket` resource.
It exposes four descriptor-bound operations:

```wit
resource ticket {}
create: func(seed: u32) -> own<ticket>;
borrow-value: func(ticket: borrow<ticket>) -> u32;
consume: func(ticket: own<ticket>) -> u32;
```

The Component resource destructor is exercised through canonical
`[resource-drop]ticket`. The Rust host uses Wasmtime `ResourceTable` and
records create, borrow, consume, and drop events.

This slice excludes HTTP, WIT future/stream values, cancellation, component-GC
crossing, implicit destruction, user-defined resource declarations, and any
ARC-to-GC backend migration.

## Source Contract

Source continues to use a nominal `@wasi_resource` name such as `Ticket`.
`own<T>` and `borrow<T>` remain WIT/manifest qualifiers and are not new public
Do type constructors. The `.id` field in an `@wasi_resource` declaration is
compiler-private representation: source code cannot construct a resource from
an id, inspect or assign its id field, or pass that id through ordinary scalar
operations.

Resource ownership is affine:

- A result declared as WIT `own<T>` creates an active `T` binding.
- Passing an active binding to a WIT `own<T>` parameter consumes it before the
  call result is available. The old binding cannot be used, moved, or dropped.
- Passing it to a WIT `borrow<T>` parameter leaves the binding active. The
  borrow is represented only during that call and cannot be stored, returned,
  or cross an await.
- `resource.drop` consumes an active binding and lowers to the exact
  descriptor-bound canonical resource-drop import. It may occur once only.
- Assignment of a resource binding is an ownership transfer, not a struct
  copy. The source binding becomes inactive.

No implicit destructor is introduced. A normal return with a still-active
resource remains a semantic error in this slice unless ownership was returned
or transferred to a consuming host call.

## Descriptor And Lowering Boundary

A checked-in resource descriptor registry binds each accepted `(locator,
member)` to an exact WIT resource identity and parameter/result ownership mode.
No source spelling or member-name heuristic determines ownership. The generic
resource lowering takes a descriptor plus resource handle positions; it emits
the canonical i32 resource representation only inside the Core WAT ABI layer.
It must not expose that i32 to source code or reuse the old per-interface
descriptor helpers.

For the probe, the compiler emits Core WAT and a WIT sidecar. `wasm-tools
component embed` and `wasm-tools component new` assemble the Component. The
Rust adapter is the authoritative runtime test; Core WAT string checks are
secondary evidence only.

## Error Contract

The semantic pass reports a dedicated resource-ownership diagnostic for use
after transfer/drop, duplicate drop, and an active resource leaving scope.
Unknown resource host descriptors remain rejected rather than being lowered as
ordinary `i32` calls. Existing synchronous WASI resource shells stay supported
through their current path until migrated descriptor by descriptor; this slice
does not change their public APIs.

## Verification

Tests must demonstrate all of the following with real compiler output:

1. `create` returns an active resource; `borrow-value` can be called repeatedly
   and preserves ownership.
2. `consume` invalidates the caller binding; a later use or drop is rejected.
3. Explicit drop invalidates its binding; a second drop is rejected.
4. An active resource cannot silently leave an async or synchronous scope.
5. The assembled Component invokes the Rust host's create/borrow/consume/drop
   paths with the expected values, and the `ResourceTable` observes each owned
   resource deletion exactly once.
6. Existing full compiler regression, resource-specific Zig tests, WIT
   validation, and `git diff --check` pass.

## Compatibility

This introduces no raw pointer, reference, `externref`, `anyref`, `funcref`,
`i31ref`, `own<T>`, or `borrow<T>` syntax to Do. It establishes internal
resource semantics required by existing `@wasi_resource` declarations and
future pinned WIT bindings.
