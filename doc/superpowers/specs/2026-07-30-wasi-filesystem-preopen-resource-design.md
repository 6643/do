# WASI Filesystem Preopen Resource Design

## Goal

Extend the verified private resource probe to one real pinned WIT slice:
`wasi:filesystem/preopens@0.3.0` `get-directories`, followed by
`wasi:filesystem/types@0.3.0` `descriptor.sync` and canonical descriptor drop.

## Source Surface

Do source remains unchanged. A module declares `Dir` with
`@wasi_resource("filesystem/types/descriptor", { .id i64 })`, imports the
existing preopens and sync bindings, obtains one preopen descriptor, borrows it
for `sync`, and explicitly transfers it to the registered drop binding.

There is no public `own<T>` / `borrow<T>` syntax and source cannot read, write,
or fabricate `.id`.

## Descriptor Registry

A pinned descriptor table records the actual WIT ownership forms:

- `get-directories() -> list<tuple<own<descriptor>, string>>`
- `descriptor.sync(borrow<descriptor>) -> result<_, error-code>`
- canonical `[resource-drop]descriptor`

Ownership is never inferred from member spelling. The table drives sema,
Component WAT, WIT sidecar, and Wasmtime host registration.

## Component Boundary

The opt-in target accepts only the fixed preopen probe source flow. It emits a
Core module plus matching WIT, then `wasm-tools component embed/new` assembles
the Component. The Core flow takes the first preopen entry, calls sync with a
borrowed descriptor, checks the successful result tag, and invokes canonical
resource drop exactly once.

The Wasmtime runner owns descriptors in `ResourceTable`; preopens creates one
owned descriptor, sync reads it without deletion, and the resource destructor
deletes it. The execution test asserts each event count and that the table is
empty after `run`.

## Exclusions

This does not add generic Component lowering, arbitrary resource lists, file
open/read/write, HTTP, Future/Stream, cancellation, Component-GC, or ARC
migration. A nonmatching source must fail the opt-in target rather than fall
back to ordinary lowering.

## Verification

Red/green fixtures cover borrow preservation, drop, malformed source rejection,
WIT validation and Component assembly. The Rust runner exercises the assembled
component with Wasmtime 47 and `ResourceTable`. The normal compiler regression
suite continues to run independently of the Rust example.
