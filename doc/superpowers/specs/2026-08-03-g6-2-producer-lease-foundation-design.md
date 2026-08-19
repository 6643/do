# G6.2 Producer Lease Foundation Design

**Status:** Approved for planning on 2026-08-03.

## Goal

Replace the current token-order-only `StreamWriter<T>` ownership check with a
small path-sensitive semantic analysis that can prove affine producer-lease
cleanup across lexical control flow. This phase stabilizes the ownership
contract; it does not open general async-call lowering or a new source-level
ownership syntax.

## Evidence and Current Boundary

The current implementation is in `src/build/sema_async.zig`. It records writer
bindings as `{ name, decl_idx, element_type, active }`, scans one token stream,
tracks `block_depth` and `has_prior_return`, and marks a binding inactive when
it is transferred or finalized. This is deliberately conservative, but it
cannot distinguish all paths through nested `if`, loops, early returns, or
lexical `defer` scopes.

The existing accepted surface is already covered by the writer fixtures in
`src/build/test/check` and the Component/Rust gates under
`examples/p3-runtime`. The public contract remains:

- `StreamWriter<T>` is an affine producer lease.
- A same-typed binding or an explicitly registered helper call transfers the
  lease; the source owner is unusable afterward.
- `close(writer)`, `abort(writer, err)`, and `defer close(writer)` are the only
  recognized finalization forms.
- A lease is not implicitly copied, dropped, or converted to `own<T>`,
  `borrow<T>`, or `ref<T>`.
- Existing descriptor-specific Component lowering remains the only runtime
  lowering for producer paths.

## Non-Goals

This phase does not:

- add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax;
- implement general async function-call lowering;
- accept arbitrary producer expressions or arbitrary stream element layouts;
- add a sixth forwarding hop or a seventh nested resource level;
- implement borrowed/list/variant resource fields;
- change cancellation to rollback external side effects;
- switch ARC and Wasm GC backends or add a host scheduler.

## Semantic Model

### Lease identity

Each writer binding receives one semantic lease identity. A binding name is only
the current source-level view of that identity; creating another same-typed
binding creates a new view and consumes the old view. The analysis never models
the writer as a copyable scalar.

### States

The analysis uses the following per-binding states:

| State | Meaning | Valid next operations |
| --- | --- | --- |
| `owned` | The binding is the unique live owner. | write, same-typed transfer, registered helper transfer, close, abort, register `defer close` |
| `owned_deferred` | The binding is still the live owner and a cleanup is registered for the current lexical scope. | write, same-typed transfer only if the defer scope moves with the owner, scope exit |
| `moved` | Ownership was transferred to another binding or approved helper. | no use of the source binding |
| `finalized` | `close` or `abort` has consumed the owner, or the registered defer ran on an exit path. | no use |
| `maybe` | Different incoming paths disagree about the state. | no writer operation; report a path-sensitive diagnostic |

`owned_deferred` is still writable before scope exit. A second finalizer for
the same lease is invalid. A transfer out of a deferred scope is rejected in
this phase unless the defer registration is provably transferred with the
owner; this keeps cleanup ownership explicit rather than guessing at runtime
scope behavior.

### Transfer and finalization

1. A same-typed local binding consumes the source and creates an `owned` target.
2. A registered helper transfer consumes the source and creates no caller-side
   owner; the helper's own analysis must finalize its parameter.
3. A write requires `owned` or `owned_deferred` and leaves the state unchanged.
4. `close` or `abort` requires `owned` and changes it to `finalized`.
5. `defer close(writer)` requires `owned`, registers one cleanup in the current
   lexical scope, and changes it to `owned_deferred`.
6. Any use of `moved`, `finalized`, or `maybe` is rejected at the source operand.

### Control-flow transfer and joins

The analyzer evaluates statements into a small flow result:

```text
Flow = Continue(LeaseEnv) | Return(LeaseEnv) | Break(LeaseEnv) | ContinueLoop(LeaseEnv)
```

Only reachable flows participate in a join. A branch with no `else` joins its
body result with the incoming environment. A join requires equal state and
equal defer-registration for each live lease; a disagreement produces
`maybe`, which is rejected if the binding is used or if the function can leave
with an unfinalized owner. This intentionally keeps the first implementation
conservative and makes `if (...) close(writer)` invalid unless every reachable
exit finalizes the lease.

At `return`, `break`, `continue`, and normal lexical scope exit, the analyzer
applies the existing defer rule in LIFO order. An `owned` lease without a
registered cleanup is an error; `owned_deferred`, `moved`, and `finalized` are
valid only when their scope/transfer obligations are satisfied. Return values
are not changed by cleanup analysis.

### Helper calls

The analyzer receives the existing descriptor-specific helper classification
from `sema_async.zig`. A call is a lease transfer only when it is already in the
registered producer shape. All other async calls remain rejected by the
existing lowering guard and do not mutate the lease environment. This prevents
the semantic foundation from silently becoming general async-call lowering.

## Module Boundaries

- Create `src/build/sema_stream_lease.zig` as a leaf semantic module. It owns
  lease states, flow environments, statement-level transfer/finalization
  events, and unit tests. It imports only `std`, `lexer.zig`, and
  `sema_tokens.zig`.
- Keep `src/build/sema_async.zig` as the public async orchestrator. It collects
  async function ranges and delegates writer analysis to the new leaf module;
  existing Future/Stream reader checks remain unchanged in this phase.
- Keep diagnostics in `src/build/diag.zig`; add only diagnostics needed to
  distinguish path disagreement or invalid defer transfer from existing
  `StreamWriterAlreadyFinalized` and `StreamWriterLeaseDropped` errors.
- Do not change `src/build/codegen_component_stream_writer.zig` lowering except
  for tests that prove accepted existing plans still use the same Component
  output and unsupported forms remain rejected.

## Error and Compatibility Rules

- Existing diagnostics keep their meaning and text unless a new path-sensitive
  case needs a distinct diagnostic.
- A previously accepted bounded fixture must remain accepted and produce the
  same WAT/WIT/component artifacts.
- A previously rejected general async call, arbitrary producer expression,
  conditional cleanup, or unsupported resource shape must remain rejected.
- No diagnostic may silently fall back to synchronous code generation.

## Verification Contract

The phase is complete only when all of the following are true:

1. New semantic unit tests cover state transitions and all reachable-flow join
   cases.
2. New `.do` check/error fixtures cover branch, loop, early return, nested
   defer, transfer, duplicate finalization, and helper-transfer cases.
3. Existing focused Zig tests and both default and `RUN_WASM=1` regression suites
   pass with their current baselines.
4. Existing Component/Rust/Wasmtime producer gates pass without artifact drift.
5. `doc/spec_rules.md`, `doc/async-design.md`, `doc/pending_blocked.md`,
   `doc/roadmap_status.md`, and `doc/start_here.md` state that lease analysis
   is improved while general producer lowering remains pending.

The phase does not claim G6.2 is fully closed. A separate design is required
before admitting a new general producer runtime shape.
