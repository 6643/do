# Async, Future, and Stream Design

## Scope

This change replaces the proposed public `do` / `Channel<T>` concurrency
surface with `async`, `await`, `Future<T>`, and `Stream<T>`. It restores an
explicit asynchronous source model without making the language depend on a
specific embedder or runtime implementation.

This specification covers source syntax and semantics, ownership, cancellation,
stream backpressure, and the compiler/runtime boundary. It does not implement
the syntax, the scheduler, a WASI P3 host binding, or a new Wasmtime C API
adapter. `Channel<T>`, `send`, `recv`, and `yield` are not part of the new
public concurrency contract.

## Design Decisions

### One asynchronous function form

The only user-declared asynchronous function form is:

```do
async fetch(url text) -> text {
    return await(host_get(url))
}
```

Calling an `async` function eagerly starts its operation and produces a
`Future<T>`:

```do
pending Future<text> = fetch("https://example.test")
body text = await(pending)
```

The language does not also permit a user function declared as
`f() -> Future<T>`. That former second source form creates two unrelated
meanings for the same public type and makes it unclear whether an import/export
uses a Component Model `async func` or a synchronous function returning a
`future<T>`. A host declaration may still lower an imported WIT `future<T>`
to a language `Future<T>`; it is a boundary operation, not a second user
function declaration form.

`async f() -> Future<T>` is invalid. It would expose a nested scheduling and
ownership contract that the language does not need.

`async f() -> nil` remains valid and uses a unit result internally. `nil` is
not a generic argument, so `Future<nil>` and `Stream<nil>` are invalid.

### Future

`Future<T>` is an opaque, affine handle for one eventual result. It is a
language builtin and cannot be declared, constructed, copied, or inspected by
user code. Its legal producers are an `async` call, a host binding that lowers
to a future, and a compiler-provided combinator.

```do
pending Future<i32> = read_size()
size i32 = await(pending)
```

`await(f)` consumes `f`, suspends only the current async frame, and returns
`T` after the operation reaches its unique terminal state. A consumed future
cannot be awaited, cancelled, assigned, or passed again. Dropping an unfinished
future at scope exit is a compile error unless ownership was explicitly moved
to a supported consuming operation.

The initial surface contains:

```text
await(future)                 -> T | FutureError
await(future, timeout_ms)     -> T | FutureError
await_all(f1, f2, ...)        -> Tuple<...>
await_any(f1, f2, ...)        -> Tuple<usize, ...>
@cancel(future)               -> nil
```

`await_all` consumes all inputs and returns one fixed-layout result per input.
`await_any` consumes all inputs, returns the winning index and result, then
requests cancellation for every losing unfinished input. A timeout starts when
the corresponding await operation begins; it is not a global function timeout.

`@cancel` is idempotent and requests cooperative cancellation. It does not
make a result appear and does not permit reuse of the handle. The scheduler
accepts exactly one terminal state: `Complete`, `Failed`, or `Cancelled`.
If completion and cancellation race, the state accepted first wins; later
events only release retained runtime state and cannot wake a caller twice.

`FutureError` describes runtime control failures such as cancellation, timeout,
or an invalid runtime handle. Business results remain explicit in `T`, for
example `T | IOError`; the compiler must not invent a WIT business-error
variant for `FutureError`.

### Stream

`Stream<T>` is an opaque asynchronous sequence type. It is not a channel and
it does not make a producer/consumer queue the central concurrency primitive.
It is the source-level representation for a host/WIT stream and for the
standard stream constructor:

```text
new_stream<T>(capacity: u32) -> Tuple<StreamReader<T>, StreamWriter<T>>
```

`StreamReader<T>` is single-consumer. `StreamWriter<T>` carries a producer
lease: it may be passed to another async frame, but each transferred lease must
be closed, aborted, or released by its owning scope. The reader and writer are
opaque compiler-managed endpoint values; no closure or callback value crosses
the source boundary.

```do
reader StreamReader<Message>, writer StreamWriter<Message> = new_stream<Message>(16)
write Future<StreamWriteResult> = writer(message)
await(write)
item StreamRead<Message> = await(reader())
defer close(writer)
```

The result protocol is fixed:

```text
reader()       -> Future<StreamRead<T> | StreamError>
writer(value)  -> Future<StreamWriteResult | StreamError>
StreamRead<T>  = Item(T) | Done
```

`Done` is not a `nil` item. `close(writer)` consumes one producer lease; the
reader receives `Done` only after every producer lease is closed or released
and buffered items are drained. `abort(writer, err)` terminates the endpoint;
already accepted buffered items remain FIFO-visible, while pending and later
writes fail as closed. A reader or writer that leaves a scope during
cancellation releases its endpoint ownership after the scheduler acknowledges
its terminal state.

`capacity > 0` specifies bounded buffering and applies backpressure to
`writer(value)` when full. `capacity == 0` is a rendezvous stream. FIFO is
defined after a runtime operation has entered the endpoint queue; source call
order across independently scheduled tasks is not a fairness guarantee.

## Runtime and ABI Boundary

The source model is independent of Wasmtime. The compiler lowers source async
state machines, frame ownership, and WIT metadata to Core Wasm plus component
artifacts using the pinned `wasm-tools` assembly path. A runtime may then load
that artifact and provide WASI imports.

WIT has separate shapes for `async func`, `future<T>`, and `stream<T>`. The
source model maps user `async f() -> T` only to `async func`; host-imported
`future<T>` and `stream<T>` values map to the opaque language builtins. No
runtime-specific C API limitation may change this mapping. In particular, a C
embedder that cannot hand-register a WIT `async func` is an execution-support
gap in that embedder, not a parser, type-system, or component-assembly reason
to retain channels or reject public async syntax.

The initial scheduler uses one runtime drive loop per store and schedules
logical do tasks above it. A host completion is represented by an operation
identifier and one terminal event. This prevents re-entering a store while a
component future is active, while keeping that runtime constraint out of the
language ABI.

## Frame, Resource, and Cancellation Rules

An `await` preserves all values live after the suspension point in the async
frame. It does not run lexical `defer` actions. On normal return, failure, or
acknowledged cooperative cancellation, remaining defers run once in LIFO
order, then owned host resources, futures, stream leases, and the frame are
released. A hard Wasm trap or host process termination does not promise do
language cleanup.

Cancellation first marks the frame as cancelling and prevents new source-level
work from being submitted. It then sends required cancellation requests,
waits for each retained operation to reach one terminal state, executes LIFO
cleanup, and invalidates the frame. A late completion after a cancellation
acknowledgement can only release resources; it cannot resume the invalidated
frame.

## Compiler Boundaries

The implementation must add syntax and semantic checks for `async`, `await`,
`Future`, `Stream`, `StreamReader`, and `StreamWriter`; remove the present
legacy-surface rejection; and update the grammar, specification rules, parser,
sema, code generation, diagnostics, and regression suites together.

It must not restore the old dual declaration ABI, retain `do`/`Channel<T>` as a
parallel public model, or make a Wasmtime C API probe a compiler acceptance
gate. The existing generic component-async probe and the P3 host-binding probe
remain runtime evidence with their current, narrower claims.

## Acceptance Criteria

1. The parser accepts only the async declaration and await forms specified
   here, while rejecting `f() -> Future<T>` user declarations and nested
   `async f() -> Future<T>`.
2. Sema enforces affine Future ownership, a single Stream reader, producer
   lease close/release, and invalid use-after-await/cancel diagnostics.
3. Code generation preserves live values and defer state across every await,
   and produces exactly one cleanup path for each frame terminal state.
4. Regression fixtures cover eager start, await, timeout, cancellation races,
   Future misuse, stream EOF, abort, bounded backpressure, and cancellation
   cleanup.
5. Component lowering tests distinguish compiler artifact assembly from host
   runtime compatibility. Wasmtime C API limitations remain documented but do
   not block compiler syntax or component assembly.
