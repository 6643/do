# WASI P3 lowering draft

> Status: Phase G / G2 compiler-facing lowering contract. G1, G2.1, G2.2 and
> G2.3 are complete for registry-backed result-area metadata, lowering fixtures
> and component/core validation coverage; this is not a claim that executable
> WASI component lowering is implemented.

## Generic component async evidence

`examples/p3-runtime/test.sh` is the executable evidence for one smaller
boundary in the local Wasmtime 47.0.2 C API. It enables component model,
component-model async, and more async builtins; then a component function
enters one host callback defined by
`wasmtime_component_linker_instance_add_func_async`, yields its first
continuation poll, and completes on the second through the same
`wasmtime_component_func_call_async` future. The runner asserts one callback,
two continuation polls, one incomplete call-future poll, and result `27815`.
It runs that sequence both with ordinary core values and with a Core Wasm GC
`struct` allocated entirely inside the embedded core module. The C API enables
`wasm-gc`, but not `component-model-gc`; the component boundary remains a
copied `u32`.

This is **generic component async C API evidence only**. Its custom
`do:component-async-probe@0.1.0` WIT package uses a synchronous source
signature; the asynchrony is intentionally the C host continuation. It does
not establish a P3 package/interface/member, the P3 `task.return` or waitable
ABI, a `@host_func` lowering, component-model GC, or a WASI host binding.
The adjacent `async-wait-for-component.wat` fixture now proves that the pinned
P3 WIT import and its minimal core `task.return` wrapper parse successfully.
It also proves the next boundary is a real C API limitation: manually defining
its provider with `wasmtime_component_linker_instance_add_func_async` fails
with `type mismatch with async`, because that API models an async host
continuation but cannot declare a WIT `async func` provider. The local header
exposes `wasmtime_component_linker_add_wasip2_async` but no
`wasmtime_component_linker_add_wasip3*` helper or lower-level equivalent.
This does not block Component assembly: the compiler's output path is WIT
metadata plus pinned `wasm-tools`, not the Wasmtime C API. It only blocks an
embedding application that wants to hand-register this async provider through
that C API. Runtime execution support is reported separately from compiler
artifact validity.

## References

- WIT format: https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md
- Canonical ABI: https://github.com/WebAssembly/component-model/blob/main/design/mvp/CanonicalABI.md
- WASI 0.3 draft interface list: https://wasi.dev/interfaces

## Boundary

`@host("wasi:package/interface@version", "member", sig)` is a WIT binding declaration, not a
core Wasm import declaration. A Do core WAT module cannot call this directly.
The compiler must first preserve enough binding metadata, then a component
lowering step can generate the canonical ABI shims and component imports.

Current `do build` behavior:

```wat
;; wasi-bind source="entry" alias="host_now" target="clocks/system-clock/now" params="" result="Datetime"
```

The binding identity is `source + alias`.

- `source="entry"` means the compile entry module.
- `source="module-path"` means a recursively imported module.
- `alias` is only local to that source module.
- `target` is the WIT package/interface/member path without a version.
- `params` is the compact comma-separated WIT parameter type list.
- `result` is the compact single WIT result type.

Current `do build` can lower the registered scalar/record/list<u8> subset and
the registered filesystem `result<_,error-code>` /
`result<filesize,error-code>` / `result<tuple<list<u8>,bool>,error-code>`
direct-call subset to `cm32p2` core imports and Do-level wrapper code. The
shipped subset covers the current clocks `Datetime/u64` bindings, scalar
`random/get-random-u64`, and `random/get-random-bytes(u64) -> list<u8>` copied
into Do `[u8]` ARC storage.
The current `descriptor.sync -> result<_,error-code>` increment supports
statement-position ignore and explicit status reads:

```do
status i32 = 0
_, status = host_file_sync(file)
```

The current `descriptor.write -> result<filesize,error-code>` increment supports
both statement-position ignore and explicit two-left-hand-side reads:

```do
written u64 = 0
status i32 = 0
written, status = host_file_write(file, data, offset)
```

The current `descriptor.read -> result<tuple<list<u8>,bool>,error-code>`
increment supports explicit three-left-hand-side reads:

```do
data [u8] = .{}
done bool = false
status i32 = 0
data, done, status = host_file_read(file, size, offset)
```

The current
`descriptor.link-at -> result<_,error-code>` increment supports explicit status
reads with direct string literal paths or Do `text` locals/parameters:

```do
status i32 = 0
_, status = host_file_link_at(old_file, flags, "old.txt", new_file, "new.txt")
```

```do
old_path text = "old.txt"
new_path text = "new.txt"
status i32 = 0
_, status = host_file_link_at(old_file, flags, old_path, new_file, new_path)
```

The current `descriptor.open-at -> result<descriptor,error-code>` increment
supports explicit descriptor/status reads. The WIT path parameter accepts a
direct string literal or a Do `text` local/parameter:

```do
descriptor i32 = 0
status i32 = 0
descriptor, status = host_file_open_at(dir, path_flags, path, open_flags, descriptor_flags)
```

The two WIT `string` parameters are lowered as canonical ABI `ptr,len` pairs.
Direct string literals use static data segments; Do `text` locals/parameters use
their ARC storage payload pointer and length. `[u8]` is raw bytes and is not
accepted as a WIT `string` argument.
At the ordinary Do call boundary, Do `text` parameters and returns are ARC storage
handles; direct string literals in known `text` argument or return positions
allocate storage handles before the call/return.

`status == 0` means ok. Nonzero status is the WIT `error-code` variant index
plus 1, so variant index 0 cannot collide with ok. Converting that status into a
public Do error enum is a standard-library wrapper responsibility; the current
build subset represents `ErrorEnum | nil` as an `i32` with `nil = 0` and error
branches numbered from 1 in declaration order. Resource constructor wrappers
may also use the narrower `UnmanagedStruct | ErrorEnum` build subset: the struct
payload fields are returned first and the final `i32` status is `0` on success
or the public error branch number on failure. The payload part is ignored when
status is nonzero; this is not general arbitrary-union lowering.

The current `descriptor.drop` increment is treated as a resource-drop lowering,
not as a normal WIT resource method. It imports the canonical core drop function
as `[resource-drop]descriptor`, accepts the resource handle, returns `nil`, and
does not emit a fake `drop: func` member in generated WIT:

```do
.host_file_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (descriptor) -> nil)
host_file_drop(file)
```

The current `descriptor.create-directory-at` and `descriptor.remove-directory-at`
increments support explicit status reads with a Do `text` local/parameter path:

```do
status i32 = 0
_, status = host_dir_create_at(parent, path)
_, status = host_dir_remove_at(parent, path)
```

They use the same `status == 0` success convention as other filesystem
`result<_,error-code>` calls. Direct string literal support for these two raw
host bindings is not part of the current direct-call subset; standard-library
wrappers pass typed Do `text` values.

The current `input-stream.read -> result<list<u8>,stream-error>` increment
supports explicit two-left-hand-side reads:

```do
data [u8] = .{}
status i32 = 0
data, status = host_input_read(stream, size)
```

`status == 0` means ok. Nonzero status is the WIT `stream-error` variant index
plus 1. Unknown bindings and complex WIT signatures such as unsupported
`result/resource/variant` combinations still fail when reachable with
`UnsupportedWasiHostImport`.

The current output stream increment supports three explicit result-area forms:

```do
allowed u64 = 0
status i32 = 0
allowed, status = host_output_check_write(stream)

_, status = host_output_write(stream, data)
_, status = host_output_flush(stream)
```

`status == 0` means ok. Nonzero status is the WIT `stream-error` variant index
plus 1. The standard library turns that status into `StreamError | nil` and
does not expose WIT `result` or resource method signatures as public Do types.
The Do wrapper keeps `StreamError` slightly broader than the current WIT
variant: `StreamClosed` mirrors the WIT `stream-error` branch, while
`StreamReadFailed`, `StreamCheckWriteFailed`, `StreamWriteFailed`, and `StreamFlushFailed` are wrapper-
local classifications for host bridge failures. There is currently no
`close_stream` or drop API for streams in the checked-in registry or wrapper.
`output-stream.check-write` is a capacity query, not a write operation; it
returns the writable byte count with the same wrapper error mapping.

`doc/wit/wasi_registry.json` is the current checked-in WIT registry subset. It
contains only the WASI targets and record mirrors that the compiler/test suite
currently knows how to validate. `src/build/test/validate_wasi_bind_manifest.mjs
--registry doc/wit/wasi_registry.json --json <file.wat>` is the current
BindingResolve input artifact. It parses manifest comments into:

```json
{
  "bindings": [
    {
      "source": "entry",
      "alias": "host_now",
      "target": "clocks/system-clock/now",
      "params": [],
      "result": "Datetime",
      "identity": "entry/host_now",
      "known": true,
      "resolved": {
        "package": "clocks",
        "interface": "system-clock",
        "member": "now",
        "params": [],
        "result": "Datetime"
      },
      "shim": {
        "kind": "record-result",
        "params": [],
        "result": {
          "kind": "record",
          "name": "Datetime",
          "fields": [
            { "name": "seconds", "type": "s64" },
            { "name": "nanoseconds", "type": "u32" }
          ]
        },
        "lowering": {
          "component_import": {
            "package": "clocks",
            "interface": "system-clock",
            "member": "now"
          },
          "canonical_abi": {
            "params": ["i32"],
            "results": []
          },
          "core_import": {
            "module": "cm32p2|wasi:clocks/system-clock",
            "name": "now",
            "params": ["i32"],
            "results": []
          },
          "do_result": {
            "kind": "record",
            "name": "Datetime",
            "size": 12,
            "align": 4,
            "fields": [
              {
                "name": "seconds",
                "type": "s64",
                "offset": 0,
                "size": 8,
                "align": 4,
                "core_type": "i64"
              },
              {
                "name": "nanoseconds",
                "type": "u32",
                "offset": 8,
                "size": 4,
                "align": 4,
                "core_type": "i32"
              }
            ]
          }
        }
      }
    }
  ]
}
```

This artifact is still not a full WIT package resolver. `known: true` only means
the target matched `doc/wit/wasi_registry.json` and its compact `params/result`
text was checked. If the registry entry names a record mirror, the JSON includes
that record's field list for the next lowering step. `resolved` is the registry
match split into WIT package/interface/member plus the canonical registry
signature. `shim` is the first lowering plan boundary: scalar params with a
scalar result, registered record result, registered `list<u8>` result, and the
registered `descriptor.sync`, `descriptor.write`, `descriptor.read`,
`descriptor.link-at`, `descriptor.create-directory-at`, `descriptor.open-at`,
`descriptor.remove-directory-at`, and `descriptor.drop` shapes are
marked as lowerable. `preopens.get-directories` is lowerable to do
`[Tuple<Dir, text>]` (resource shells in the first element).
`descriptor.read-directory` and `http/client.send` are registered as known
WASI 0.3 signatures. `descriptor.read-directory` has a dedicated bounded
lowering slice: it accepts one to three statically visible `directory-entry`
reads, awaits the entry and completion futures, and performs exactly-once
stream/future/resource cleanup. The ABI, lowering, and Rust/Wasmtime gates are
`test_do_wasi_filesystem_read_directory_abi.sh`,
`test_do_wasi_filesystem_read_directory_lowering.sh`, and
`test_rust_wasi_filesystem_read_directory.sh`, with bounded multi-read gates
`test_do_wasi_filesystem_read_directory_bounded_lowering.sh` and
`test_rust_wasi_filesystem_read_directory_bounded.sh`.
Generic record-stream lowering remains unsupported: dynamic loops,
payload-bearing completion errors, arbitrary stream sources, and other
filesystem async methods are still rejected.
**G6.3 (scheme B):** `tcp-socket.create/bind/drop` and `udp-socket.create/bind/drop`
are lowerable: create reuses open-at style `result_descriptor_error` (family disc +
result area); bind reuses unit-error with guest-packed `ip-socket-address` pointer;
drop is resource-drop. Public do types use dual `Ipv4SocketAddress` /
`Ipv6SocketAddress`, payload enum `IpSocketAddress = V4|V6`, and resource shells
`TcpSocket` / `UdpSocket` (see `lib/tcp.do`, `lib/udp.do`,
`docs/superpowers/specs/2026-07-13-g6-3-sockets-scheme-b-design.md`).
`http/client.send` uses HTTP request/response resources
and is async in the WIT world, so it is likewise known but unsupported until HTTP
resource/result/async lowering exists. Other complex unregistered
`result/tuple/option/resource/borrow/own/stream/future/variant` signatures are
also marked `unsupported`.


## Declarative host surface (stdlib)

Stdlib modules declare WASI with:

| Form | Role |
| --- | --- |
| `@host("wasi:package/interface@version", "member", sig)` | Sole WASI function binding form; **preferred** do types in `sig` (see below); the old single-locator form is removed |
| `@wasi_resource("…/resource", { .id i64 })` | Resource handle shell (not a WIT record) |
| `@wasi_record("…", { fields })` | Record mirror (field-aligned) |
| `@wasi_enum("…/error-code", arms)` | Optional fine error table; coarse `DirError`/`FileError` may stay plain |

### Preferred do signatures (source)

Host import signatures bind **do types**, not WIT-only wrapper types. Preferred surface:

| Shape | do source | Maps to WIT (manifest) |
| --- | --- | --- |
| Infallible / unit | `() -> Datetime`, `(Dir) -> nil` | record / unit |
| Unit fallible | `(Dir) -> nil \| DirError` / `StreamError \| nil` | `result<_, error-code>` / stream-error |
| Payload fallible | `(Dir, …) -> Dir \| DirError`, `(File, [u8], u64) -> u64 \| FileError`, `(InputStream, u64) -> [u8] \| StreamError` | WIT `result<…>` still stored on manifest |
| Preopens list | `() -> [Tuple<Dir, text>]` | `list<tuple<descriptor,string>>` |
| Resource params | `Dir` / `File` (`@wasi_resource`) | `descriptor` (via `.id`) |
| Bytes / text sugar | `[u8]`, `text` | `list<u8>`, `string` |
| Structures | do `Tuple<…>`, multi-arg flatten, or `@wasi_record` | `tuple<…>` / record — **no** `@wasi_tuple` |

Rules:

- **Preferred:** registered WIT `result<T, E>` uses the ordinary Do form `T | E` in source host signatures when the arms differ. The compiler preserves the WIT `Ok`/`Err` tag internally; a coarse do error enum (`DirError` / `FileError` / `StreamError`) is preferred over a raw status where the binding supports it.
- **Forbidden as WASI result model:** multi-return source shapes such as `-> Ok, Err` or treating dual presence as the host result type (language has no zero values).
- **No type wrappers:** do not introduce `wasi_result` / `wasi_option` / `wasi_list` / `wasi_tuple` (or `@wasi_*` synonyms of those).
- **Keep `@wasi_*`:** only `wasi_func`, `wasi_resource`, `wasi_record`, and optional later `wasi_enum`.
- **Compatibility boundary:** ordinary source uses `T | E` / `T | nil`. WIT `result<…>` spelling and `Result<T, E>` remain only for registered private or same-type ABI probes; manifest/`result=` strings remain WIT.
- **Call sites:** a whole `T | E` is statement-discardable and is inspected with `@is(value, E)` or the corresponding payload type. Multi-lhs unpack may still lower for legacy call patterns, but new source host code binds one union value (or discards the whole call).
- **Public stdlib and host APIs** use union returns (`Dir | DirError`, `File | FileError`, …). Private same-type WIT probes may retain `Result` to preserve an unambiguous internal tag.

Example (stdlib-style):

```do
.host_dir_open_at = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at", (Dir, i32, text, i32, i32) -> Dir | DirError)
.host_file_sync = @host("wasi:filesystem/types@0.3.0", "descriptor.sync", (File) -> FileError | nil)
.host_file_write = @host("wasi:filesystem/types@0.3.0", "descriptor.write", (File, [u8], u64) -> u64 | FileError)
.host_input_read = @host("wasi:io/streams@0.3.0", "input-stream.read", (InputStream, u64) -> [u8] | StreamError)
.host_preopens = @host("wasi:filesystem/preopens@0.3.0", "get-directories", () -> [Tuple<Dir, text>])
.host_dir_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (Dir) -> nil)
```

Known targets still lower via existing strategies (scalar/record/`list<u8>`/result-area/preopens). Codegen stores **WIT** params/result on the binding even when the source used do sugar (`Dir`/`[u8]`/`nil|i32`). Host imports remain in the module import prefix; type bindings follow them.

`wasi_registry.json` remains the official known-target directory for validation; private targets may use the same syntax when a lowering strategy exists (future allow_unknown mode).


## Registered Result Target Inventory

G2 starts from the checked-in `doc/wit/wasi_registry.json` entries below. This
table is the current result/result-area worklist, not a promise that every row is
executable today.

| target | registry result | current status |
| --- | --- | --- |
| `filesystem/types/descriptor.sync` | `result<_,error-code>` | lowerable; preferred do `FileError \| nil` |
| `filesystem/types/descriptor.write` | `result<filesize,error-code>` | lowerable; preferred do `u64 \| FileError` |
| `filesystem/types/descriptor.read` | `result<tuple<list<u8>,bool>,error-code>` | lowerable; preferred do `Tuple<[u8], bool> \| i32` (err arm may stay status) |
| `filesystem/types/descriptor.link-at` | `result<_,error-code>` | lowerable result-area, `_, status`, string/text paths |
| `filesystem/types/descriptor.open-at` | `result<descriptor,error-code>` | lowerable; preferred do `Dir \| DirError` / `File \| FileError` |
| `filesystem/types/descriptor.create-directory-at` | `result<_,error-code>` | lowerable result-area, `_, status`, text path |
| `filesystem/types/descriptor.remove-directory-at` | `result<_,error-code>` | lowerable result-area, `_, status`, text path |
| `filesystem/types/descriptor.drop` | `nil` | lowerable resource-drop, direct `[resource-drop]descriptor`, no ordinary error result |
| `filesystem/preopens/get-directories` | `list<tuple<descriptor,string>>` | lowerable → do `[Tuple<Dir, text>]` (G6.1 A / P3) |
| `io/streams/input-stream.read` | `result<list<u8>,stream-error>` | lowerable; preferred do `[u8] \| StreamError` |
| `io/streams/output-stream.check-write` | `result<u64,stream-error>` | lowerable; preferred do `u64 \| StreamError` |
| `io/streams/output-stream.write` | `result<_,stream-error>` | lowerable; preferred do `StreamError \| nil` |
| `io/streams/output-stream.flush` | `result<_,stream-error>` | lowerable; preferred do `StreamError \| nil` |
| `text/char/echo` | `char` | lowerable scalar, char parameter/result |
| `clocks/system-clock/now` | `Datetime` | lowerable record-result, registered `Datetime` mirror |
| `clocks/system-clock/get-resolution` | `u64` | lowerable scalar |
| `clocks/monotonic-clock/now` | `u64` | lowerable scalar |
| `clocks/monotonic-clock/get-resolution` | `u64` | lowerable scalar |
| `random/random/get-random-bytes` | `list<u8>` | lowerable `list<u8>` result |
| `random/random/get-random-u64` | `u64` | lowerable scalar |
| `filesystem/types/descriptor.read-directory` | `tuple<stream<directory-entry>,future<result<_,error-code>>>` | bounded one-to-three-read lowering and runtime verified; dynamic record streams, loops, payload errors, and arbitrary filesystem async methods remain unsupported |
| `sockets/types/tcp-socket.create` | `result<tcp-socket,error-code>` | lowerable (G6.3 B): family `u8` + result-area; preferred do `TcpSocket \| TcpError` |
| `sockets/types/tcp-socket.bind` | `result<_,error-code>` | lowerable (G6.3 B): handle + packed `IpSocketAddress`; preferred do `TcpError \| nil` |
| `sockets/types/tcp-socket.drop` | `nil` | lowerable resource-drop `[resource-drop]tcp-socket` |
| `sockets/types/udp-socket.create` | `result<udp-socket,error-code>` | lowerable (G6.3 B): same shape as tcp create; preferred do `UdpSocket \| UdpError` |
| `sockets/types/udp-socket.bind` | `result<_,error-code>` | lowerable (G6.3 B): same shape as tcp bind; preferred do `UdpError \| nil` |
| `sockets/types/udp-socket.drop` | `nil` | lowerable resource-drop `[resource-drop]udp-socket` |
| `http/client/send` | `result<response,error-code>` | fixed P3 HTTP service lowering: empty request plus one finite pinned CLI `Stream<u8>` body slice, own request transfer, owned response `Ok`, no-payload `error-code` `Err`; registered `internal-error`/`DNS-error` payloads preserve exact values through pending/ready compiler-service gates; explicit `@cancel(completion)` is additionally lowerable for the registered nil-returning payload-cancellation world; dynamic bodies, trailers, unregistered payloads, implicit/terminal/double cancellation, and general source shapes remain unsupported |

For lowerable scalar/record/list<u8>/filesystem-result signatures,
`shim.lowering` records the component import identity, the concrete `cm32p2`
core import, the canonical ABI core params/results, and the Do-side result
layout. Scalar results return as core values. Record results use an indirect
result-area pointer appended after
the normal scalar params, so `() -> Datetime` lowers to core params `["i32"]`
and no core result. Record layout follows the current Do payload rule: fields
are aligned up to at most 4 bytes and the whole payload is padded to 4 bytes.
This is a plan for the component builder; it is not executable core WAT by
itself.

`--component-plan` is stricter than `--json`: it fails if any binding is
unknown or has `shim.kind = "unsupported"`. When all bindings are lowerable, it
emits the current component-builder input:

```json
{
  "schema_version": 1,
  "imports": [
    {
      "target": "clocks/system-clock/now",
      "package": "clocks",
      "interface": "system-clock",
      "member": "now",
      "params": [],
      "result": "Datetime"
    }
  ],
  "shims": [
    {
      "identity": "lib/time.do/host_now",
      "source": "lib/time.do",
      "alias": "host_now",
      "target": "clocks/system-clock/now",
      "kind": "record-result",
      "lowering": {
        "component_import": {
          "package": "clocks",
          "interface": "system-clock",
          "member": "now"
        },
        "canonical_abi": {
          "params": ["i32"],
          "results": []
        },
        "core_import": {
          "module": "cm32p2|wasi:clocks/system-clock",
          "name": "now",
          "params": ["i32"],
          "results": []
        },
        "do_result": {
          "kind": "record",
          "name": "Datetime",
          "size": 12,
          "align": 4,
          "fields": [
            {
              "name": "seconds",
              "type": "s64",
              "offset": 0,
              "size": 8,
              "align": 4,
              "core_type": "i64"
            },
            {
              "name": "nanoseconds",
              "type": "u32",
              "offset": 8,
              "size": 4,
              "align": 4,
              "core_type": "i32"
            }
          ]
        }
      }
    }
  ]
}
```

`--wit` reuses the same strict component-plan gate and emits a single WIT package
world for the lowerable imports whose members can be rendered by the current
emitter. It supports the current flat function subset and the registered
`filesystem/types/descriptor.sync`, `descriptor.write`, `descriptor.read`,
`descriptor.link-at`, `descriptor.open-at`,
`descriptor.create-directory-at/remove-directory-at`, `descriptor.drop`,
`io/streams/input-stream.read`, and
`io/streams/output-stream.check-write/write/flush` resource method shapes. The
single-file output is intentionally limited to one WIT package, for example all
`clocks/*` imports become:

```wit
package wasi:clocks;

interface system-clock {
  record datetime {
    seconds: s64,
    nanoseconds: u32,
  }

  now: func() -> datetime;

  get-resolution: func() -> u64;
}

world imports {
  import system-clock;
}
```

If a component plan contains multiple WIT packages, `--wit` still fails. Use
`--wit-dir <dir>` for the package graph form. It writes:

```text
<dir>/world.wit
<dir>/deps/<package>/<package>.wit
```

The root `world.wit` uses `package do:imports` and imports each generated
`wasi:<package>/<interface>` dependency. This shape is validated in regression
with `wasm-tools component wit <dir>` when `wasm-tools` is available.

`--core-imports` also reuses the strict component-plan gate. It emits the
deduplicated core WAT import fragment that matches `shim.lowering.core_import`.
This fragment is the next component-builder artifact, not a standalone Do build
output. For the current clocks wrapper it emits:

```wat
  (import "cm32p2|wasi:clocks/system-clock" "now" (func $__wasi_import_clocks_system_clock_now (param i32)))
  (import "cm32p2|wasi:clocks/system-clock" "get-resolution" (func $__wasi_import_clocks_system_clock_get_resolution (result i64)))
```

The generated function symbol is compiler-owned and derived from
`package/interface/member`. Per-source Do aliases still require later shim
functions; `--core-imports` only creates the shared imported function boundary.

`--core-shims` extends `--core-imports` with one compiler-owned core function
per `source + alias`. Scalar results directly return the imported core result:

```wat
  (func $__wasi_shim_lib_time_do_host_resolution (result i64)
    call $__wasi_import_clocks_system_clock_get_resolution
  )
```

Record results keep the canonical ABI result-area shape:

```wat
  (func $__wasi_shim_lib_time_do_host_now (param $__result_area i32)
    local.get $__result_area
    call $__wasi_import_clocks_system_clock_now
  )
```

This artifact is still not the Do-level wrapper body. The compiler's direct WAT
path has a minimal bridge for the registered record-result subset: it uses a
reserved result-area scratch buffer, calls the `cm32p2` import, then loads the
fields into the flattened Do struct return. It also bridges the registered
`list<u8>` result by copying canonical ABI `ptr,len` into Do `[u8]` ARC storage.
Registered filesystem `result<_,error-code>`, `result<filesize,error-code>`,
`result<tuple<list<u8>,bool>,error-code>`, and `result<descriptor,error-code>`
calls are bridged through a
reserved result-area scratch pointer. `descriptor.sync` can be ignored in
statement position or read as `_,status`. `descriptor.write` can be ignored in
statement position or read as `filesize,status`. `descriptor.read` must be read
as `data,done,status`; ok payload offset 4/8 is copied from canonical
`list<u8>` into Do `[u8]`, offset 12 is the bool, and error payload offset 4 is
encoded as `error-code + 1`. `descriptor.link-at` must be read as `_,status`
and accepts direct string literal path arguments plus Do `text` locals/parameters.
`descriptor.open-at` must be read as `descriptor,status` and accepts direct
string literal path arguments plus Do `text` locals/parameters; ok descriptor and
error payload share offset 4, selected by the result tag. All WIT `string`
forms lower to canonical ABI `ptr,len` pairs. `input-stream.read`
bridges `result<list<u8>,stream-error>` through the same result-area scratch:
ok payload offset 4/8 is copied from canonical `list<u8>` into Do `[u8]`, and
error payload offset 4 is encoded as `stream-error + 1`. `output-stream.check-write`
bridges `result<u64,stream-error>` as `allowed,status`, with the ok payload at
offset 8. `output-stream.write` and `output-stream.flush` bridge
`result<_,stream-error>` as `_,status`, with the error payload at offset 4.
A later component-builder step must generalize this beyond the checked-in
scalar/record/list<u8> subset.

`--component-input-dir <dir>` is the current machine-consumable bundle for the
next component-builder step. It reuses the same strict component-plan gate and
writes:

```text
<dir>/metadata.json
<dir>/core.wat
<dir>/core_component.wat
<dir>/component_plan.json
<dir>/core_imports.wat
<dir>/core_shims.wat
<dir>/wit/world.wit
<dir>/wit/deps/<package>/<package>.wit
```

`metadata.json` currently has `schema_version = 1` and relative paths to those
artifacts. `core.wat` preserves the normal `do build` core output. `core_component.wat`
is the same core module prepared for `wasm-tools component new`: the ordinary
`memory` export is removed so the module exposes only the component ABI memory
name `cm32p2_memory`. This avoids the component encoder's "exports multiple
memories" rejection while keeping ordinary core Wasm tests able to use
`exports.memory`.

The same component-ready core WAT can be produced directly by the compiler:

```bash
do build input.do --component-core -o input.component-core.wat
```

This mode still writes core WAT. It does not invoke `wasm-tools`, does not embed
WIT metadata by itself, and does not write a `.component.wasm` file.

The directory itself is not a component wasm, but the current regression suite
can derive and validate a minimal component from it:

```bash
wasm-tools component embed <dir>/wit <dir>/core_component.wat -o embedded.wasm
wasm-tools component new embedded.wasm -o component.wasm
wasm-tools validate component.wasm
```

This proves the current lowerable scalar/record/list<u8>/result-area subset can
enter the component encoder. It does not yet prove runtime execution with a WASI
host, external WIT package resolution, or the unsupported complex WIT types.

`descriptor.drop` is treated as a resource-drop direct core import, not as a
normal WIT resource method. The standard library may declare it privately as:

```do
.host_file_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (descriptor) -> nil)
```

Direct codegen lowers it to the compiler-owned core import name
`[resource-drop]descriptor` with one `i32` handle parameter. The public wrapper
`close_file(file) -> nil` returns after the drop call because the current
resource-drop ABI has no ordinary error result. This direct lowering does not
yet imply full component resource lifetime output.

### Private Resource Probe

`do:resource-probe@0.1.0` is a verified private Component fixture, not a
generic WASI resource implementation. Its pinned `ledger.ticket` flow emits
`create -> borrow-value -> consume` and a separate canonical
`[resource-drop]ticket`; the Wasmtime runner stores tickets in `ResourceTable`.
It does not establish HTTP, WIT future/stream, resource arrays, Component-GC,
or general resource lowering support.

## Lowering Pipeline

```mermaid
flowchart LR
    DoSource[Do source] --> CoreWat[core WAT + wasi-bind manifest]
    CoreWat --> BindingResolve[resolve WIT package/interface/member]
    BindingResolve --> Validate[validate WIT signatures and Do mirrors]
    Validate --> Inputs[component input dir]
    Inputs --> Shim[generate canonical ABI shims]
    Shim --> Component[component wasm]
```

The shipped boundary is `CoreWat` plus a JSON manifest parse artifact with a
scalar/record/list<u8> lowering plan, a stricter component-plan JSON for lowerable
bindings, single-package WIT world generation, multi-package WIT directory
generation, deduplicated core import WAT fragments, per-alias canonical ABI shim
WAT fragments, the `--component-input-dir` bundle, and direct codegen bridges for
the registered scalar/record/list<u8> subset plus the checked filesystem and
stream result-area calls described above. A minimal component can now be produced
from either `core_component.wat` or `do build --component-core` output plus
`wit/` through `wasm-tools component embed/new`. The real external WIT package
resolver, general resource/result/stream/future lowering, WASI host execution
smoke tests and complex wrapper completion are still pending.

## Type Mapping

| WIT type | Private lowering | Public Do wrapper |
| --- | --- | --- |
| `bool` | canonical ABI scalar | `bool` |
| `u8/u16/u32/u64` | canonical ABI scalar | same Do scalar |
| `s8/s16/s32/s64` | canonical ABI scalar | Do `i8/i16/i32/i64` |
| `f32/f64` | canonical ABI scalar | same Do scalar |
| `char` | WIT-only scalar token | no public Do `char` yet |
| `string` | canonical ABI string | public Do `text`; raw bytes use `[u8]` |
| `list<T>` | canonical ABI list | `[T]` only when `T` has a Do representation |
| `record` | field-order-checked mirror | Do `Struct` with matching public fields |
| `tuple<A, B>` | canonical ABI tuple | prefer multi-return in wrapper |
| `option<T>` | canonical ABI option | host/private: `T | nil` preferred; public wrappers only where language allows |
| `result<T, E>` | canonical ABI result | source: `T | E` when arms differ; internal tag always preserved; same-type private probes may use `Result<T, E>` — **not** multi-return as the WASI result model |
| `variant` | canonical ABI variant | Do enum/error enum plus wrapper conversion |
| `flags` | canonical ABI flags | Do value enum or private bitset wrapper |
| `resource` | canonical ABI resource handle | Do struct with private handle field |
| `borrow<T>` | canonical ABI borrowed resource | wrapper-only borrowed handle; no public reference |
| `own<T>` | canonical ABI owned resource | wrapper obtains/returns owning handle |
| `_` | canonical ABI unit/empty result payload | `nil` or no public value |

## Resource Ownership

Do source still has no pointer/reference syntax and no implicit destructor. A
WIT resource is represented publicly as a Do wrapper struct with a private scalar
handle. The current checked wrappers are `File`, `Dir`, `InputStream`, and
`OutputStream`; each uses a private `.id i64` field, for example:

```do
File {
    .id i64
}
```

Rules:

- External modules can pass wrapper values, but cannot construct, read or mutate
  `.id`.
- Opening APIs must validate host return handles before constructing wrapper
  values.
- Closing APIs stay explicit and non-failing, for example
  `close_file(file) -> nil`.
- Dropping a wrapper value does not implicitly close the resource and is not an
  ARC destructor hook.
- `borrow<T>` cannot be exposed as a public Do reference; it is only a private
  wrapper lowering mode for the duration of one host call.
- `own<T>` means the wrapper must define who releases or closes the handle.

## Core Wasm refs vs do syntax (recorded; not implemented)

WASI resource handles (integer table ids) are **not** the same mechanism as
core Wasm `externref` / JS host objects. Do keeps **no pointer/reference
syntax** in source. Strategy (decision only — **no implementation in tree**):

| Core Wasm concept | Do syntax strategy | Status |
| --- | --- | --- |
| `externref` | Future opaque value shell `@host_ref("…")`, parallel to `@wasi_resource` | deferred |
| `anyref` | **No** public syntax | permanent (public) |
| `funcref` | **No** first-class source type; prefer export / callback id; optional later `@host_func` | deferred |
| `i32` as linear-memory pointer | **Never** a do type; only private `@host` lowering (e.g. ptr,len) | current rule |
| resource handle id | `@wasi_resource` + private `.id` (existing) | implemented |

Full write-up: `doc/design/wasm_ref_host_syntax.md`. Do not treat `@host_ref` as
available in stdlib or tests until that doc is promoted and implemented.

## Validation Required Before Executable Lowering

## Verified Filesystem Resource Slice

The opt-in `--p3-wasi-filesystem-preopen-component` target verifies exactly
one pinned real WASI 0.3 flow: `get-directories() ->
list<tuple<own<descriptor>, string>>`, first-entry extraction, borrowed
`descriptor.open-at() -> result<own<descriptor>, error-code>`, direct
`@is(opened, Ok)` payload extraction to File, borrowed
`descriptor.sync() -> result<_, error-code>`, then canonical File and Dir
drops. Do source keeps `@wasi_resource("filesystem/types/descriptor", { .id
i64 })` opaque; the compiler records own/borrow internally. The generated Core
WAT and WIT sidecar assemble with `wasm-tools`, and the Rust host uses
`ResourceTable` to prove one preopen, one open, one sync, two drops, and no
residual resource. It does not claim generic resource-list/result lowering,
arbitrary filesystem APIs, async, or general Component output.

For every `wasi-bind` item:

1. Resolve `target` against the selected WASI 0.3 WIT package set.
2. Check function name and arity.
3. Check each `params` type against the WIT signature.
4. Check `result` against the WIT signature.
5. If a Do struct mirrors a WIT record, verify field names, order and field
   types.
6. If a wrapper maps `result<T, E>` to an error enum, verify all WIT error cases
   have explicit Do branches.
7. If a wrapper maps a resource, verify constructor and close/error paths keep
   ownership explicit.

Current compiler increment:

- Known targets registered in `doc/wit/wasi_registry.json` have a small mirrored
  signature registry in semantic checking.
- If a source declaration uses one of those targets with different compact
  `params/result` text, it is rejected as `InvalidImportDecl`.
- If a known target returns a registered WIT record mirror, semantic checking
  verifies the public Do struct field names, order and field types. The current
  registered mirror is `clocks/system-clock/now -> Datetime { seconds i64,
  nanoseconds u32 }`.
- The manifest validator reads `doc/wit/wasi_registry.json`, repeats the same
  known-target check for generated WAT, and can emit the parsed binding list as
  JSON for the next lowering step.
- `filesystem/types/descriptor.read-directory` has a dedicated bounded
  `--p3-async-component` lowering for one to three statically visible directory
  entries and one completion await. The read-directory scripts freeze the
  pinned Core import names, indexed stream/future operations, Component
  assembly, EOF behavior, and Wasmtime cleanup. Dynamic record streams, source
  loops, payload-bearing completion errors, and arbitrary filesystem async
  methods remain rejected.
  The pinned `http/client/send` source form is instead admitted only by
  `--p3-async-component`, which selects its dedicated service lowering; it
  does not make `--component-plan`, general HTTP resources, or HTTP streams
  executable.
  (`filesystem/preopens/get-directories` and G6.3 sockets create/bind/drop are
  lowerable and not in this bucket.)
- Unknown targets still receive syntax-level WIT type validation only; they are
  not treated as executable until the full WIT package resolver exists.

### HTTP empty-request checkpoint

The first executable request-construction slice is deliberately narrow. Under
`--p3-async-component`, `http-request-empty.do` constructs a request with empty
`fields`, `none` body, an immediately completed
`future<result<option<trailers>, error-code>>` containing `Ok(None)`, and `none`
request options. The request is then transferred once into the existing fixed
`client.send` service probe and awaited as
`HttpResponse | HttpError`; the probe retains the internal WIT result tag.

The Core import and indexed future operations are pinned by
`test_do_http_request_empty_lowering.sh`; the constructor lifecycle is exercised
by `test_rust_http_request_empty.sh`; and the combined request-to-send success /
no-payload-error path is exercised by
`test_rust_http_service_empty_request.sh`. These scripts use the complete
`--p3-wit-package-output` package for composition. A minimal standalone sidecar
with a shortened `error-code` is not interchangeable with the pinned HTTP
task-return ABI and is therefore not used for this combined probe.

This checkpoint does not expose `own<T>`, `borrow<T>`, or `ref<T>` in Do source,
and it does not admit request body producers, dynamic trailers, trailer payload
lifting, unregistered/ready payload-bearing error variants, or general HTTP
resource methods. The two registered payload variants are covered by the
separate pending compiler-service gate.

### HTTP request body stream checkpoint

The admitted shape uses only the pinned CLI stdin descriptor as a finite body
source. The compiler lowers one `Stream<u8>` acquisition, passes its reader as
the `some` arm of `request.new`'s body option, and transfers the resulting
request exactly once to `client.send`. The source completion future is a
separate frame-owned handle and is dropped exactly once after send reaches its
terminal callback. The runtime fixture supplies `[65,66]` for two calls and
checks both success and no-payload `DnsTimeout` paths. The baseline host runner
covers both a ready completion future and a one-poll-pending completion future;
the source completion itself is not polled by this fixed cancellation fixture.

Run `bash examples/p3-runtime/test_do_http_request_body_abi.sh` for indexed
ABI facts, `bash examples/p3-runtime/test_do_http_request_body_lowering.sh` for
Core/Component assembly, and `bash examples/p3-runtime/test_rust_http_request_body.sh`
for Wasmtime ownership and cleanup. This remains a fixed descriptor slice;
arbitrary body producers, dynamic EOF loops, dynamic trailers, unregistered/ready
payload-bearing error variants, and public `own<T>`/`borrow<T>`/`ref<T>`
syntax remain outside the supported language surface.

The separate guest-produced request-body probe is also intentionally bounded.
It creates one capacity-one `Stream<u8>`, passes the readable endpoint to
`request.new`, starts `client.send` before the first write, awaits up to three
literal writes, closes the writer, and awaits the transmission future. The
Component stream ABI is rendezvous-based; the older write-before-request order
is therefore rejected because it cannot make progress without an attached
consumer. Its ABI, lowering, and runtime gates are
`examples/p3-runtime/test_do_http_request_body_producer_abi.sh`,
`test_do_http_request_body_producer_lowering.sh`, and
`test_rust_http_request_body_producer.sh`. This does not imply generic producer
loops, dynamic byte sources, arbitrary stream endpoints, payload-bearing
errors, or public ownership syntax.

The serialized completion variant
`examples/p3-runtime/http-request-body-await-completion.do` awaits the same
source completion before calling `request.new`. It lowers the pinned
`[async-lower][future-read-1]read-via-stream` operation and accepts only a
successful no-payload completion. Its lowering and execution gates are
`test_do_http_request_body_await_completion_lowering.sh` and
`test_rust_http_request_body_await_completion.sh`; pending-once and ready
source futures produce four and two total polls respectively across two calls.
This remains serialized and does not imply general Future/Stream or HTTP
request-body lowering.

### HTTP payload cancellation checkpoint

The opt-in `http-payload-cancel.do` fixture accepts only the explicit
`Future<Result<HttpResponse, HttpError>>` plus `@cancel(completion)` source
shape. The compiler emits the pinned versioned HTTP `[async-lower]send`, request
and response drop imports, and the private service-world export; the Core path
uses fixed `[64,128)` result scratch even though the root returns `nil`. The generated
Component and the Rust/Wasmtime runner observe one request consumption, one
pending future drop, zero response create/drop, and an empty `ResourceTable`.
The same runner also invokes the admitted nonempty DNS payload path twice on
one component instance, proving that an exact release returns the private
canonical string slot for a later sequential call.

This is a descriptor-bounded cancellation gate, not general HTTP cancellation:
the admitted immediate error payloads are `DNS-error` with `rcode=Some(nonempty)`
or `None` and `InternalError` with `Some(nonempty)` or `None`; `None` validates
the option discriminant without reading or releasing pointer/length fields.
The fixed result scratch is exercised only by sequential calls; concurrent calls
on one component instance are not proven by this gate and must not be treated as
concurrency-safe.
Cancel-after-terminal, double cancellation, implicit scope-drop, unregistered
payload tags, dynamic body/trailer shapes, and generic resource/async cancellation
remain rejected.

## First Executable Slice

The first executable P3 slices are scalar/record/list<u8> wrappers, because they
do not require resource lifetime or async lowering:

```do
.host_now = @host("wasi:clocks/system-clock@0.3.0", "now", () -> Datetime)

Datetime {
    seconds i64
    nanoseconds u32
}

now() -> Datetime {
    return host_now()
}
```

Acceptance for that slice:

- `do build` still emits core WAT plus structured `wasi-bind`.
- A later component build path resolves `clocks/system-clock/now` and
  `random/random/get-random-bytes`.
- The generated shim lifts the WIT record into the Do `Datetime` layout, and
  the list result writes `ptr,len` into the canonical result area.
- Direct core `do build` currently bridges registered record results through a
  reserved result-area scratch buffer, bridges `list<u8>` by copying the
  returned bytes into Do `[u8]` ARC storage, and can call registered
  `result<_,error-code>`, `result<filesize,error-code>`,
  `result<tuple<list<u8>,bool>,error-code>`, `result<descriptor,error-code>`
  filesystem functions,
  `result<list<u8>,stream-error>` input-stream reads, and
  `result<u64,stream-error>` / `result<_,stream-error>` output-stream methods
  through their checked result-area bridges. `descriptor.link-at` additionally supports
  direct string literal or Do `text` local/parameter path arguments and
  `_,status` result reads. Ordinary Do `text` call/return positions can now
  lower direct string literals to ARC storage handles, which lets wrappers pass
  Do `text` locals/parameters through to the WIT string bridge. Unknown or
  complex WIT calls are still rejected when reachable.
