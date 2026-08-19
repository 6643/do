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

Use the unified external-WIT host binding surface for the private source shape:

```do
advise_descriptor = @host_async_func(
    "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "descriptor.advise",
    (File, u64, u64, Advice) -> nil | AdviseError
)
File = @host_resource("filesystem/types/descriptor", { .id i64 })
Advice = @host_enum("filesystem/types/advice", {
    Normal = "normal",
    Sequential = "sequential",
    Random = "random",
    WillNeed = "will-need",
    DontNeed = "dont-need",
    NoReuse = "no-reuse",
})
AdviseError error = Io | Invalid | BadDescriptor

run(file File, offset u64, length u64, advice Advice) -> nil | AdviseError {
    pending Future<nil | AdviseError> = advise_descriptor(file, offset, length, advice)
    return @await(pending)
}

start() {}
```

`Advice` is a closed, unit-only WIT enum mirror. The left side of each mapping is
the local Do branch name and the quoted right side is the exact WIT arm name.
The declaration order is the WIT discriminant order. The compiler must not
infer kebab-case names or accept hand-written numeric discriminants.

| Observed discriminant | WIT arm |
| ---: | --- |
| `0` | `normal` |
| `1` | `sequential` |
| `2` | `random` |
| `3` | `will-need` |
| `4` | `dont-need` |
| `5` | `no-reuse` |

The numeric column records the pinned ABI observation only; source code uses
the named `Advice` branches rather than numeric literals.

The compiler shape accepts only the exact method declaration, one direct
`@await`, a synchronous empty `start`, and linear control flow. The runtime
probe must exercise all six named branches. A raw discriminant outside the
complete `0..5` range is not a successful WIT enum value; the Component
boundary or host adapter must reject it explicitly rather than silently
remapping it.

No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, or
generic filesystem syntax is added. All external WIT declarations generated for
the host-facing import surface use the `@host_*` family: `@host_func`,
`@host_async_func`, `@host_resource`, `@host_record`, and `@host_enum`.
`@host_variant` remains reserved for a separately designed WIT `variant`
mapping. The locator, rather than the marker prefix, identifies `wasi:`,
custom, and private WIT packages. WIT exports and direct component-to-component
links are outside this design. The default emitter keeps
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
- an advice source type other than the exact `Advice` `@host_enum` mirror;
- an incomplete, reordered, duplicate, or mismatched WIT arm mapping;
- `@host_variant` used for the WIT `enum` `advice` type;
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
| `ready-normal` | `Advice.Normal`, exact offset/length, one host call, unit completion, exactly-once cleanup |
| `ready-all-advice` | all six named `Advice` branches reach the matching WIT arms without remapping |
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

### Private `u32` advice value

Keep the advice argument as `u32` and validate its range only at the host
adapter. This would reduce the compiler type-binding work, but it would hide
the WIT enum contract from source and permit an untyped value to reach the
boundary. It is rejected in favor of the explicit `@host_enum` mirror.

### Convention-derived enum names

Use `Normal | Sequential | Random | WillNeed | DontNeed | NoReuse` and infer
the WIT names by converting PascalCase to kebab-case. This is shorter, but it
silently guesses an external ABI spelling and cannot represent exceptions or
legacy names. It is rejected in favor of explicit mappings.

### `descriptor.read-via-stream`

This has greater end-user value but combines a stream, a future, a resource
lifetime, EOF/error completion, and cancellation ordering. It is a separate
high-risk design and remains pending after this scalar/enum slice.

## Acceptance And Handoff

The design is accepted only when the ABI probe records the current tool hash,
upstream WIT hash, mirror hashes, exact Core signature/layout, and the full
`@host_enum` mapping. After user review of this file, the implementation plan
may define the probe, compiler, fixture, Rust/Wasmtime, and documentation
tasks. Until then, the existing `descriptor.set-size` slice and unrelated
uncommitted worktree changes remain unchanged.
