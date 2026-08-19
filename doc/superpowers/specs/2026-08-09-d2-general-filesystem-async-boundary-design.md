# D2 General Filesystem And HTTP Async Boundary

Date: 2026-08-09  
Status: boundary design; no generic filesystem or HTTP lowering

## Decision

The three private filesystem methods already have independent ABI and runtime
evidence: `descriptor.get-type`, `descriptor.sync`, and `descriptor.get-flags`.
They remain isolated descriptors. The rest of `wasi:filesystem` and the
`wasi:http` service world require method-specific recovery gates. No compiler
registry entry, generic resource rule, stream rule, or public ownership syntax
is added by this document.

Cancellation follows the existing Component/WASI contract. It cancels live
Component state and releases values still owned by the guest. It never rolls
back a filesystem mutation, network request, or other host effect that was
issued before cancellation.

## Pinned Sources

Filesystem source:

```text
package wasi:filesystem@0.3.0-rc-2025-09-16;
source commit: 90fed3c6adf53f112c4dea56851728557bb73799
types.wit sha256: 8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f
world.wit sha256: 22a2958e41ca0d982add92116c5ba9d3d9ff46ff1df23f4633c6fc36f492ee49
preopens.wit sha256: 941830f054859fa1322ffbc36289cb43f1d798a232dec913ee3ca2dda05546a8
```

HTTP source:

```text
package wasi:http@0.3.0-rc-2025-09-16;
source commit: 7c678c4c10238a4bf4db91a0e27023d680ff65fe
worlds.wit sha256: 4f4bcdd89c8fd3de2fd171d600255b1b4d8157c4c142e8eb4d2e0270f5510670
types.wit sha256: 37477eca8b4a2cdc158e09ca3ddc33b8dfceb752b09e44e4f6e8842e6f6d2a38
```

The current capability probe uses `wasm-tools 1.255.0 (76e20611d
2026-07-30)` with binary SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
Legacy async assembly uses `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)` with
SHA-256 `cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6`.
Runtime evidence uses Rust `1.97.1`, Wasmtime `47.0.2`, and Zig `0.16.0`.

## Closed D2 Anchors

The following rows are closed only for their exact private source shapes:

| Method | WIT signature | Measured Core import | Result/payload | Cleanup evidence |
| --- | --- | --- | --- | --- |
| `descriptor.get-type` | `async func() -> result<descriptor-type, error-code>` | `(i32, i32) -> i32` | component variant `descriptor-type | error-code`; two flat `i32` completion words | one future drop, one descriptor drop; ready/pending/error/cancel; empty table |
| `descriptor.sync` | `async func() -> result<_, error-code>` | `(i32, i32) -> i32` | component variant `unit | error-code`; two flat Result words | one future drop, one descriptor drop; ready/pending/error/cancel; empty table |
| `descriptor.get-flags` | `async func() -> result<descriptor-flags, error-code>` | `(i32, i32) -> i32` | canonical result byte `u8`, promoted flat `i32`; variant `descriptor-flags | error-code` | one future drop, one descriptor drop; ready/pending/error/cancel; empty table |

The reproducible gates are:

```text
bash examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh
bash examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh
bash examples/p3-runtime/test_d2_wasi_filesystem_get_flags_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_sync.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_flags.sh
```

The current run passed all six commands. The private compiler fixtures and
manifest tests remain fail-closed for unregistered methods, wrong result
shapes, borrowed payloads, and second awaits.

## Filesystem Recovery Matrix

The exact signatures below are copied from the pinned `types.wit`. A row is
not admitted merely because its result is `nil | error-code`; the listed stream,
record, resource, string, and borrow obligations are part of the gate.

| Method | Exact WIT signature | Required independent evidence before admission |
| --- | --- | --- |
| `descriptor.read-via-stream` | `func(offset: filesize) -> tuple<stream<u8>, future<result<_, error-code>>>` | stream reader ABI, completion future/error payload, descriptor lifetime, stream/future drop ordering, pending and cancel before/after EOF |
| `descriptor.write-via-stream` | `async func(data: stream<u8>, offset: filesize) -> result<_, error-code>` | producer stream transfer point, writer close/drop, offset `u64` layout, sink error and cancellation after bytes are issued |
| `descriptor.append-via-stream` | `async func(data: stream<u8>) -> result<_, error-code>` | producer stream ownership and close, append effect boundary, pending/error/cancel cleanup |
| `descriptor.advise` | `async func(offset: filesize, length: filesize, advice: advice) -> result<_, error-code>` | two `u64` arguments, enum encoding, result variant, argument cleanup and cancellation |
| `descriptor.sync-data` | `async func() -> result<_, error-code>` | independent method import/result layout and host future cancel/drop counters |
| `descriptor.set-size` | `async func(size: filesize) -> result<_, error-code>` | `u64` argument flat lowering, filesystem mutation no-rollback semantics, error/cancel gate |
| `descriptor.set-times` | `async func(data-access-timestamp: new-timestamp, data-modification-timestamp: new-timestamp) -> result<_, error-code>` | timestamp record/variant layout, two argument ownership states, error/cancel gate |
| `descriptor.read-directory` | `async func() -> tuple<stream<directory-entry>, future<result<_, error-code>>>` | record stream layout (`directory-entry`), stream reader and completion future, directory drop ordering, EOF/error/cancel matrix |
| `descriptor.create-directory-at` | `async func(path: string) -> result<_, error-code>` | string pointer/length transfer, path lifetime, mutation effect, error/cancel cleanup |
| `descriptor.stat` | `async func() -> result<descriptor-stat, error-code>` | `descriptor-stat` record layout, nested enum/integers, result payload and descriptor cleanup |
| `descriptor.stat-at` | `async func(path-flags: path-flags, path: string) -> result<descriptor-stat, error-code>` | enum plus string arguments, record result layout, path and pending/error/cancel ownership |
| `descriptor.set-times-at` | `async func(path-flags: path-flags, path: string, data-access-timestamp: new-timestamp, data-modification-timestamp: new-timestamp) -> result<_, error-code>` | mixed enum/string/record argument layout and mutation cancellation gate |
| `descriptor.link-at` | `async func(old-path-flags: path-flags, old-path: string, new-descriptor: borrow<descriptor>, new-path: string) -> result<_, error-code>` | borrowed receiver validity and scope, two path strings, no public borrow syntax, mutation/error/cancel gate |
| `descriptor.open-at` | `async func(path-flags: path-flags, path: string, open-flags: open-flags, %flags: descriptor-flags) -> result<descriptor, error-code>` | owned descriptor result, resource table transfer/drop, four argument encodings, pending/error/cancel and zero-representation presence |
| `descriptor.readlink-at` | `async func(path: string) -> result<string, error-code>` | string result allocation/release, path transfer, error/cancel gate |
| `descriptor.remove-directory-at` | `async func(path: string) -> result<_, error-code>` | mutation effect, string argument lifetime, not-empty error, pending/error/cancel cleanup |
| `descriptor.rename-at` | `async func(old-path: string, new-descriptor: borrow<descriptor>, new-path: string) -> result<_, error-code>` | borrowed descriptor scope, two string arguments, mutation transfer and cancel cleanup |
| `descriptor.symlink-at` | `async func(old-path: string, new-path: string) -> result<_, error-code>` | two string arguments, mutation effect, error/cancel cleanup |
| `descriptor.unlink-file-at` | `async func(path: string) -> result<_, error-code>` | string argument, mutation effect, is-directory error, error/cancel cleanup |
| `descriptor.is-same-object` | `async func(other: borrow<descriptor>) -> bool` | borrowed descriptor ABI and validity, scalar result, pending/cancel cleanup |
| `descriptor.metadata-hash` | `async func() -> result<metadata-hash-value, error-code>` | two-word `u64` record result, result variant, error/cancel cleanup |
| `descriptor.metadata-hash-at` | `async func(path-flags: path-flags, path: string) -> result<metadata-hash-value, error-code>` | enum/string arguments, two-word record result, path and cancel cleanup |

The already closed `get-type`, `sync`, and `get-flags` rows are intentionally
not reused as a template for these methods. In particular, `read-via-stream`
and `read-directory` have both a stream and a future, `open-at` creates an
owned resource, and `link-at`/`rename-at`/`is-same-object` carry a borrowed
descriptor. Each requires a new canonical frame and ownership matrix.

## External HTTP Gate

The pinned `wasi:http/service` world includes clocks, randomness, stdout,
stderr, stdin, an imported `client`, and an exported `handler`. The exact client
operation is:

```wit
interface client {
  use types.{request, response, error-code};
  send: async func(request: request) -> result<response, error-code>;
}
```

The service handler has the same shape:

```wit
interface handler {
  use types.{request, response, error-code};
  handle: async func(request: request) -> result<response, error-code>;
}
```

HTTP admission needs a separate service-world Component, not only a types-world
function probe. The gate must measure request ownership at the `send` transfer,
response creation and drop, response body stream/future state, optional error
payloads, pending/ready/error/cancel, and repeated calls on one component
instance. A cancellation after the request reaches the host must observe the
external request effect and release only still-live guest resources; it must
not synthesize rollback.

The existing registered `client.send` and fixed payload/error slices are
evidence for those individual shapes only. They do not admit arbitrary request
construction, body producers, response streams, service worlds, or external
HTTP error variants.

## No-Go Boundary

Until the relevant row has the complete gate above, the compiler must reject:

- unregistered filesystem methods and arbitrary `@host_async_func` locators;
- generic `read`/`write` stream or record lowering, including dynamic loops;
- borrowed filesystem arguments/results and `future<borrow<T>>` or borrowed
  stream records rejected by the pinned toolchain;
- owned resource results such as `open-at` without a measured presence/drop
  protocol;
- arbitrary HTTP service worlds, request/response body streams, and payload
  error variants;
- public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, or lifetime
  syntax.

The recovery condition is a new dated design plus pinned WIT hash, canonical
Core WAT, positive/negative fixtures, Component validation, and Rust/Wasmtime
ready/pending/error/cancel cleanup evidence for the exact method. No descriptor
is generalized from a neighboring method.

## Verification Record

Fresh boundary commands on 2026-08-09:

```text
test_d2_wasi_filesystem_get_type_abi.sh       passed
test_d2_wasi_filesystem_sync_abi.sh           passed
test_d2_wasi_filesystem_get_flags_abi.sh      passed
zig test build/p3_filesystem_wit_manifest.zig 2/2 passed
test_do_borrowed_resource_rejection.sh        passed
test_rust_wasi_filesystem_get_type.sh         passed
test_rust_wasi_filesystem_sync.sh             passed
test_rust_wasi_filesystem_get_flags.sh        passed
```

No compiler source or registry changes are part of this boundary record.
