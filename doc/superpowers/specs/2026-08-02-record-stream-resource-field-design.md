# Generic Record-Stream Owned Resource Field Design

Status: approved for the next bounded G6.2 slice on 2026-08-02.

## Goal

Extend the descriptor-driven record-stream consumer with one executable
resource-valued record field. The slice proves that an owned WIT resource
handle can be lifted from a stream record, held for the admitted source
expression, and released exactly once at the record terminal boundary.

The public Do language remains unchanged: `own<T>`, `borrow<T>`, `ref<T>`,
pointers, and references are not source types. Ownership is represented only by
the WIT descriptor, manifest metadata, generated cleanup, and the existing
`@wasi_resource` declaration.

## Admitted Shape

Use a private descriptor package:

```text
do:record-resource-stream-probe@0.1.0
source.read-via-stream
```

Its source interface returns:

```wit
tuple<stream<resource-entry>, future<result<_, error-code>>>
```

The record is:

```wit
resource ticket {}

record resource-entry {
  id: u32,
  ticket: own<ticket>,
}
```

The Do fixture declares an opaque `Ticket` with `@wasi_resource`, receives the
record stream, runs the same dynamic one-read-in-flight loop as the scalar and
text probe, and discards each admitted entry after the body has observed it.
The descriptor is private and is not inferred from arbitrary locator/member
strings.

The manifest extends each resource source field with explicit metadata:

```json
{
  "name": "ticket",
  "source_type": "ticket",
  "storage": ["ticket"],
  "ownership": "own",
  "resource": "ticket"
}
```

Validation requires one aligned `i32` storage slot, a registered resource
drop operation, and `ownership == "own"`. Borrowed record fields and multiple
resource fields are rejected in this slice rather than approximated.

## Data Flow And Cleanup

1. The stream read writes the record's Core resource representation into the
   validated record area.
2. The generated decoder copies the handle into a frame-owned record slot and
   emits a marker naming the resource drop operation.
3. The admitted source shape discards the entry after the read callback. The
   generated record cleanup calls `[resource-drop]ticket` once and clears the
   slot before the next read.
4. EOF transitions to the existing independent completion future. Completion,
   read failure, cancellation, and host error all use the same idempotent
   cleanup path.
5. Stream and completion handles are still dropped once, and the host
   `ResourceTable` must be empty after the Component call.

The record resource is not allowed to escape the loop, be copied, or be passed
to another host operation. Those shapes remain explicit unsupported lowering.

## Compiler Boundaries

- `RecordSourceField` carries ownership and resource identity in the async
  manifest; ordinary scalar/text fields retain their existing representation.
- `valid_record_stream_layout` admits the resource field only when its Core
  type, storage, ownership, and resource drop facts agree.
- WIT generation declares the private resource in the source interface and
  emits `own<ticket>` in the record field. Keeping the resource and record in
  that interface makes the Core `[resource-drop]ticket` module explicit and
  avoids inferring a second WIT interface from a Do alias. Do-side output never
  contains the WIT ownership qualifier.
- The generic emitter adds the descriptor resource-drop import and releases
  the frame-owned record handle exactly once. It does not add a general
  resource field ABI or change unrelated resource emitters.
- Existing scalar/text record streams and the fixed filesystem slice remain
  unchanged and continue to use their current cleanup paths.

## Alternatives Rejected

1. **Treat the resource as a plain `i32` scalar.** Rejected because it loses
   the WIT ownership contract and can leak or double-drop a host resource.
2. **Add public `own<T>`/`borrow<T>` syntax.** Rejected because it would make
   resource ownership part of the Do type system before escape and borrow
   analysis exist.
3. **Generalize arbitrary resource fields and resource escape now.** Rejected
   for this slice because it combines record layout, affine data flow, and
   arbitrary host operations; it needs a separate ownership plan.
4. **Implement producer leases first.** Deferred because producer pumping adds
   writable endpoint, backpressure, cancellation, and source-loop obligations
   that are independent of consumer-side resource lifting.

## Verification Matrix

- Focused manifest tests cover valid owned resource metadata and rejection of
  missing drop, borrowed ownership, wrong Core type, duplicate storage, and
  multiple resource fields.
- Focused record-stream tests cover generated WAT markers, the resource-drop
  import, and rejection of an escaping or borrowed resource field.
- The lowering gate runs `wasm-tools parse`, `component embed`, `component new`,
  and Component validation for the private package.
- The Rust/Wasmtime runner supplies two resource-bearing records in pending,
  ready, and completion-error modes. It asserts record order, EOF, completion
  polls, one resource drop per record, one stream drop, one future drop, and an
  empty `ResourceTable`.
- The existing generic scalar/text probe, bounded read-directory probe, full
  regression suite, ReleaseSmall smoke, and `git diff --check` remain gates.

## Explicit Non-Goals

- No arbitrary record resource fields, borrowed fields, nested resource
  records, lists, variants, or resource-valued completion errors.
- No public ownership/reference syntax and no Core GC/ARC migration.
- No guest producer pump, producer lease, or writable stream endpoint changes.
- No arbitrary filesystem async method admission.
