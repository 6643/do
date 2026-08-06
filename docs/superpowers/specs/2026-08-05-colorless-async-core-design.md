# Colorless Async Core Design

**Status:** approved for implementation planning.

**Goal:** remove the source-level async-function color while keeping explicit
task creation, waiting, cancellation, and affine cleanup.

## Canonical Source Surface

The core operations are compiler intrinsics and use the `@` namespace:

```do
task Future<T> = @async(foo(args))
value T = @await(task)
@cancel(task)
```

`async foo(...) -> T` is migration-only syntax and will eventually be removed.
`Future<T>` remains the task handle type during this phase; a second public
`Task<T>` type is not introduced.

## Function Execution Model

All user functions are declared with an ordinary return type. A function may
contain `@await` and is marked internally as resumable by semantic analysis.

- A direct call from a task context executes as a resumable child call in the
  current task and suspends the current frame at `@await`.
- A direct call from a synchronous root creates an implicit root task and drives
  it to completion. The caller still observes the declared return value or
  error; the task handle is compiler-owned and cannot leak into source.
- `@async(call)` always creates an independent eager task and returns an affine
  `Future<T>` handle.
- A normal Do call never produces a `Future<T>` by assignment alone. The source
  form is `Future<T> = @async(call)`. The only direct `Future<T> = call` form is
  a generated binding for a WIT `async func` whose validated manifest declares
  the future effect; wrapping that call would create `Future<Future<T>>`.
- `@await(future)` consumes the handle and returns its result.
- `@cancel(future)` consumes the handle, requests cancellation, waits for the
  task to reach an ABI terminal state, and performs exactly-once cleanup.

This is the required behavior for true colorless async. Rejecting direct calls
to resumable functions would be simpler but would leave semantic async color
in the language and is therefore not the chosen design.

## Ownership and Cancellation

- An owned argument passed to `@async` moves into the task frame.
- A borrowed value cannot escape the call or outlive its owner; unsupported
  nested WIT borrow shapes remain explicit capability failures.
- A Future must be consumed exactly once by `@await` or `@cancel`.
- Dropping an unconsumed Future, awaiting/canceling twice, and polling after a
  terminal state are semantic errors.
- Cancellation observes task/resource cleanup and does not roll back external
  side effects.

## WIT Boundary

WIT `async func` is represented by binding metadata and the component target,
not by a Do `async` declaration. Generated Do bindings use the three core
intrinsics. The host import manifest records whether a member returns a WIT
future/stream and supplies the canonical ABI plan.

WIT-to-Do generation is provided by `do wit bind` / `wit-bindgen-do`. Generated
modules and their `manifest.json`/`wit.lock` are placed under the project-root
`wit/` directory. The colorless async compiler consumes the generated metadata;
it does not infer WIT async behavior from a source function name or from a
generated `async` declaration.

The explicit validation boundary is:

```text
do wit check <wit-input> --world <world> --manifest <wit/manifest.json>
```

This validates the schema, package/world identity, WIT content hash, and every
generated member's async/future/stream/resource effect before a caller relies
on the binding. It also verifies the content hash of every generated `.do`
module, so a changed Future/result signature is rejected before source
checking can rely on it. A mismatch is an error; it is never downgraded to a
synchronous host import. `do wit bind` remains the only producer of this
manifest, and the manifest does not by itself claim generic Component or
Wasmtime lowering.

## Compatibility and Removal

The compiler may accept `async name(...) -> T` during migration and lower it to
the same resumable function metadata. It must emit a deprecation diagnostic in
the migration mode. Once all fixtures, standard-library declarations, and WIT
bindings use the intrinsic form, the old declaration is removed from the
grammar and negative coverage is added for it.

## Acceptance Gates

The design is not complete until all of the following are tested:

1. synchronous direct call to a resumable function through the hidden root
   driver;
2. task-context direct call with suspension and resume;
3. explicit `@async` eager task creation;
4. exactly-once `@await` and `@cancel` consumption;
5. pending, ready, error, early-cancel, and cleanup paths;
6. WIT async import/export metadata without a source `async` declaration;
7. old `async` declaration deprecation and final rejection.

The existing bounded Component/Rust/Wasmtime gates remain the ABI oracle while
the generic lowering is migrated.
