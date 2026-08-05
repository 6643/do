# Core Wasm GC probe

This directory is a standalone capability probe for the Core Wasm GC
instructions intended for the future do runtime. It has no Component Model,
WIT, WASI, P3, host import, resource, or cancellation behavior.

`gc-frame.wat` verifies three representation rules:

1. A mutable `struct` can represent runtime-private frame state.
2. A mutable `array` can represent a runtime-private queue.
3. A source value is an immutable GC `struct`; a changed value is rebuilt, so
   the original remains unchanged after assignment/copy.

Run it from the repository root:

```bash
examples/gc-p3-runtime/run-wasmtime.sh
```

The script uses `/home/_/Public/wasmtime/bin/wasmtime` by default and accepts
`WASMTIME_BIN=/path/to/wasmtime` for an explicit override. It enables only
`-W gc=y`, uses Wasmtime's `compile` command to compile-or-validate the WAT,
then invokes `probe`. The guest traps unless its internal representation check
computes `27815`, and the script requires that exact returned value.

Recorded on 2026-07-28:

```text
wasmtime: wasmtime 47.0.2 (90fed3c6a 2026-07-21)
compile-or-validate: ok
run:
warning: using `--invoke` with a function that returns values is experimental and may break in the future
  guest result: 27815
GC probe passed: 27815
```

The feature set for both validation and execution is exactly `-W gc=y`. The
warning is emitted by Wasmtime's CLI; the probe intentionally returns a value
so the script can assert the in-guest result without a host import.

## Restricted compiler lowering

`do build --gc-core` is an experimental, deliberately restricted target. It
does not select the active ARC backend and it does not accept arbitrary Do
programs. The currently executable source forms are independent fixtures:

```do
identity(value text) -> text {
    return value
}

start() {}
```

```do
update(input [u8]) -> [u8] {
    return @set(input, 0, 65)
}

start() {}
```

```do
set_at(input [u8], index usize, value u8) -> [u8] {
    return @set(input, index, value)
}

start() {}
```

```do
Box {
    value [u8]
}

update(box Box) -> Box {
    return @set(box, .value, @set(@get(box, .value), 0, 65))
}

start() {}
```

```do
Box {
    value [u8]
    tag i32
}

update(box Box) -> Box {
    return @set(box, .value, @set(@get(box, .value), 0, 65))
}

start() {}
```

Run the source-to-engine checks from the repository root:

```bash
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_text_identity.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_text_identity_renamed.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_parameterized_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_parameterized_list_set_renamed.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_renamed.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_preserve_field.sh
```

The list fixture uses a GC array reference for function transfer, allocates a
fresh array for `@set`, copies the original bytes, and changes only the fresh
array. Its exported probe traps unless the original remains `[1, 2, 3]` and
the returned value is `[65, 2, 3]`. This is a persistent-update semantic check,
not a unique-value reuse optimization.

The parameterized-list fixture takes the index and byte as source parameters.
Its emitted function uses the input's `array.len` for allocation and copies that
entire runtime length before the parameterized `array.set`.

For this parameterized shape, the function and parameter identifiers are not
part of the ABI contract: `replace(bytes [u8], offset usize, next u8)` is also
accepted when its body directly returns `@set(bytes, offset, next)`. Different
types, control flow, or a different data flow remain unsupported.

The text identity shape has the same naming rule: `relay(message text) -> text`
is accepted when its body directly returns `message`. It transfers the internal
GC reference, not a copied text payload.

The managed-struct fixture repeats that check through an immutable outer GC
struct. It copies and updates the nested array, then constructs a distinct
`Box`; the original `Box.value` continues to read as `[1, 2, 3]`.

The field-preserving fixture additionally records a `tag i32`. Updating
`value` retains `tag` in both the old and the new `Box`, proving that an outer
rebuild does not discard unrelated fields.

The managed-struct shape also accepts renamed struct, function, receiver, and
`[u8]` field bindings. `Packet/bytes/rewrite` uses the same immutable path-copy
lowering as `Box/value/update`; different field types or update data flows stay
outside this experimental target.

`async-frame-table.wat` validates the internal async-frame bridge used by the
selected P3 clocks/cancellation lowering. A Core table roots each GC frame
while a host retains only its `i32` slot handle. The probe clears a completed
slot, links that handle through a GC-private free-slot node, then proves the
next frame reuses the same handle. It also holds two frames concurrently to
verify distinct live slots and reuses the first released slot while the second
remains rooted. Saved frame values remain GC struct fields and no GC reference
crosses the Component boundary or shares canonical ABI memory.

## ARC semantic baseline

The active ARC backend remains the semantic baseline for cleanup behavior:

| Fixture | Existing evidence | Task 0 limitation |
| --- | --- | --- |
| `src/build/test/compile_ok/142_defer_lifo_multiple_cleanups_lower.do` | `cleanup_b` lowers before `cleanup_a`, proving LIFO defer order. | Synchronous return only. |
| `src/build/test/compile_ok/150_defer_recv_loop_control_lower.do` | `continue` and `break` lower the loop-local defer before ARC release of `tmp`. | `recv(xs)` is existing loop syntax, not a suspended host receive. |
| `src/build/test/compile_ok/276_wasi_func_do_sig_and_resource.do` | `descriptor.drop` lowers as `[resource-drop]descriptor`. | It does not exercise a pending host operation or cancellation acknowledgement. |

The intended future sequence is fixed as:

```text
cancel request -> host terminal outcome -> LIFO defer -> resource drop -> frame invalidation
```

`Complete` can still win after a cancel request; only the host terminal outcome
decides whether cleanup begins. Task 0 does not dynamically verify that
sequence. Tasks 5 and 8 must execute it against the host-driven P3 runtime.

## Future ownership table

This table is the GC runtime target, not a claim about the active ARC backend.

| Item | Memory owner | Logical owner | Destruction rule |
| --- | --- | --- | --- |
| GC frame | GC heap | Scope while its task is live | Scope invalidates it only after terminal outcome and cleanup; GC reclaims it once unreachable. |
| GC value object | GC heap | Reachable source/runtime values | GC reclaims it once unreachable; no resource drop is attached. |
| Resource handle | Host resource table | Scope | Scope invokes the explicit idempotent drop exactly once; GC never drops it. |
| Defer payload | GC heap if it contains GC values | Scope defer stack | Scope consumes it in LIFO order before frame invalidation, then releases its roots. |
| P3 event buffer | Host before accepted delivery; guest ABI buffer after transfer | Receiving Scope after acceptance | Host frees or cancels an undelivered buffer; the receiving Scope releases an accepted buffer after handling or terminal cleanup. GC refs never cross the component boundary. |

## Future representation matrix

| Source/runtime category | Future Core Wasm representation | Update rule |
| --- | --- | --- |
| Scalar, value enum, small struct without managed fields | Core Wasm value | Copy by value. |
| Large struct, list, text, or value containing managed fields | GC object | Treat source values as immutable; rebuild/clone on update. |
| Private frame, channel queue, runtime cell | Mutable GC `struct` or `array` | `struct.set`/`array.set` are allowed only inside runtime-private ownership. |
| Ordinary source value update | New GC object | Never mutate an aliased source value; proven-unique runtime-private objects are the only later optimization boundary. |

## Task 0 gate

**Core GC representation: GO.** The recorded probe proves this exact Wasmtime
binary accepts and executes the selected Core GC instruction subset.

**Runtime/ARC switch: NO-GO.** It remains blocked on the Task 5
scheduler/byte-admission contract, Task 8 terminal-outcome cleanup, and Task 9
complete GC lowering plus copied ABI migration. The separate Wasmtime C
embedder experiment is neither a compiler nor an ARC/GC gate.

The byte-admission contract has a first executable model in
`src/build/async_byte_budget.zig`. It is instance-owned and transactional:
reserve before mutation, then commit or rollback; committed allocations are
released exactly once. The model covers frame, queue, text/list, and canonical
ABI byte formulas with checked overflow. It is a contract test only; until the
runtime's scheduler and allocation call sites consume it, this Task 0 gate
remains NO-GO.

The compiler-side `StreamWriterQueue` model now has an explicit
`init_with_budget` path. Accepted and pending queue entries retain allocation
tokens, and item consumption or writer finalization releases them exactly
once. The TaskFrame model now accounts the existing 16-byte header plus the
layout payload and emits `[async-frame-bytes]` metadata. The HTTP service model
also accounts its 64-byte per-handle canonical result slot and emits
`[canonical-buffer-bytes]`. These are compiler-side admission boundaries only;
generated frame allocators now carry the frame byte count through a checked
instance-local counter before `table.grow`, and generated HTTP result buffers
reserve their fixed 64-byte slot before `memory.grow` and release it after
terminal `task-return`. The counter detects overflow and returns bytes on
cleanup, but it is not yet a configurable quota or a scheduler admission
policy; non-HTTP canonical allocations remain unbudgeted.

The standalone `async-frame-table.wat` probe now executes a fixed 16-byte
runtime budget as well: two 8-byte frames, or one frame plus one 8-byte
canonical buffer, are admitted; the next allocation is rejected before
`table.grow`/`memory.grow`; and cleanup returns the bytes. This proves only the
isolated allocator ordering; the generated HTTP result-buffer helper now uses
the same counter, while the Component scheduler and non-HTTP canonical
allocators remain outside the gate.

`cabi-realloc-budget.wat` is the matching direct allocator probe. Run
`test_cabi_realloc_budget.sh` to verify grow/shrink usage, failed-growth
rollback (including unchanged heap ownership), and quota rejection. It keeps
the production `cabi_realloc` failure-as-trap behavior; its internal try path
exists only to observe the rollback state after a deliberately failed
`memory.grow`.

Successful output is evidence that this exact Wasmtime binary accepts and runs
the minimal Core GC artifact. It is not evidence of Component Model async,
WASI Preview 3, host linking, structured cancellation, resource cleanup, or
complete WASI support; those require their own probes and acceptance matrix.
