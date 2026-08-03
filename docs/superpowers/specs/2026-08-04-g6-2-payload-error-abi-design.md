# G6.2 Payload-Bearing Error ABI Design

**Status:** Draft for user review
**Scope:** Establish a pinned Component ABI gate for WIT error variants with
payload before extending compiler lowering.
**Primary boundary:** `wasi:http/types.error-code` in the pinned
`wasi-http-0.3.0-rc-2025-09-16` WIT.

## Context

The compiler already has the value-level `Result<T, E>` core type and a
bounded private HTTP/resource result path.  The current HTTP service emitter
also assembles for the admitted no-payload error path.  These facts do not
prove that a payload-bearing WIT error can cross the legacy P3 task-return
boundary.

The current pinned evidence is a hard blocker:

- Wasmtime `47.0.2` and the matching `wit-parser 0.252.0` snapshot generate an
  eight-word task-return shape for the complete HTTP error variant.
- Directly supplying the canonical flat values for
  `internal-error(option<string>)` traps during task-return lift.
- Supplying the host-lowered payload produces `InternalError(None)` instead of
  the supplied value.
- The fixed HTTP lowering therefore traps every payload-bearing error arm and
  must not replace its payload with an empty value.

The authoritative details are recorded in `doc/host_abi_blockers.md`; the
pinned source definitions are in
`src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/types.wit`.

## Goals

1. Produce a reproducible, standalone Component probe for the exact pinned
   nested-variant task-return boundary.
2. Distinguish canonical payload layout from host-lowered payload layout using
   observable values, not only a generated signature.
3. Freeze a descriptor shape that can later drive compiler lowering without
   silently discarding payloads.
4. Preserve an explicit unsupported-lowering boundary while the probe is red.
5. If and only if the probe is green, admit the smallest payload shape through
   compiler, Component assembly, and Rust/Wasmtime runtime gates.

## Non-goals

- No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- No general producer lease, borrowed resource, arbitrary stream source, or
  general async-call lowering.
- No change to cancellation semantics; cancellation never rolls back an
  already-issued external effect.
- No inference change for generic calls and no reopening of deferred D2 real
  WASI host runtime work.
- No payload fallback from `Some` to `None`, from a record to zeroed bytes, or
  from an unknown arm to a no-payload error.

## Selected approach

Use an evidence-first sequence:

1. Build the probe independently of the Do compiler, using the pinned WIT and
   pinned `wasm-tools 1.254.0` / Wasmtime `47.0.2` toolchain.
2. Exercise a no-payload control arm, `internal-error(option<string>)`, and
   `DNS-error(DNS-error-payload)`.  The latter covers both an optional scalar
   field and a multi-field record payload.
3. For each payload case, evaluate the canonical representation and each
   documented host-lowered candidate separately.  The probe must identify one
   exact mapping whose Component-side lift observes the supplied payload; a
   candidate that merely avoids a trap but changes the value is rejected.
4. Keep compiler lowering unchanged while the probe is red.  The existing
   HTTP emitter's explicit `unreachable` guards for payload-bearing tags remain
   the required behavior; a source shape that is outside the registered
   lowering still uses the compiler's existing unsupported boundary.
5. Once the probe is green, implement payload metadata and lowering in two
   bounded increments: optional string first, then the DNS record.  Each
   increment receives its own negative and runtime gate.

Directly extending the HTTP emitter from the eight-word signature is rejected:
the signature identifies parameter count, but the current experiment proves
that it does not identify a working payload lift.  Generalizing ownership or
borrow semantics is also rejected because it does not resolve this ABI gate
and would introduce unrelated scheduler and lifetime obligations.

## Probe design

### Fixtures

The probe has a pinned full-WIT fixture and a minimal reproduction fixture.
The full fixture verifies the real `wasi:http` task-return shape; the minimal
fixture makes payload layout failures easier to isolate.  Both fixtures use a
host-driven Component runner and avoid relying on a guest allocator or an
unverified host result buffer.

Each run covers:

| Case | Purpose | Required observation |
| --- | --- | --- |
| `DNS-timeout` | no-payload control | task-return completes without trap |
| `internal-error(None)` | optional payload absence | `InternalError(None)` is preserved |
| `internal-error(Some("x"))` | optional string payload | exact string is preserved |
| `DNS-error({ rcode: Some("...") , info-code: Some(...) })` | nested record payload | both fields are preserved |
| canonical vs host-lowered input | ABI distinction | exactly one documented mapping preserves the value; a trap or value change rejects that candidate |

The runner must report the component validation result, task-return outcome,
decoded payload, and any trap.  A generated signature without execution is
insufficient evidence.

### Probe gate

The probe is **green** only if every supported case validates and lifts the
exact payload through one documented mapping.  A candidate that traps or
decodes to a different value is rejected, even when another candidate works.
If no single mapping covers all supported cases, the payload shape remains
blocked and no compiler lowering is added.  A no-payload control passing
alongside a payload failure does not open the gate.

## Lowering design after a green probe

The compiler extension is descriptor-driven and private at first:

1. Record the WIT package/interface/member, variant discriminants, payload
   field order, alignment, optional representation, and ownership behavior in
   the existing lowering metadata.
2. Preserve the `Result<T,E>` tag and the complete error payload in the result
   area.  The error arm is not represented as a second return value and is not
   inferred from dual presence.
3. Reject an arm when its payload descriptor is absent or unsupported.  Do not
   emit a different ABI that happens to have the same arity.
4. Start with `internal-error(option<string>)`.  Admit the
   `DNS-error(DNS-error-payload)` record only after the first shape has an
   independent runtime gate.
5. Keep the public Do-facing error type coarse until a separate API design is
   approved; this phase is about the private host binding and exact ABI, not a
   public WIT error wrapper.

## Verification sequence

The work is split into independently verifiable gates:

1. **Probe gate:** pinned WIT source, component assembly, canonical and
   host-lowered payload cases, and Rust/Wasmtime execution.
2. **Negative lowering gate:** while the probe is red, generated HTTP WAT
   retains an explicit trap for every registered payload-bearing error tag and
   does not pass an empty payload to `task.return`.  A separate unsupported
   source shape continues to use the compiler's existing diagnostic boundary;
   the fixture asserts the actual diagnostic text or structured error category
   rather than assuming a new name.  No synchronous WAT is emitted as a
   substitute.
3. **First lowering gate:** `internal-error(option<string>)` emits the exact
   descriptor and assembles successfully.
4. **First runtime gate:** pending/ready, success, no-payload error, payload
   error, explicit cancellation, exactly-once cleanup, and empty resource table.
5. **Record lowering gate:** the DNS record payload repeats the same compiler,
   assembly, and runtime checks.
6. **Release gate:** default and WASM regression, Zig unit tests, ReleaseSmall
   smoke, Rust formatting/checks, and `git diff --check`.

Every gate records its command, pinned versions, observed result, and recovery
condition in `doc/host_abi_blockers.md` and the roadmap entry.  A failed gate
updates the blocker evidence and stops only the dependent lowering increment;
unrelated completed G6.2 slices remain usable.

## Acceptance criteria

This design is complete only when:

- the pinned probe either proves exact payload lift or records a reproducible
  blocker with no ambiguous success claim;
- unsupported compiler input cannot silently become an empty payload or a
  different artifact;
- each admitted payload shape has compiler, Component, and Rust/Wasmtime
  evidence for success, error, cancellation, and cleanup;
- existing G6.2 positive and negative matrices remain green; and
- roadmap and blocker documents state the exact admitted shape and the exact
  remaining boundary.

Until the first probe gate is green, this document authorizes no compiler
lowering change.
