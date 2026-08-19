# Root-Owned Async Call with One Scalar Argument

**Status:** probe stage; no compiler or public-language change is admitted.

## Goal

Measure whether the existing root-owned local-frame route can preserve one
guest `u32` argument while a helper waits for the registered zero-payload async
host operation. The helper remains an internal continuation; the Component has
only the existing `run` async export.

## Exact Source Shape

```do
work = @host("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper(value u32) -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    child Future<nil> = @async(helper(7))
    @await(child)
}
start() {}
```

The WIT package remains `do:generic-async-call-probe@0.1.0`; only the guest
frame shape changes. There is no WIT parameter for `value`.

## ABI Contract

The root frame stores `value` before entering `helper`. The callback resumes
the helper from the same frame and reads the slot before child cleanup. The
frame order is:

```text
waitable-set -> host subtask -> helper state -> u32 argument
```

The helper has no independent `[task-return]helper` endpoint. Terminal cleanup
is ordered child/subtask first, then waitable set, then the root frame. A
cancelled path may release the frame and live child exactly once, but it never
rolls back the host operation.

## Probe Boundary

The hand-authored Core WAT must be accepted by both pinned toolchains:

- current Component tooling: `wasm-tools 1.255.0 (76e20611d 2026-07-30)`;
- legacy async assembler: `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)`.

The probe must reject or remain outside scope for a second argument, a
non-`u32` argument, helper payload, two live children, nested helpers,
resource/Stream payloads, and legacy `async` declarations. These are compiler
admission boundaries, not additional ABI work in this probe.

## Success Criteria

- Core WAT parses and the WIT custom section attaches on both pinned versions.
- Component creation with `--skip-validation` and validation with
  `cm-async,cm-more-async-builtins` pass.
- The output contains argument-store, argument-load, parent-resume, and
  child-cleanup markers, and no helper `task-return` import.
- No registry row or public ownership syntax is added by this probe.

## Stop Conditions

Any pinned assembly rejection, missing frame value at callback time, helper
task endpoint requirement, or cleanup order ambiguity is a no-go for the
scalar-argument adapter. Record the exact stderr and leave the existing
no-argument adapter unchanged.
