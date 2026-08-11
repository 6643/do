# D2 `descriptor.advise` Async Filesystem Design

**Status:** approved bounded direction; design and probe only. This document
does not add compiler admission, generic filesystem lowering, or public
ownership syntax.

## Goal

Measure and admit one private, opt-in lowering for the pinned WASI operation:

```wit
descriptor.advise: async func(
    offset: filesize,
    length: filesize,
    advice: advice,
) -> result<_, error-code>
```

The operation provides advisory information about a byte range on an already
open descriptor. It is a method-specific scalar/enum shape: it does not create
a resource, transfer a stream, or carry a string or record payload.

## Decision

Use the existing Do scalar surface for the private source shape:

```do
advise_descriptor = @host_async_func(
    "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "descriptor.advise",
    (File, u64, u64, u32) -> nil | AdviseError
)
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
AdviseError error = Io | Invalid | BadDescriptor

run(file File, offset u64, length u64, advice u32) -> nil | AdviseError {
    pending Future<nil | AdviseError> = advise_descriptor(file, offset, length, advice)
    return @await(pending)
}

start() {}
```

The `u32` advice value is a deliberate private compatibility mapping, not a
new public enum type. The pinned WIT enum order is fixed as follows:

| Value | WIT arm |
| ---: | --- |
| `0` | `normal` |
| `1` | `sequential` |
| `2` | `random` |
| `3` | `will-need` |
| `4` | `dont-need` |
| `5` | `no-reuse` |

The compiler shape accepts only the exact method declaration, one direct
`@await`, a synchronous empty `start`, and linear control flow. The runtime
probe must exercise valid values from the complete `0..5` range. Values outside
that range are not a successful WIT enum value; the Component boundary or host
adapter must reject them explicitly rather than silently remapping them.

No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime,
`@wasi_enum`, or generic filesystem syntax is added. The default emitter keeps
returning `AsyncLoweringUnavailable`; only `--p3-async-component` may select
this future compiler slice.

## Pinned Inputs

The source of truth is:

- `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit`
- upstream `types.wit` SHA-256
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`
- `wasm-tools 1.255.0 (76e20611d 2026-07-30)`
- tool SHA-256
  `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`
- Rust `1.97.1`, Wasmtime `47.0.2`, and Zig `0.16.0`

The probe mirrors must contain only `filesize`, the complete `advice` and
`error-code` definitions, the descriptor resource, and the regular/cancel
probe worlds. Their hashes are produced by the probe task and become part of
the admission record; compiler registration is forbidden before those hashes
and the measured Core layout are recorded.

## ABI Probe

The ABI task must run the current-only `wasm-tools 1.255.0` component embed,
Core parse, Component assembly, and validation path. It must assert:

- exactly one `[async-lower][method]descriptor.advise` import;
- the complete `advice` discriminant order and the `unit | error-code` result;
- the exact flat or indirect Core import signature;
- every indirect parameter-block offset and alignment, if the tool selects an
  indirect call because the receiver, two `u64` values, enum, and result area
  exceed the flat limit;
- the task-return words, result-area tag/payload, async callback, subtask
  cancellation, and descriptor-drop imports;
- no neighboring filesystem method is emitted.

The expected shape is an indirect scalar call because the receiver, two
`filesize` values, enum, and result area exceed the already measured
`descriptor.set-size` direct shape. This is an expectation only: the probe's
current output is authoritative, and any different signature stops admission
until this design is revised.

## Compiler Boundary

Implementation, after the probe is green, consists of one independent
`filesystem_advise` registry row, manifest entry, analyzer, fixed WIT mirror,
and Core template. The analyzer must reject:

- an unregistered or wrong-version locator/member;
- a receiver other than the exact descriptor resource shell;
- offset or length types other than `u64`;
- an advice source type other than `u32`;
- `Result<T, E>` source spelling instead of the ordinary Do union;
- borrowed or resource result payloads;
- a second await, branch, loop, defer, extra host binding, or async root.

The emitter copies both `u64` values and the enum word into the measured frame
or indirect argument block before the host call, retains the descriptor until
unified termination, decodes the unit/error result, and releases the future,
subtask, descriptor, and frame exactly once.

## Runtime And Cancellation Contract

`descriptor.advise` is advisory and does not promise a reversible filesystem
mutation. Cancellation is cleanup-only: it releases guest/Component state and
never invents rollback for an advisory call already issued to the host.

The Rust/Wasmtime runner records the descriptor identity, offset, length,
advice value, host calls, polls, wakes, completions, future drops, pending
future drops, descriptor drops, and `ResourceTable` state. The host callback
must reject an invalid advice discriminant instead of coercing it to another
arm.

## Verification Matrix

| Row | Required observation |
| --- | --- |
| `ready-normal` | advice `0`, exact offset/length, one host call, unit completion, exactly-once cleanup |
| `ready-all-advice` | values `0..5` reach the matching WIT arms without remapping |
| `pending` | both `u64` values and the enum survive one delayed wake; one completion |
| `error` | explicit `Err(io)` or `Err(invalid)` with no fabricated success |
| `invalid-advice` | value `6` is rejected at the Component/host boundary and never treated as a valid arm |
| `cancel` | one pending-future drop and descriptor cleanup, no completion or rollback claim |
| `early-drop` | Store disposal drops the pending future; table state follows the established Wasmtime boundary |
| `repeat` | two calls with different ranges/advice values have independent frames and exactly-once cleanup |

The generated regular Component covers ready, pending, error, all valid advice
arms, and repeat. A hand-authored cancel Component remains separate until its
ABI is measured. The invalid-advice row is an explicit negative boundary and
must not be counted as a successful WIT invocation.

## Stop Conditions

Stop before compiler registration if the pinned tool:

- changes the enum discriminant order or rejects the `advice` shape;
- emits a Core signature or indirect layout different from the measured probe;
- cannot preserve both `u64` arguments across a pending wake;
- permits an invalid enum discriminant to reach the host as a valid arm; or
- produces duplicate/missing completion, future, subtask, descriptor, or frame
  cleanup in any terminal row.

A green `descriptor.advise` gate authorizes only this private method. It does
not authorize `descriptor.read-via-stream`, `write-via-stream`,
`set-times`, borrowed descriptors, generic filesystem async, arbitrary
producer expressions, or public ownership/reference syntax.

## Alternatives

### Fixed `normal` advice only

Hard-code `normal` in the adapter and expose only `(File, u64, u64)`. This
would reduce enum validation risk, but it would not prove the WIT enum mapping
or exercise the method's actual third argument. It is a fallback probe, not the
recommended compiler shape.

### Public `@wasi_enum` advice type

Add a first-class Do enum mirror before this method. That would improve static
range checking, but it expands syntax and semantic surface for one private
method and is outside the current no-new-syntax boundary. It is rejected for
this slice.

### `descriptor.read-via-stream`

This has greater end-user value but combines a stream, a future, a resource
lifetime, EOF/error completion, and cancellation ordering. It is a separate
high-risk design and remains pending after this scalar/enum slice.

## Acceptance And Handoff

The design is accepted only when the ABI probe records the current tool hash,
upstream WIT hash, mirror hashes, exact Core signature/layout, and full enum
mapping. After user review of this file, the implementation plan may define
the probe, compiler, fixture, Rust/Wasmtime, and documentation tasks. Until
then, the existing `descriptor.set-size` slice and the uncommitted release
candidate documentation change remain unchanged.
