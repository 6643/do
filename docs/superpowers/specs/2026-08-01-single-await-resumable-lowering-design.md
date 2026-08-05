# Single Await Resumable Lowering Design

**Status:** approved for implementation on 2026-08-01.

## Goal

Make one pinned scalar/unit Component async function execute through an
explicit resumable frame instead of relying only on a source-shape template.
The first admitted shape is a `wasi:clocks@0.3.0` async host call with one
`Future<nil>` and one `await`.

The public source syntax does not change. `own<T>`, `borrow<T>`, `ref<T>`,
resources, lists, Result payloads, and Stream operations are outside this
slice.

## Accepted Source Contract

The first red/green fixture uses this pinned descriptor and a local value that
must survive the suspension:

```do
wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

async run(input u64) -> nil {
    deadline u64 = @add(input, 1)
    pending Future<nil> = wait_for(deadline)
    await(pending)
    after u64 = @add(deadline, 1)
    _ = after
    return
}

start() {}
```

The descriptor must be found in the pinned registry and must have the
registered scalar/unit canonical shape. The Component target remains explicit:
`--p3-async-component`. Ordinary `do build` continues to return
`AsyncLoweringUnavailable` for this and every other async source program.

## Frame And State Model

`codegen_async_model.AsyncFunctionPlan` remains the source of truth for frame
metadata. The lowering consumes its `FrameModel` and `FrameLayout` without
re-scanning the source body in the emitter.

The frame contains the existing state, waitable-set, cleanup flags, completion
slot, and scalar live slots. For the accepted fixture, `deadline` is an `i64`
slot visible at the await. The state machine has:

1. an entry state that materializes the host call and records the pending
   state;
2. one resume state that observes the completed Future and emits statements
   after `await`; and
3. the existing cleanup state, reached by normal return, cancellation, or
   failure.

The generated WAT must contain explicit state dispatch and markers for the
frame, live slot, resume state, and terminal cleanup. A metadata comment alone
is insufficient: the resume branch must be reachable from the Component task
callback export.

## Cancellation And Cleanup

Cancellation follows the pinned Component/WASI ABI. The emitter observes the
terminal subtask state before dropping the waitable and freeing the frame. It
does not roll back external effects, create an operation broker, emit a custom
cancelled Result arm, or acknowledge cancellation through a Do-level protocol.

Defers run in LIFO order before frame release. The single-await fixture has no
defer, but the emitter must use the shared terminal cleanup helper so later
defer/resource work has one path.

## Non-Goals

- arbitrary user async bodies;
- multiple await sites in this first contract;
- `Future<Result<T, E>>` payload lifting;
- `Stream<T>`, `@next`, producer endpoints, or writer pumping;
- WIT resource own/borrow/drop lowering;
- scheduler policy beyond the pinned Component task/subtask ABI.

## Verification

The implementation is complete for this slice only when all of the following
pass:

- the new source fixture is red before the lowering change and green through
  `--p3-async-component` afterward;
- generated Core WAT has a real resume branch, the `deadline` frame slot, and
  one terminal cleanup path;
- `wasm-tools component embed`, `component new`, and `validate` succeed;
- the Rust/Wasmtime runner observes one pending poll, one external wake, and
  one completion, plus the immediate-ready path;
- `./src/build/test/run_tests.sh` remains `pass=... fail=0` and the ordinary
  async build guard remains covered.
