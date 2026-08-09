# G6.2 Bounded Scalar List Producer Probe

Date: 2026-08-09
Status: evidence-only probe; no compiler promotion

## Decision

The pinned Component toolchain accepts the hand-authored pure-scalar
`stream<list<u32>>` shape for one bounded producer protocol. This green probe
authorizes a separate future plan for registry/sema/codegen admission; it does
not add a descriptor, generic list lowering, or public `own<T>`, `borrow<T>`,
`ref<T>`, pointer, reference, or lifetime syntax.

## Canonical Shape

The checked-in WIT is intentionally the exact probe shape:

```wit
package do:g6-2-scalar-list-producer@0.1.0;

interface types {
  enum error-code { io, pipe, invalid-mode }
}

interface sink {
  use types.{error-code};
  consume-via-stream: async func(data: stream<list<u32>>) -> result<_, error-code>;
}

world scalar-list-producer {
  use types.{error-code};
  import sink;
  export produce: async func(count: u32) -> result<_, error-code>;
}
```

`count` is a bounded input, not an implicit list length generalization:

| Input | List item | Sink call |
| ---: | --- | ---: |
| `0` | `[]` | `1` |
| `1` | `[10]` | `1` |
| `2` | `[10, 20]` | `1` |
| `3` | `[10, 20, 30]` | `1` |
| `4` | `Err(invalid-mode)` | `0` |

The private probe controls use inputs `10..14` for pending, sink error, early
drop, cancellation before transfer, and cancellation after transfer. They are
runner-only controls and do not change the WIT contract for `count=0..4`.

## Pinned Evidence

Toolchain:

```text
wasm-tools 1.255.0 (76e20611d 2026-07-30)
wasmtime 47.0.2 (90fed3c6a 2026-07-21)
rustc 1.97.1 (8bab26f4f 2026-07-14)
```

Artifact hashes for this run:

```text
examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
sha256: a24e467b1746f94432bb495c13fc0ce718a3833dc0ce7659228cfb6eaf69ff9f

examples/p3-runtime/g6-2-scalar-list-producer-canonical.wat
sha256: 73b47cc83052a4d3cc16919c14bf7445e400d43c5d9268b59ba4404226f6583a

examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh
sha256: 529ab52558b4493cb766ec4f632b465af47829b2731a9a57162656ccdebef680

examples/p3-runtime/rust-host-runner/src/bin/g6_2_scalar_list_producer_abi.rs
sha256: 2a0b170ba54052ebaa0c021344dd9ddded010442ec10211c6b1a9947346277fb
```

The WAT markers measure the fixed canonical path:

```text
list pointer word: 64
list length word: 68
u32 element stride: 4
maximum list elements: 3
single stream item slot: 0
```

Each admitted row allocates a 4-, 4-, 8-, or 12-byte scalar backing region
(`count=0..3`) and releases it once through `cabi_realloc`. The WAT keeps an
internal release state and asserts `list-release-count == 1` at cleanup for
every admitted row; the invalid `count=4` row asserts zero allocation/release.
This is a scalar list allocation invariant, not a resource or pointer type in
the Do language. The Rust host runner reports an empty `ResourceTable` for
every row.

## Runtime Matrix

The gate command was:

```bash
wasm-tools component wit examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
sha256sum examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
bash examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh
```

The complete machine-checkable rows were:

```text
mode=count-0 result=Some((Ok(()),)) values=[] expected=[] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=count-1 result=Some((Ok(()),)) values=[10] expected=[10] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=count-2 result=Some((Ok(()),)) values=[10, 20] expected=[10, 20] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=count-3 result=Some((Ok(()),)) values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=pending result=Some((Ok(()),)) values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=1 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=sink-error result=Some((Err(Pipe),)) values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=early-drop result=Some((Err(Pipe),)) values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=cancel-before-transfer result=Some((Ok(()),)) values=[] expected=[] host-calls=1 pending-polls=0 stream-drops=0 cancel-calls=0 list-releases=1 table-empty=true
mode=cancel-after-transfer result=None values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=count-4 result=Some((Err(InvalidMode),)) values=[] expected=[] host-calls=0 pending-polls=0 stream-drops=0 cancel-calls=0 list-releases=0 table-empty=true
G6.2 scalar list producer canonical ABI probe passed
```

`pending` observes one pending poll before the ordered list is consumed.
`sink-error` and `early-drop` consume the list and return `Err(pipe)`, so the
external effect is not rolled back and the guest list is still released once.
`cancel-before-transfer` cancels the host subtask before stream transfer and
keeps the list entirely guest-owned. `cancel-after-transfer` observes the
ordered values before the parent call is cancelled; it drops live async state
without compensating the already-issued stream effect.

## Boundary

This is a hand-authored canonical ABI/runtime probe only. It does not modify
`p3_async_registry.json`, sema admission, codegen, generated WIT, or the
ordinary Do type surface. A later promotion must create a separate registry
descriptor, negative fixtures for list length/element/layout drift, and an
independent compiler-generated Component/Rust/Wasmtime gate. A failed future
promotion must leave this probe and the existing resource/list descriptors
unchanged.
