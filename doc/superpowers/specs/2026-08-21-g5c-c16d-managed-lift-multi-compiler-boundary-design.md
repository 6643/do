# G5c C16-D: private managed-record multi-lift compiler boundary

## Goal

Promote the measured three-field managed-record lift into a private explicit
compiler route without changing the ordinary ARC-backed host path.

## Selected descriptor

The only admitted descriptor is:

```text
demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift
```

The source fixture must contain exactly one synchronous declaration equivalent
to:

```do
read = @host_func("demo:marshal-record-managed-lift-multi/api@1.0.0", "read", () -> Reading)

Reading {
    code u32
    label text
    note text
}

start() {}
```

The source validator requires the exact locator/member, `@host_func` marker,
zero parameters, `Reading` result, and ordered `code: u32`, `label: text`, and
`note: text` fields. Unknown descriptors, async markers, locator/member drift,
shape drift, duplicates, and extra host declarations fail before WAT.

## ABI and emitter contract

The manifest-backed WIT result layout is 20 bytes aligned to 4:

```text
code@0
label.ptr@4
label.len@8
note.ptr@12
note.len@16
```

The canonical import remains `(func (param i32))`: the host receives a pointer
to the result area, the GC lift checks both spans, copies both text payloads
into `$do_bytes`, constructs two `$do_text` values and the enclosing record,
and publishes the result without crossing a GC reference through the import.
The private `run` wrapper returns `code + label.length + note.length`, which is
`17` for the fixed host values `7`, `hello`, and `world`.

`--gc-wit-marshal` remains explicit and fail-closed. Ordinary `@host_func`
compilation remains ARC-backed. This task does not add generic Do-to-WIT
inference, public ownership syntax, async/resource lowering, Option/Result
semantics, or default GC host/WIT routing. The migration inventory remains
15 rows with its G5c pending status.

## Gates

The compiler host gate must build the dedicated fixture, parse the generated
WAT with pinned `wasm-tools 1.255.0`, assemble and validate a Component, and
observe `value=17` from the Rust/Wasmtime host. The equivalence gate compares
the generated GC Component with a linear-memory ARC reference and observes
`17/17`. Negative fixtures cover async marker and locator mismatch and require
no WAT artifact. A default build of the same fixture must retain its ARC
marker and exclude the private canonical import.
