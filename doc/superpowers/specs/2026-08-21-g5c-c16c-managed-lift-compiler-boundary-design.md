# G5c C16-C: private managed-record lift compiler boundary

## Goal

Promote the already verified C15-A managed-record lift probe into a private,
explicit compiler route that consumes a real source-level synchronous
`@host_func` declaration and emits the pinned manifest-backed GC module.

## Selected boundary

The only admitted descriptor is:

```text
demo:marshal-record-managed-lift/api.read@1.0.0/lift
```

The source fixture must contain exactly one top-level declaration equivalent to:

```do
read = @host_func("demo:marshal-record-managed-lift/api@1.0.0", "read", () -> Reading)

Reading {
    code u32
    label text
}

start() {}
```

The validator requires the exact synchronous `@host_func`, locator, member,
zero parameters, result type `Reading`, and ordered fields `code: u32` and
`label: text`. It rejects async markers, locator/member drift, nonzero
parameters, non-record results, reordered/wrong fields, duplicate or extra
host declarations, and unknown descriptors before any WAT is returned.

## ABI and emitter contract

The manifest and measured layout remain authoritative. The root result area is
12 bytes aligned to 4 with `code@0`, `label.ptr@4`, and `label.len@8`.
The canonical import is `(func (param i32))`: the host writes the result area,
the GC lift copies the text bytes into `$do_bytes`, constructs `$do_text` and
the record, and the private `run` export returns `code + label.length` for the
fixed host gate. No GC reference crosses the canonical import.

`--gc-wit-marshal` remains opt-in and supports only the fixed C15-B/C15-A/C16-A
descriptor allowlist. Ordinary `@host` stays on the ARC transition route.
This task does not add generic Do-to-WIT inference, public ownership syntax,
async/resource lowering, Option/Result lowering, or default GC host routing.

## Gates

The positive compiler host and ARC/GC equivalence gates must use the dedicated
fixture and observe the existing C15-A values (`value=12` and `12/12`).
Negative CLI fixtures must fail before WAT and cover async marker and locator
mismatch. A default build of the same fixture must retain its ARC marker and
must not contain the private canonical import. The migration inventory remains
unchanged and continues to report 15 pending rows.
