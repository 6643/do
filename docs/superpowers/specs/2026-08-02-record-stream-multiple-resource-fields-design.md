# Generic Record-Stream Multiple Owned Resource Fields Design

## Goal

Extend the existing private generic record-stream consumer from one owned WIT
resource field to multiple owned fields, while keeping Do source ownership-free
and preserving exactly-once cleanup for every resource handle.

## Scope

The admitted shape remains internal to a registered async-manifest descriptor.
Every resource source field must have `ownership: "own"`, one aligned Core
`i32` storage slot, a source type equal to its resource name, and an explicit
`[resource-drop]` import. Scalar and string fields keep their existing rules.
Borrowed fields, nested/list/variant resources, resource escape, producer
leases, and public `own<T>`/`borrow<T>`/`ref<T>` syntax remain rejected.

The probe record contains two `own<ticket>` fields. The WIT generator declares
the `ticket` resource once and emits one drop import despite two fields. The
frame reserves one four-byte slot per owned field, decodes each handle before
marking the record active, and releases fields in deterministic source-field
order. Each release tests the handle, drops it once, clears its slot, and the
active bit is cleared after all fields. Repeated terminal cleanup is harmless.

## Validation And Runtime Evidence

Manifest validation permits any positive number of owned resource fields as
long as source names and storage names remain unique and every field passes
the existing resource checks. WIT/drop-import generation deduplicates by
resource/drop identity. A private pending/ready/error Rust/Wasmtime runner
supplies two records with two handles each and asserts record order, four
resource drops, one stream drop, one completion-future drop, and an empty
`ResourceTable` for every mode.

This is a bounded ABI checkpoint, not a general ownership system. No resource
field may be copied, passed to another operation, retained after the record
body, or mixed with `borrow` metadata.

## Rejected Alternatives

1. Public ownership syntax: rejected because Do still lacks general escape and
   borrow analysis.
2. Borrowed fields first: rejected because borrow lifetime and host validity
   rules are not frozen.
3. Producer lease first: rejected because writable endpoints, backpressure,
   cancellation, and source-level pumping are an independent larger gate.
