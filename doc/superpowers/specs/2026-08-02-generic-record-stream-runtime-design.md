# Generic Record-Stream Runtime Design

**Status:** approved for implementation on 2026-08-02 by the continuation request.

## Goal

Replace the current descriptor-specific `read-directory` stream template with a
descriptor-driven runtime that can consume any registered record stream while
preserving Do's value semantics and keeping WIT ownership types internal to the
Component boundary.

The first delivery is a complete consumer vertical slice: a dynamic source loop
can issue one record read at a time, decode a registered record, stop at EOF or
completion error, and release every stream, future, record buffer, and frame
exactly once. A later producer slice will reuse the same lifecycle model for
guest-created writable endpoints and backpressure.

## Constraints

- Do source does not expose `own<T>`, `borrow<T>`, `ref<T>`, pointers, or
  references.
- WIT `own`/`borrow` remain internal ABI ownership facts used by the descriptor
  and cleanup plan.
- The pinned Component async ABI and `wasi:filesystem@0.3.0-rc-2025-09-16`
  source hashes remain authoritative.
- `RecordLayout` is the only source of record-area offsets; emitters must not
  embed a directory-specific offset table.
- There is at most one in-flight read per consumer. A second read is rejected
  before an import is emitted.
- Cancellation observes the Component terminal state and releases waitables and
  resources; it never rolls back an external host effect.
- Existing fixed one-to-three-entry `read-directory` fixtures remain green
  throughout the migration and are not silently widened by this design.

## Alternatives

### A. Descriptor-driven runtime state machine (recommended)

The manifest validates a generic stream descriptor and record layout. A shared
runtime plan owns the stream/future handles, record area, read continuation, and
terminal cleanup. Filesystem, CLI, and HTTP modules provide descriptor-specific
names and source-shape adapters only.

This is the recommended route because it makes ownership, backpressure, and
cleanup one implementation instead of multiplying WAT templates. It also keeps
the language surface value-based while allowing WIT resources to remain an ABI
detail.

### B. Parameterized per-interface templates

Each interface keeps a private emitter, with hard-coded control flow replaced by
manifest-derived offsets and import names. This is a useful migration aid, but
it cannot provide dynamic loops, arbitrary record layouts, or a shared producer
lease. It is not sufficient as the final runtime architecture.

### C. Public `own`/`borrow` types

Expose WIT ownership in Do and let source code drive resource endpoints directly.
This would add ownership checking, affine moves, borrow validity, escape rules,
and new diagnostics to the language. It is unnecessary for the runtime problem
and conflicts with the existing no-reference value model, so it is rejected for
this phase.

## Architecture

### Descriptor and layout

`p3_async_manifest` remains the descriptor loader and validator. The existing
`RecordLayout` is extended only with facts needed by generic lifting:

- stable record name;
- ordered source fields;
- Core scalar storage type and byte offset for scalar fields;
- explicit pointer/length pairing for UTF-8 text fields;
- total record-area byte size, aligned to four bytes.

The loader rejects missing fields, duplicate source names, duplicate storage
slots, unaligned offsets, overlapping slots, unsupported nested/list/resource
fields, and text pairs whose pointer or length field is absent. A descriptor is
eligible for generic lowering only after its pinned WIT source mirror and all
of these facts validate.

### Consumer plan

`src/build/codegen_component_record_stream.zig` becomes the shared planning and
state-model boundary. It consumes a validated
`p3_async_manifest.RecordStreamReaderShape` and produces a
`RecordStreamPlan` containing:

- stream and completion-future operation names;
- record layout and record-area size;
- result-area offsets for the current read;
- source loop continuation states;
- cleanup actions for readable stream, completion future, record buffer, and
  frame.

The plan has no parser or global mutable state. It is pure data plus a guarded
transition function so it can be unit-tested without Wasmtime.

### Runtime state machine

The consumer transitions through these phases:

```text
Idle -> ReadPending -> ItemReady -> ReadPending
                         |              |
                         v              v
                       Eof          CompletionPending
                         \              /
                          -> Terminal -> Closed
```

An item error, completion error, or cancellation enters `Terminal`. The
terminal transition records the outcome once and emits cleanup in a fixed order:

1. cancel or join the active read/future when required;
2. drop the readable stream endpoint;
3. drop the completion future endpoint;
4. release copied record storage;
5. release the async frame and byte-budget charge;
6. return the recorded Do result.

Each cleanup flag is monotonic. Replaying a terminal callback is harmless and
emits no duplicate drop or release action.

### Source contract

The first source form is a loop whose body performs one explicit `@next(reader)`
and `await`, then branches on the generic `Result` tag. `Ok(record)` enters the
body with a decoded value; `Err(nil)` marks EOF; a non-nil completion error
returns the function's declared error. The compiler rejects two concurrent
reads, hidden read calls, unsupported nested control flow, and a record type
that has no validated layout.

The existing fixed read-directory source form remains supported during the
migration. Its emitter is changed to consume the shared plan before the generic
loop form is enabled by the main pipeline.

### Producer follow-up

Guest producers are a separate phase. They use the same frame and terminal
cleanup model plus a `ProducerLease` state that owns the writable endpoint until
`close` or `abort`. A write is admitted only when the consumer has accepted the
endpoint and the byte-budget gate has capacity. Dynamic producer loops and
payload-bearing producer errors are not part of the consumer milestone.

## Error and cancellation semantics

- Descriptor or layout mismatch is a compile-time unsupported-shape diagnostic;
  no alternate WAT is emitted.
- A pending read that is cancelled is cancelled at the Component operation
  boundary, then cleaned up after the operation reports a terminal state.
- EOF is a normal stream outcome and does not suppress completion-future cleanup.
- A host completion error is returned as the declared Do error when its payload
  shape is registered; an unregistered payload shape is rejected before
  lowering.
- Host effects already issued before cancellation are not rolled back.

## Verification

The consumer milestone is accepted only when all of these pass:

1. unit tests cover every legal transition, illegal concurrent read, repeated
   terminal callback, EOF, completion error, and cancellation;
2. manifest tests cover scalar fields, text pointer/length pairs, invalid and
   overlapping layouts, and a second registered record descriptor;
3. compiler tests lower a dynamic loop with at least two records and EOF without
   directory-specific names or offsets in generated WAT;
4. Component assembly and validation pass with `wasm-tools 1.254.0`;
5. Rust/Wasmtime pending and immediately-ready hosts observe the records,
   completion outcome, exactly-once cleanup, and an empty resource table;
6. `./src/build/test/run_tests.sh`, release smoke, and `git diff --check`
   remain green.

The phase is not called complete by a unit-only state model. The generated
Component and Rust/Wasmtime gates are required before G6.2 is removed from the
blocked list.
