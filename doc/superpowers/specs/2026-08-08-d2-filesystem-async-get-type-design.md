# D2 `descriptor.get-type` Async Filesystem Design

**Status:** complete; the private compiler admission and full regression gates
are green. This design still authorizes only the pinned `descriptor.get-type`
method and does not authorize general filesystem async lowering.

## Goal

Prove one narrow real-filesystem async operation before attempting general
WASI filesystem async lowering:

```wit
descriptor.get-type: async func() -> result<descriptor-type, error-code>
```

The operation has a borrowed resource receiver in the Component ABI, a scalar
variant result, no stream/future payload resource, and no external side
effect beyond observing a local descriptor. The probe must establish the
actual async task-return imports and result representation; those facts must
not be inferred from the synchronous `descriptor.sync` ABI.

## Pinned Source and Tools

The upstream source is the checked-in WASI package at:

```text
source commit: 90fed3c6adf53f112c4dea56851728557bb73799
source path: src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16
types path: deps/filesystem/types.wit
types SHA-256: 8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f
```

The hand-authored WIT is a narrow mirror of that package. It keeps the exact
package/version, interface name, method name, enum member order, and resource
receiver, while omitting unrelated filesystem methods. The probe records a
separate mirror hash; the mirror hash must never be presented as the upstream
package hash.

The required toolchain evidence is:

| Tool | Version / identity |
| --- | --- |
| Zig | `0.16.0` |
| wasm-tools capability probe | `1.255.0 (76e20611d 2026-07-30)` |
| wasm-tools legacy async assembly | `1.254.0 (bb58fdf91 2026-07-20)`, SHA-256 `cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6` |
| Rust/Cargo | `1.97.1` |
| Wasmtime | `47.0.2` |

The legacy binary is used for `cm-async,cm-more-async-builtins` assembly when
the current tool rejects or changes the async custom-section contract. The
current tool remains the capability/hash probe and must be checked explicitly.

## WIT Mirror Contract

`examples/p3-runtime/wit/wasi-filesystem-get-type.wit` contains only the
following public shape:

```wit
package wasi:filesystem@0.3.0-rc-2025-09-16;

interface types {
  enum descriptor-type {
    unknown,
    block-device,
    character-device,
    directory,
    fifo,
    symbolic-link,
    regular-file,
    socket,
  }
  enum error-code {
    access,
    already,
    bad-descriptor,
    busy,
    deadlock,
    quota,
    exist,
    file-too-large,
    illegal-byte-sequence,
    in-progress,
    interrupted,
    invalid,
    io,
    is-directory,
    loop,
    too-many-links,
    message-size,
    name-too-long,
    no-device,
    no-entry,
    no-lock,
    insufficient-memory,
    insufficient-space,
    not-directory,
    not-empty,
    not-recoverable,
    unsupported,
    no-tty,
    no-such-device,
    overflow,
    not-permitted,
    pipe,
    read-only,
    invalid-seek,
    text-file-busy,
    cross-device,
  }
  resource descriptor {
    get-type: async func() -> result<descriptor-type, error-code>;
  }
}

interface probe {
  use types.{descriptor, descriptor-type, error-code};
  run: async func(directory: own<descriptor>) -> result<descriptor-type, error-code>;
}

world get-type-probe {
  import types;
  export probe;
}
```

The WIT `own<descriptor>` spelling is private probe syntax. Do source remains
without pointers, references, lifetimes, or public `own<T>`/`borrow<T>`/`ref<T>`
types.

## Core and Component ABI

The hand-authored Core module is generated from the mirror with the pinned
legacy async metadata and then checked in as the canonical probe. The probe
must contain exactly one root async export and the imports needed for:

- descriptor receiver handle use;
- the `descriptor.get-type` async-lower operation;
- its task-return/result completion path;
- descriptor resource drop.

The ABI script records the exact import names, function type indices,
task-return parameter words, result tag width/alignment, and resource-drop
signature. It compares those facts on every run and fails closed on any
package, method, import, type, or layout drift. No compiler registry entry is
created from a WIT signature alone.

## Do Admission Shape

After the canonical probe and host matrix are green, the private compiler
adapter may admit only this source shape:

```do
get_type = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-type", (Dir) -> DescriptorType | FileError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
DescriptorType error = Unknown | Directory | RegularFile
FileError error = Io | NoEntry

run(directory Dir) -> nil {
    pending Future<DescriptorType | FileError> = get_type(directory)
    result DescriptorType | FileError = @await(pending)
}
start() {}
```

The source union is the ordinary Do surface. The private WIT Component
adapter maps it to the measured result tag/payload and does not expose the
WIT `Result<T,E>` spelling to ordinary APIs.

The adapter rejects an unregistered locator, a changed package/version,
unknown enum/error arms, a second await or child, branches, loops, `defer`,
payload resources, `borrow<T>`, `list<T>`, arbitrary expressions, and any
other filesystem method before WAT emission.

## Runtime Matrix and Cancellation

The Rust host uses one Component and one Wasmtime Store per mode invocation. It
creates a temporary root containing one regular file and one directory. The
descriptor resource carries a `PathBuf`; `get-type` maps `metadata().is_dir()`
to the measured enum arm and maps a missing path to `no-entry`.

The required modes are:

| Mode | Required behavior |
| --- | --- |
| `ready-directory` | one call, immediate `directory`, no external wake |
| `ready-regular` | one call, immediate `regular-file`, no external wake |
| `pending` | one call, one host wake, one completion, `directory` result |
| `error` | one call, explicit `no-entry`, no silent success/default |
| `cancel` | cancellation before completion, no second completion, exactly-once task/descriptor cleanup |

Every mode must end with `table-empty=true`. Cancellation terminates the
guest task and releases live Component resources; it does not undo the
filesystem metadata lookup if that lookup was already issued.

Wasmtime 47.0.2 does not cancel a guest task when a host-side
`call_concurrent` future is dropped; its public documentation limits hard
cancellation to dropping the whole Store. The runtime `cancel` mode therefore
uses a separate test-only `get-type-cancel-probe` Component, with the same
filesystem method and host implementation, that exports an async `cancel`
control endpoint. That endpoint invokes the async-prefixed `[subtask-cancel]`
intrinsic on the pending host `get-type` child. The root callback then performs
the normal subtask/resource/table cleanup. The control WIT/Core files are
probe-only and are not a Do surface, registry descriptor, or compiler lowering.

## Stop Conditions

Stop before manifest/registry/codegen changes when any of these occurs:

1. The pinned toolchain cannot assemble the mirror with the async features.
2. The generated Component does not expose a stable `get-type` async import
   and task-return contract.
3. The Rust host cannot drive ready, pending, error, and cancel without a
   duplicate completion or a non-empty resource table.

When stopped, record the complete command, tool versions, diagnostic, and
recovery condition in `doc/pending_blocked.md`. A green WIT parse alone does
not close D2 or authorize compiler lowering.
