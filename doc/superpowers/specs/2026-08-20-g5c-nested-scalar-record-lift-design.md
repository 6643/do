# G5c C10: nested scalar-record lift

## Status

Design selected for the next private G5c marshal gate. This is a bounded
parser-backed evidence slice; it does not change the default host/WIT route or
close the `host_wit_marshalling` inventory row.

## Goal

Prove that the measured GC marshal route can recursively lift a value-only WIT
record containing one nested scalar record, while preserving the canonical ABI
boundary and ARC/GC observable equivalence.

The gate must be independently reproducible with the pinned
`wasm-tools 1.255.0` toolchain and the existing Rust/Wasmtime runner pattern.
The source identity, WIT signature, and world fragment are owned by the
descriptor manifest; callers supply only the descriptor id to the private
route.

## Selected shape

The source fragment is a new package/interface with this value-only member:

```wit
package demo:marshal-record-nested-host@1.0.0;

interface api {
  record header {
    code: u32,
    count: u64,
  }

  record reading {
    header: header,
    status: s64,
  }

  read: func() -> reading;
}
```

The package-less world fragment imports `api` and exports `run: func() -> u32`.
The host returns `{ header: { code: 7, count: 35 }, status: -5 }`; the guest
adds the three scalar leaves and must return `37`.

## Alternatives and decision

### A (selected): nested scalar-record `lift`

Use one result-area pointer at the canonical import, recursively load the
measured nested fields, construct the inner GC record, then construct the outer
GC record and publish it through a typed local. This exercises recursive
record layout and construction with one direction and does not introduce a
new linear-memory allocation or ownership protocol.

### B: nested scalar-record `lower`

Allocate a measured nested record area, recursively store the inner and outer
fields, call the canonical import, and release the area. This is useful after
A, but it adds more write-offset and temporary-buffer cases before recursive
lift construction is proven.

### C: default host/WIT route wiring

Route all currently measured shapes through ordinary `do build` host/WIT
lowering immediately. This mixes compiler cutover with a new recursive shape,
has a larger rollback surface, and would make a failure ambiguous between
layout measurement, route selection, and the legacy ARC residual. It is not
selected.

## ABI and layout contract

1. The nested record is measured from the parser-backed WIT tree; the probe
   does not accept caller-supplied offsets as authority.
2. `header` has size 16 and alignment 8: `code` is at offset 0 and `count` at
   offset 8.
3. `reading` has size 32 and alignment 8: `header` is at offset 0 and
   `status` is at offset 16.
4. The canonical import is `(i32)` where the argument is the result-area
   pointer. No `(ref null $do_*)` occurs in its parameter or result types.
5. The GC module constructs `$do_header` first, then `$do_reading` with the
   nested header reference and status value. The canonical area is validated
   before any result is published.
6. The host Component callback receives the WIT record value, not the Core
   pointer representation. The linear-memory ARC reference reads the same
   measured offsets.

If the pinned toolchain reports a different layout or canonical signature, the
gate fails closed and the design must be revised; the expected facts above are
not permission to bypass measured evidence.

## Admission and rejection

The private descriptor route admits exactly this value-only nested shape. It
must reject before WAT emission:

- a source-hash, package, world, member, direction, or signature drift;
- a missing or extra nested field, changed scalar type, or changed record
  depth;
- a list, text, option/result/variant, resource, or async member in this
  descriptor;
- a GC reference marker in any canonical slot;
- an indirect layout or nested depth beyond the pinned two-record shape.

The ordinary host/WIT route remains ARC-backed for this member and all other
unsupported shapes. No public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or
`Result` syntax is introduced.

## Evidence gates

The implementation is complete only when all of these pass:

1. parser-backed descriptor loading and source-hash drift negative check;
2. focused Zig unit tests for recursive measured-node binding, offsets,
   canonical slot validation, and generated GC construction;
3. Core WAT parse, Component embed/new/validate with `wasm-tools 1.255.0`;
4. Rust/Wasmtime host execution returning `37`;
5. a linear-memory ARC reference under the same WIT world returning `37`;
6. an ARC/GC equivalence gate observing `37/37` and no GC reference at the
   Component boundary;
7. the existing full regression, ReleaseSmall build, and residual inventory
   gate.

## Non-goals and rollback

This change does not implement arbitrary recursive aggregates, nested lower,
lists/text inside records, variants, resources, async frames, default route
cutover, or GC runtime replacement. If any gate cannot preserve the measured
layout or boundary invariant, remove only the C10 descriptor/probe files and
leave C1-C9 and the ARC residual route unchanged.

## Verification commands

```bash
cd src && zig test main.zig
cd .. && ./src/build/test/run_tests.sh
bash src/build/test/check_gc_g5c_residual_gate.sh
```
