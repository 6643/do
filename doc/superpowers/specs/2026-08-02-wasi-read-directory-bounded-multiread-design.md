# WASI Read-Directory Bounded Multi-Read Design

**Status:** implemented and verified on 2026-08-02; this design selects the
previously recommended bounded route.

## Goal

Extend the pinned `descriptor.read-directory` Component slice from one
directory entry to a fixed, statically visible sequence of up to three
`@next(reader)` operations. The sequence must preserve the existing
completion-future ordering and exactly-once cleanup, while keeping source-level
dynamic loops and arbitrary record-stream sources rejected.

## Scope

The admitted source shape remains a single pinned host declaration and one
`async` function taking `Dir` and returning `nil`. After acquiring the stream
and independent completion future, the body may contain one to three repeated
blocks:

```do
pending Future<Result<DirectoryEntry, nil>> = @next(reader)
entry Result<DirectoryEntry, nil> = await(pending)
_ = entry
```

The completion future is awaited once after the final entry block:

```do
completed Result<nil, DirectoryError> = await(completion)
_ = completed
return
```

The third read is the bounded EOF probe for the runtime fixture. A source
`loop`, branch, second stream source, payload-bearing completion result, or
fourth read is rejected with the existing fixed-slice error. This is an
unrolled source contract, not dynamic loop lowering.

## Architecture

`ReadDirectoryPlan` records `read_count` in addition to the existing binding
names. Its parser consumes repeated `Future<Result<DirectoryEntry,nil>> =
@next(reader)` / await / discard blocks using the same token guards as the
first block, then requires one completion await and terminal return. The
parser enforces `1 <= read_count <= 3` and rejects any intervening token that
is not the next fixed block or the completion block.

The WAT emitter uses one frame counter for the remaining read states. Each
stream read writes the same directory-entry result area, and the ready path
consumes the entry before decrementing the counter and starting the next read.
An item result continues to the next read while an EOF/dropped result enters
the completion stage. Pending callbacks restore the same state through the
existing context handle. Completion still runs after the fixed sequence or
early EOF, and cleanup remains guarded by zeroing the stream, completion
future, and descriptor frame slots.

The manifest remains the ABI source of truth. Import names, stream indexes,
future indexes, and the three pinned `directory-entry` record offsets are
registry facts, never inferred from source aliases. The layout metadata is a
checkpoint toward generic record support, not generic record-stream admission.

## Runtime Evidence

The Rust host runner will expose `alpha` and `beta` entries followed by an
empty dropped stream result. The test invokes the component in both
pending-once and immediately-ready completion modes and asserts:

- exactly two entry payloads and one EOF probe;
- no read after EOF and no fourth read;
- completion future poll counts of two and one respectively;
- one descriptor drop, one stream drop, one completion-future drop;
- an empty `ResourceTable`.

The existing one-entry fixture and runner remain unchanged and must continue to
pass. The new fixture is separate so its source contract and evidence cannot
silently broaden the old target.

## Non-Goals And Rejection Boundary

- No source-level `loop` or dynamic collection is admitted.
- No generic record type or arbitrary WIT stream descriptor is admitted.
- No payload-bearing completion error is added.
- No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax is
  introduced.
- Cancellation still follows the pinned Component ABI and never rolls back an
  external effect.

## Acceptance

The change is accepted only when the focused Zig tests, the new ABI/lowering
and Rust/Wasmtime scripts, the existing read-directory scripts, the default
regression suite, ReleaseSmall smoke, and `git diff --check` all pass. Docs
must describe this as bounded multi-read evidence and retain dynamic record
streams as unsupported.
