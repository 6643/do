# Host ABI Blockers

## Core Wasm GC Runtime Probe

**Status:** Core GC representation: GO. Runtime/ARC switch: NO-GO pending
Tasks 2, 5, 8, and 9. This is not a Component Model or WASI compatibility
result.

**Evidence:** `examples/gc-p3-runtime/gc-frame.wat` uses an immutable
`struct` for a source value, mutable `struct` fields for a runtime-private
frame, and a mutable `array` queue. `run-wasmtime.sh` runs that fixture with
`/home/_/Public/wasmtime/bin/wasmtime compile -W gc=y` (compile-or-validate)
followed by
`-W gc=y --invoke probe`. The guest traps unless its encoded result is `27815`,
which the script also asserts. The fixture deliberately has no imports and
cannot exercise host ABI behavior.

**Boundary:** passing this probe shows only that the selected Wasmtime accepts
and executes this Core GC instruction subset. It does not establish P3 async
ABI support, canonical ABI lowering, resource cleanup, cancellation, Component
Model assembly, or complete WASI support.

**Unblock condition:** Task 5 must fix scheduler/byte admission; Task 8 must
prove terminal-outcome cleanup; and Task 9 must migrate all active data
lowering and copied ABI wrappers before ARC can cease to be the active backend.
The separate C embedder experiment is not an ARC/GC or compiler gate.

This file records blockers discovered while implementing the generic
`--host-export` Core Wasm ABI. It is intentionally evidence-based: a blocker
does not become a supported fallback merely because the compiler can emit a
partial signature.

## P3 Task-Return Scalar Type Identity

**Status:** unsigned/narrow scalar `Future<Result<T, E>>` payloads remain
blocked in the pinned legacy async runtime; signed `s32` payloads are verified.

**Evidence:** a descriptor-driven `Result<u8,u8>` probe with the same flat core
signature as the verified `Result<i32,i32>` probe compiles, assembles, and
validates with `wasm-tools 1.254.0` and Wasmtime `47.0.2`. The Rust host future
is invoked and returns `Ok(43)`/`Err(199)`, but completion traps at
`task.return` with `invalid \`task.return\` signature and/or options for
current task` (`TaskReturnInvalid`). Replacing the WIT result with
`result<s32,s32>` while keeping the same core frame makes the pending and
immediate executions pass.

**Boundary:** this is not evidence that Do's source-to-core mapping is wrong;
`u8` maps to one `i32` word correctly. It is a pinned Wasmtime/WIT task-return
type-identity limitation. The compiler therefore keeps the source scalar
mapping and WIT type generator tested, but does not register or lower a
runtime-facing narrow/unsigned Result descriptor until a standalone probe
passes.

**Unblock condition:** rerun the same probe against a toolchain revision where
`result<u8,u8>` (and then `bool`, `u16`, `u32`, and signed narrow variants) has
matching import/export task-return type identity and pending/immediate
execution. Do not silently substitute `s32` for the public WIT type.

## Callback Parameters On Host Exports

**Status:** permanently unsupported by the public host-export surface.

**Evidence:** Do function types are parameter-only constraints. They cannot be
stored, returned, or made into public first-class values, and a lambda cannot
capture an outer local binding. A foreign host therefore cannot construct a Do
function value for a public `--host-export` parameter. This is not a missing
closure lifetime mechanism.

**Current protection:** `--host-export` rejects a public function with a
callback parameter using `HostExportCallbackParamUnsupported`.

**Resolution:** redesign that public API as concrete exported functions plus
explicit resources, polling, future/stream delivery, or host-managed static
event registration. Do not add public `funcref`, pointer, reference, or closure
syntax to make this signature appear supported.

## Guest-To-Host Static Callbacks

**Status:** design and implementation blocked; this is distinct from host
exports accepting a callback.

**Evidence:** the target host-binding design declares `@host_func`, but the
current parser accepts only `@host` host imports. Its host parameter grammar
does not accept `FuncType`, so it cannot currently describe a host function
such as `(Button, (ClickEvent) -> nil) -> Subscription`.

**Target contract:** an `@host_func` parameter may contain an inline function
signature only in that host declaration. The compiler lowers the non-capturing
callback to a private per-instance static callback id and emits a typed
dispatcher. `callback_id` is not a Do type, resource, or manifest value.

**Required decisions before implementation:**

- v1 callback result is `nil`; no synchronous result is returned through an
  event callback.
- Callback inputs and outputs use only already-defined canonical copied value
  shapes; no raw ARC handle, pointer, or host object crosses the dispatcher.
- A host must not re-enter the same instance through the dispatcher before the
  registration call returns; later reentrancy requires an explicit runtime
  rule and test suite.
- Callback ids are valid only for the creating instance and must not be reused
  by a disposed instance without an adapter-side instance generation check.

**Unblock condition:** implement `@host_func`, add the restricted inline
callback parameter grammar, freeze dispatcher argument/error/reentrancy ABI,
and add WAT plus host-adapter lifecycle fixtures.

### Adapter Lifecycle Probe

**Status:** the JavaScript-side subscription registry is verified in isolation;
end-to-end Wasm callback delivery remains blocked by the items above.

**Evidence:** `examples/ui-signal/host-runtime.test.ts` verifies dispatch while
live, explicit unsubscribe, a host-retained late listener after unsubscribe,
idempotent instance disposal, disposal of every listener, and rejection of a
new subscription after disposal. The registry identifies subscriptions by an
opaque token object and checks both per-subscription liveness and an
instance-generation value before calling the dispatcher.

**Boundary:** this probe uses fake event targets and a fake static dispatcher.
Its event payload is still an adapter-local `unknown` value, not the canonical
copied JS/Wasm value ABI. It does not claim that `@host_func`, generic
resources, generated callback ids, or a real Wasm instance are implemented.

### Event Pump Probe

**Status:** the adapter has a verified host queue plus scheduled-drain primitive
that does not require a guest async stack or a guest callback value.

**Evidence:** `examples/ui-signal/host-runtime.test.ts` verifies that an idle
pump schedules no work, a synchronous event batch produces one drain, an event
enqueued by a drain runs in a later microtask instead of re-entering the
dispatcher, and instance disposal drops a queued event before its drain runs.

**Boundary:** this is an adapter-local event loop primitive. Its `drain` target
is a fixed host-held function plus `instance_id`; it is not yet a generated
Wasm export, and `nextEvent()` does not yet use the canonical copied value ABI.
It does not implement WIT `stream<T>`, `future<T>`, `pollable`, cancellation,
or TCP/UDP stream lowering.

## Generic Host Resources

**Status:** blocked by missing executable generic host resource declaration.

**Evidence:** `doc/host-binding-design.md` specifies `@host_resource`, but the
current grammar implements only the WASI-specific `@wasi_resource`. A browser
`Button` and a returned `Subscription` therefore cannot honestly be declared
as generic opaque host resources today.

**Required contract:** `Button` and `Subscription` are opaque host resource
handles, never JS object references or numeric values that source code can
fabricate. `unsubscribe(subscription)` explicitly destroys the host listener;
the host removes all remaining subscriptions before instance disposal.

**Unblock condition:** implement the documented `@host_resource` declaration,
its private handle representation, ownership validation, explicit destructor
mapping, and adapter-side disposal behavior. Do not use deferred `@host_ref`
or raw `externref` as a shortcut for v1.

## Generic Struct Parameters

**Status:** concrete generic struct field expansion is supported for the
current unmanaged/managed-scalar/union field shapes.

**Evidence:** `Box<i32>` is accepted by the host-export collector. Its
post-monomorphization field substitution produces one `i32` WAT parameter and
the host manifest reports the same `"wasm_params":["i32"]` sequence in
`src/build/test/compile_ok/341_host_export_generic_struct.*` and the nested
`342_host_export_nested_generic_struct.*` fixture. The shared collector tests
also cover a managed scalar handle, a payload-plus-tag union, and unresolved
generic rejection.

**Current protection:** generic templates and unresolved bindings remain
rejected with `HostExportGenericStructAbiUnsupported`. Managed concrete fields
continue to use their single `i32` ABI value, and union fields use the normal
payload slots followed by an `i32` tag.

**Remaining work:** extend the same record matrix to additional multiword and
resource-shaped fields only after their ownership/host-handle contract is
specified. Canonical JS values and ownership protocols remain outside this
ABI.

## Canonical JS Values

**Status:** not yet designed; it is not a Core Wasm manifest defect.

**Evidence:** `text` is currently an ARC-managed `i32` handle. Lists and
managed structs also use runtime-owned memory layouts. A browser host cannot
safely fabricate, retain, or release these handles from the Core value type
alone.

**Current protection:** the manifest reports both source and Core Wasm value
types, but does not claim a JavaScript object/value conversion or ownership
transfer rule.

**Unblock condition:** freeze the generic JS/Wasm value ABI with allocation,
copy/borrow/transfer ownership, error, and cleanup semantics before adding
`lib/ui.do` host imports.

## WASI HTTP Client ABI

**Status:** fixed executable Component slices exist for the pinned HTTP service,
empty request construction, one finite CLI-stdin request body, response status,
a bounded response-body probe, and a trailers-future read/discard probe; general
canonical lowering and a standard-library binding remain unavailable.

**Evidence:** the compiler vendors the checked upstream `wasi-http` snapshot
`7c678c4c10238a4bf4db91a0e27023d680ff65fe` under
`src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16`. Its manifest test fixes the
`worlds.wit`, `types.wit`, and dependency lock hashes before any future
descriptor can consume the input. The snapshot defines
`wasi:http@0.3.0-rc-2025-09-16/client.send` as
`async func(request: request) -> result<response, error-code>` in
`wit-0.3.0-draft/worlds.wit`. Both `request` and `response` are resources.
`src/build/resource_abi_registry.json` records this exact package/interface
member with an `own` request input and an owned response Result payload; the
registry represents their distinct resource paths without exposing
`own<T>`/`borrow<T>` as Do source types. In particular, `response` exposes
resource methods such as `get-status-code` and `consume-body`; the latter
moves the response and returns a `stream<u8>` plus a trailers `future`.
`request` has the corresponding resource/body ownership rules.

`src/build/p3_async_registry.json` additionally pins the corresponding
`@host_func` source declaration to the WIT `service` world and its exact
`[async-lower]send` import name and records the canonical completion words as
`i32 i32 i32 i64 i32 i32 i32 i32`, including the `i64` payload word emitted by
the pinned toolchain. The `--p3-async-component` target accepts the
exact `async handle(request HttpRequest) -> Result<HttpResponse, HttpError>`
shape where `send(request)` is bound to a Future and immediately returned from
`await`, either directly or through an identically typed Result binding. It
emits the service export, consumes and drops the request, and
returns either an owned response or a no-payload `error-code`. The regression
at `examples/p3-runtime/test_http_service_abi_surface.sh` compiles, assembles,
validates, and invokes that Component concurrently in the Rust Wasmtime host.
`do check` also rejects a second transfer of the async `HttpRequest` parameter.
The async host-import semantic gate accepts only this exact pinned descriptor
shape and defers its service-specific validation to `HttpServicePlan`; an
unknown or otherwise unlowerable descriptor still fails the generic async gate.
Ordinary `do build` and every other async HTTP source form remain guarded.

The service plan now validates the complete nominal resource graph before it is
selected: `fields` (the WIT `headers`/`trailers` alias), `request-options`,
`request`, and `response`, plus the pinned `request.new`, both `consume-body`
operations, and `client.send` signatures. The required Do shells are
`HttpHeaders`, `HttpRequestOptions`, `HttpRequest`, and `HttpResponse`; a source
program with only copied request/response records or an incomplete graph is
rejected. `examples/p3-runtime/test_do_wasi_http_request_shape.sh` covers the
check/build boundary, while `test_http_service_abi_surface.sh` covers the
generated Component ABI and Rust/Wasmtime adapter. This is a shape gate only:
it does not lower request construction, body/trailer streams, or arbitrary HTTP
resource operations.

**Boundary:** `doc/wit/wasi_registry.json` currently records the unversioned
`http/client/send` shape, while `lib/http.client.do` declares copied
`HttpRequest` and `HttpResponse` records. Those records cannot represent the
WIT resource identity, ownership transfer, headers, body stream, trailers, or
async result. Mapping `response` to `{ status u16, body [u8] }` would silently
change the ABI and lose required lifecycle behavior.

**Empty-request checkpoint (2026-08-02):** the compiler now admits one bounded
constructor shape under `--p3-async-component`. It creates empty `fields`, passes
`none` for the request body and options, writes an immediate `Ok(None)` trailers
future, and calls the pinned static `request.new`. The returned request is stored
in the async frame and may be transferred exactly once to the fixed `client.send`
probe. The transmission future and trailers future are explicitly read or
dropped before terminal cleanup. `examples/p3-runtime/test_do_http_request_empty_lowering.sh`
verifies Core/Component assembly, while
`test_rust_http_request_empty.sh` and
`test_rust_http_service_empty_request.sh` verify two independent calls, success
and no-payload `DNS-timeout`, exactly-once lifecycle handling, and an empty
Wasmtime `ResourceTable`.

The standalone minimal HTTP sidecar is intentionally not the composition path:
its shortened `error-code` definition does not match the pinned task-return
shape. The authoritative combined request-to-`client.send` check therefore uses
`--p3-wit-package-output`, which emits the complete pinned types package. This is
a packaging boundary, not a relaxation of the ABI.

**Request-body stream checkpoint (2026-08-02):** one further executable slice
now admits a finite `wasi:cli/stdin.read-via-stream` `Stream<u8>` as the
`request.new` body. The source form is fixed: acquire one reader/future pair,
pass the reader once as `option<stream<u8>>`, transfer the constructed request
once to `client.send`, and release the independent source completion future at
the send terminal callback. The host runner supplies `[65,66]` and exercises
two calls, one successful and one `DnsTimeout`; it observes both body payloads,
two source stream drops, two source future drops, one response, and an empty
`ResourceTable`.

The ABI gate is `examples/p3-runtime/test_do_http_request_body_abi.sh`; the
compiler/component gate is `test_do_http_request_body_lowering.sh`; and the
Wasmtime ownership gate is `test_rust_http_request_body.sh`. The probe also
asserts that an unregistered indexed stream import is rejected by
`component new`. This is an internal WIT/manifest boundary: it does not expose
`own<T>`, `borrow<T>`, `ref<T>`, pointers, or references in Do source.

**Request-body boundary:** only the pinned CLI `Stream<u8>` source and the
linear finite sequence are admitted. Dynamic producers, source-level loops,
arbitrary stream descriptors, dynamic trailers, trailer payload lifting,
unregistered/general payload-bearing error codes, and general HTTP lowering
remain rejected. The separately registered `internal-error` and `DNS-error`
payloads are admitted only by the pending compiler-service gate described
below.

**Guest-produced request-body checkpoint (2026-08-02):** the dedicated producer
probe admits one guest-created `new_stream<u8>(1)`, transfers its readable
endpoint through `request.new`, starts `client.send`, then performs at most
three literal `u8` writes with one await per write, closes the writer exactly
once, and awaits the transmission future. Component streams are rendezvous
operations, so a write before `request.new`/`send` is rejected rather than
treated as an implicit guest buffer. The ABI, lowering, and Rust/Wasmtime gates
are `test_do_http_request_body_producer_abi.sh`,
`test_do_http_request_body_producer_lowering.sh`, and
`test_rust_http_request_body_producer.sh`; the runner observes `[65,66]`, one
pending write, one success and one no-payload error, exactly-once endpoint and
future cleanup, and an empty `ResourceTable`.

This is still a bounded compiler probe. Dynamic producer loops, arbitrary
stream element types or endpoints, producer error mapping, dynamic trailers,
unregistered/general payload-bearing error codes, and public
`own<T>`/`borrow<T>`/`ref<T>` syntax remain outside the admitted surface.

**Remaining boundary:** extend canonical lift/lower for dynamic/general request
bodies, dynamic trailers, trailer payloads, general payload-bearing error-codes,
ready completion delivery outside the registered shapes, general async control
flow, cancellation interaction, and broader resource methods/drop semantics with
component execution fixtures.
Only then may a Do HTTP wrapper choose a copied convenience API above the
resource ABI; it must not replace that ABI.

**Payload error checkpoint (2026-08-04):** the pinned registry now admits only
the descriptor-validated `internal-error(option<string>)` and
`DNS-error(rcode: option<string>, info-code: option<u16>)` shapes. The canonical
ABI probe preserves `InternalError(Some("x"))` and
`DnsError(rcode=Some("EAI"),info-code=Some(7))`; the host-lowered candidate's
`Some -> None` mismatch remains explicitly blocked. The compiler-generated WAT
and Component pending gate now preserve both InternalError values and the DNS
payload, with request consumption, zero response creation, and
`table-empty=true` across pending and ready delivery; the combined entry point is
`examples/p3-runtime/test_do_http_payload_error_lowering.sh all`.
The ready immediate-return path now branches on `Status::Returned` before
extracting a waitable handle, so the former `unknown handle index 0` failure is
closed without weakening payload assertions or silently dropping payload data.
General ready delivery outside the registered shapes and cancellation interaction
remain outside this bounded checkpoint.
`examples/p3-runtime/test_do_http_payload_error_boundary.sh` continues to
verify that every unregistered payload tag retains an explicit trap.

**Payload cancellation discard ABI probe (2026-08-04):** an isolated
`http-payload-cancel` Core module now proves the canonical ownership hand-off
for the pinned immediate
`DNS-error(rcode: Some("EAI"), info-code: Some(7))` path. Component lowering
calls guest `cabi_realloc(0, 0, 1, 3)` for the `rcode` string in the fixed
`[64,128)` result area; the probe validates the result layout and byte payload,
then calls `cabi_realloc(pointer, 3, 1, 0)` exactly once before terminal task
return. Its reallocator traps on a missing, duplicate, or differently-shaped
allocation/release, and the Rust/Wasmtime gate observes one ready-future
poll/drop, zero response resources, and `table-empty=true`. The subsequent
compiler lowering consumes only this string protocol: its private reallocator
permits one nonempty `rcode` allocation in `[128,65536)` at a time, validates
the returned pointer/length on release, and returns the slot to idle for a
later sequential call in the same component instance. It accepts `DNS-error`
with either `info-code` option state. Component/Rust gates cover
`Some("EAI"), Some(7)`, the distinct length/option case
`Some("dns-error-long"), None`, the no-payload `rcode=None, info-code=None`
case, and two sequential `Some("EAI")` calls in one instance. For `Some`, the
string is released exactly once; for `None`, lowering validates only the option
discriminant and does not read or release pointer/length fields. The same
bounded protocol now covers
`InternalError(Some("no"))` and `InternalError(None)`. This is not generic
payload destruction: empty strings, other variants, record/resource payloads,
and unregistered tags retain an explicit trap.

**Response body stream checkpoint (2026-08-01):** the unified Component target
now admits the pinned `response.consume-body` operation for a bounded linear
sequence of one to three successful `stream<u8>` reads or a terminal
`Err(nil)` EOF result. The emitter stores a read index in the async frame,
starts the next read only after an `Ok(u8)` completion, and either cancels the
independent trailers future or performs one explicit `future.read-2` before
exactly-once stream/future/frame cleanup. The one-read, two-read, and three-read fixtures are
`examples/p3-runtime/http-response-consume-body-read.do` and
`examples/p3-runtime/http-response-consume-body-two-read.do` and
`examples/p3-runtime/http-response-consume-body-three-read.do`; their assembly
and Wasmtime checks are
`test_rust_http_response_consume_body_read.sh` and
`test_rust_http_response_consume_body_two_read.sh` and
`test_rust_http_response_consume_body_three_read.sh` and
`test_rust_http_response_consume_body_eof.sh`. The trailers await fixture is
`examples/p3-runtime/http-response-consume-body-await-trailers.do`, with
`test_rust_http_response_consume_body_await_trailers.sh` covering both pending
and ready future delivery. The host runner observes
one response consumption, one stream drop, one trailers-future drop, and an
empty resource table for each admitted length.

**Response body boundary:** this slice does not admit conditional or dynamic
EOF iteration, trailer payload lifting (the future result is currently discarded), request
construction, payload-bearing error-code lowering, or general `client.send`.
Those remain separate blockers and must not be inferred from the bounded
successful-read probe.

## Stream Endpoint Surface

**Status:** the public source contract is selected and parser/sema validation
is implemented. The pinned CLI stdin `u8` Stream slice now has canonical
Component lowering and Rust/Wasmtime execution; generic Stream lowering,
backpressure, and arbitrary stream-producing interfaces remain blocked.

**Evidence:** the vendored pinned WIT tree already supplies a real small
WASI stream boundary: `wasi:cli/stdin.read-via-stream` returns
`tuple<stream<u8>, future<result<_, error-code>>>`. The installed
`wasm-tools 1.254.0` also recognizes legacy `stream.*` and `future.*` Core
operations. The admitted source form is `pending Future<Result<T, nil>> =
@next(reader)`: it retains the caller-owned `Stream<T>`/`StreamReader<T>`,
uses `Ok` for an item and `Err(nil)` for EOF, and leaves an imported completion
`Future<Result<nil, E>>` as a separate explicit future. `recv` remains a
finite `[T]` loop operation and is not reused for a stream.

**Evidence:** `test_do_cli_stream_stdin_lowering.sh` validates the generated
Core/WIT artifacts. `test_rust_cli_stream_stdin.sh` runs the same Component
through Wasmtime twice: once with a pending host Future and once with an
already-ready host Future. The unread completion is released directly with
`future.drop-readable`; neither run polls or calls `future.cancel-read`. Both
runs consume two items, observe EOF, and release the stream and future exactly
once.

The reproducible sidecar is
`examples/p3-runtime/wit/cli-stream-stdin.wit` with SHA-256
`c12c40df23a0ad562e743487b907113dbc9daadafa347d65d151d210d1292fc7`.
The compiler command is `do build --p3-async-component --p3-wit-output`;
`test_do_cli_stream_stdin_lowering.sh` then runs `wasm-tools parse`,
`component embed`, `component new`, and Component validation. The runtime
command is `bash examples/p3-runtime/test_rust_cli_stream_stdin.sh`, which
executes the same Component once with a pending completion and once with an
already-ready completion; both assert items `[97, 98]`, EOF, and exactly-once
stream/Future disposal.

The same descriptor-driven lowering is exercised with a private custom package:
`do:stream-probe@0.1.0` / `source.read-via-stream`. Its explicit registry entry
supplies the canonical module and operation names; the compiler does not infer
them from a locator or member string. `test_do_stream_reader_descriptor.sh`
checks the custom WAT/WIT artifacts, and
`test_rust_stream_reader_descriptor.sh` assembles and executes the Component
with Wasmtime. The host records two items `[97, 98]`, EOF, no completion-future
poll, and exactly one drop for both the stream and completion future.

**Current boundary:** the consumer lifecycle is now generalized to one
registered non-filesystem record stream, and the bounded scalar producer path
is separately verified. The generic consumer admits a validated record layout,
a dynamic `@next`/`await` loop, pending/ready completion, a completion error,
and exactly-once stream/future/resource cleanup. The producer gate admits only
two literal `u8` writes through a capacity-one `StreamWriter<u8>` pump and
selects the registered `do:stream-probe/sink@0.1.0` host instance by descriptor.
General producer leases, general dynamic producer loops, arbitrary element layouts, borrowed/list/variant
resource fields, seventh-level or more general nested resource layouts, and arbitrary WIT stream-producing interfaces remain
outside this runtime path.

**2026-08-02 read-directory ABI checkpoint:**
`examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh` generates
the pinned `wasi:filesystem/imports` world with `wasm-tools 1.254.0` and checks
the exact `[async-lower][method]descriptor.read-directory` import, stream index
`0`, future index `1`, indexed stream/future drops, and the `(i32, i32) -> i32`
method/future-read callback shape. The embedded component type confirms
`directory-entry { type: descriptor-type, name: string }`. This fixed slice now
has compiler lowering, Component assembly, and Rust/Wasmtime execution gates
for one read and for a statically visible two-entry sequence plus EOF probe.
The bounded runner observes `alpha`, `beta`, three stream reads including EOF,
both pending-once and immediately-ready completion futures, exactly-once
stream/future/resource cleanup, and an empty resource table. The fixed slice
remains independently verified; its remaining boundary is arbitrary filesystem
async methods and payload-bearing completion errors.

**2026-08-02 record-layout checkpoint:** the pinned async manifest now carries
validated `directory-entry` Core field facts (`type@0`, `name-ptr@4`,
`name-len@8`). The bounded emitter consumes these registry-owned offsets while
preserving the `frame+64` result-area base and all cleanup transitions. Missing,
unaligned, overlapping, or non-scalar layout facts reject the descriptor; this
does not admit generic record layouts, general dynamic iteration, or arbitrary
filesystem async methods.

**2026-08-02 record-source checkpoint:** `src/build/p3_filesystem_wit_manifest.zig`
now verifies the pinned filesystem WIT source hashes and the source declaration
of `directory-entry` (`%type: descriptor-type`, `name: string`). The async
manifest records the matching `types.wit` hash, and both `@host` and
`@host_func` declarations for the admitted record-stream descriptor reject a
wrong `@wasi_record` target, field order, or Do-side field type. This closes
source/manifest drift for the fixed descriptor only; it does not admit generic
record definitions, dynamic streams, payload-bearing completion errors, or
other filesystem async methods.

**2026-08-02 generic record-stream consumer checkpoint:**
`src/build/codegen_component_record_stream.zig` now emits a descriptor-driven
consumer for the registered `do:record-stream-probe@0.1.0` record stream. The
probe accepts `ProbeEntry { id: u32, label: string }`, drives a dynamic
`@next`/`await` loop with one read in flight, lifts scalar and UTF-8 fields,
awaits the independent completion future, and emits tag/payload completion
results. `test_do_record_stream_probe_lowering.sh` validates the generated
Core module and Component; `test_rust_record_stream_probe.sh` validates
pending, immediately-ready, and `Err(io)` completion modes. The runner observes
`[(1, alpha), (2, beta)]`, EOF, one pending wake only in pending mode, one drop
each for stream and future, and an empty `ResourceTable` after every call.

This closes the generic **consumer** slice of G6.2. A bounded scalar producer
gate and a narrower helper-mediated lease gate are recorded below; general
producer leases, borrowed/nested/variant resource-valued
record fields, payload-bearing completion errors beyond the admitted error
shape, and arbitrary filesystem async methods remain outside this slice.

**2026-08-02 multiple owned resource-field checkpoint:** the same descriptor
driven consumer now admits a private `resource-entry` with two
`own<ticket>` fields. Manifest validation reserves one aligned `i32` slot per
field; WIT declares `ticket` once and the Core module imports
`[resource-drop]ticket` once. The generated release helper keeps the record
active bit around the whole field loop, then checks, drops, and clears every
handle before clearing the bit. `test_do_record_resource_stream_multi_probe_lowering.sh`
and `test_rust_record_resource_stream_multi_probe.sh` validate WAT/WIT assembly
and pending/ready/error Wasmtime execution with four resource drops and an
empty `ResourceTable`. Borrowed, nested/list/variant fields and resource
escape remain rejected.

**2026-08-02 generic stream-writer producer checkpoint:** the bounded guest
`StreamWriter<u8>` pump is now exercised through the registered private
`do:stream-probe@0.1.0/sink.write-via-stream` descriptor instead of the pinned
stdout package. `stream-probe-guest-producer-component.do` performs exactly two
literal writes with capacity one, closes the writer once, transfers the stream
once, and awaits the no-payload result. The custom Rust/Wasmtime runner variant
selects `do:stream-probe/sink@0.1.0` and export `produce`, and its pending,
ready, and `Err(pipe)` probes observe `[65, 66]`, one host callback, and one
stream drop; the error marker explicitly requires `result=err:pipe` together
with `stream-dropped=true`. `test_do_stream_writer_guest_producer_descriptor.sh`
and `test_rust_stream_writer_guest_producer_descriptor.sh` are the lowering and
runtime gates. This proves descriptor-driven producer wiring and bounded
backpressure only; general dynamic producer loops, general producer leases, and arbitrary
element layouts remain unadmitted.

**2026-08-03 helper-mediated producer-lease checkpoints:** a bounded guest
producer may transfer its `StreamWriter<u8>` once at the root level to a
same-typed async helper. The helper may directly call the registered
`do:stream-probe/sink.write-via-stream` descriptor or perform a bounded linear
`u8` write sequence before that call, and the final helper closes its lease
with `defer close(writer)`. The adjacent two-hop and three-hop shapes permit
private forwarding helpers to pass the still-open lease to the final helper;
each forwarder performs no write and no close. The descriptor-specific emitter
folds the fixed helper shape into the `produce` root; generated WIT exports
only the root. The original forwarding, helper-owned sequence
(`397_stream_writer_helper_owned_writes.do`), two-hop, and three-hop fixtures are covered
by Component lowering plus pending/ready/`Err(pipe)` Rust/Wasmtime gates,
observing `[65, 66]`, one host callback, and one stream drop. A sixth hop,
general async function calls, general dynamic producer loops, arbitrary element
layouts, borrowed/nested/variant resource fields, and broader completion-error
payloads remain outside G6.2.

**2026-08-03 bounded dynamic producer checkpoint:** the registered
`do:stream-probe/sink.write-via-stream` path now also admits one explicit
countdown shape: `produce(count u64)` creates a capacity-one `StreamWriter<u8>`,
writes literal `65` once per iteration, awaits each write, closes once, and
awaits the sink. The emitter stores `remaining` as `i64` at frame offset 52 and
starts the sink before pumping, so `count=0` is a valid empty stream. The
Component gate and Rust/Wasmtime runner cover `count=0/1/3` in pending, ready,
and `Err(pipe)` modes, observing ordered bytes, one host callback, and one
stream drop. This remains a bounded descriptor-specific gate: arbitrary loops,
dynamic byte values, general async calls, producer leases beyond the admitted
helper shapes, and borrowed/nested/variant resource fields remain blocked.

**2026-08-03 parameterized helper producer checkpoint:** the same registered
`do:stream-probe/sink.write-via-stream` path now admits one private helper with
the exact `(StreamWriter<u8>, u64, u8)` parameter shape. The root transfers the
writer, count, and value directly; the descriptor-specific emitter folds the
helper countdown into the single `produce(count, value)` Component export and
reuses frame offsets 52 and 60. The lowering gate and
`test_rust_stream_writer_guest_producer_parameterized_helper.sh` cover
`count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, one host callback, and one
stream drop. This is still a private source-shape adapter: arbitrary async
calls, additional helper hops, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 parameterized five-hop forwarding helper producer checkpoint:**
the same registered shape now admits exactly
`produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> inner_stream -> finish_stream`.
All five private forwarding helpers pass `(writer, count, value)` unchanged and
only await the next same-typed helper; the final helper remains the existing
countdown/close/sink shape. Component lowering still emits only the root export
and reuses frame offsets 52 and 60. The dedicated Component and Rust/Wasmtime
gates cover `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, one host
callback, and one stream drop. A sixth forwarding edge, crossed or literal
arguments, general async calls, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 parameterized forwarding helper producer checkpoint:** the same
registered `do:stream-probe/sink.write-via-stream` shape now admits one private
parameterized forwarding helper. `produce` transfers `(writer, count, value)`
to `forward_stream`, which transfers the same three direct parameters to the
already verified countdown helper. The descriptor-specific emitter still emits
only the root export and reuses frame offsets 52 and 60. The new Component and
Rust/Wasmtime gates cover `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`,
one host callback, and one stream drop. A sixth forwarding edge, crossed or
literal arguments, general async calls, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 reordered parameterized helper checkpoint:** the same registered
shape now accepts the three private helper parameters in any declaration order,
provided the call supplies exactly one `StreamWriter<u8>`, one `u64`, and one
`u8` source identifier in that declaration order. The sema ownership pass finds
the writer argument by its typed formal slot, so a reordered forwarding helper
still transfers and closes the lease exactly once. The descriptor-specific
Component emitter keeps the `(i64, i32)` root export and frame offsets 52/60;
the new Component and Rust/Wasmtime gates cover count `0/1/3`, value `90`,
pending/ready/`Err(pipe)`, one callback, and one stream drop. Literal, duplicate,
missing, extra, or arbitrary expression arguments, a sixth forwarding edge, and general
producer/resource shapes remain rejected.

**2026-08-03 branch-selected terminal checkpoint:** the same private
`do:stream-probe/sink.write-via-stream` descriptor now admits one helper-mediated
terminal branch: normal completion calls `close(writer)`, while the registered
`pipe` path calls `abort(writer, 2)`. Component lowering keeps one root export and
routes both arms through the same exactly-once writer/task/waitable cleanup
epilogue. `test_do_stream_writer_guest_producer_branch_terminal.sh` and
`test_rust_stream_writer_guest_producer_branch_terminal.sh` cover pending/ready
normal completion and the abort result, observing one host callback, one stream
drop, and one terminal completion. This producer-only runner has no
`ResourceTable`, so its evidence does not claim `table-empty=true`; sixth
forwarding, dynamic abort codes, arbitrary producer expressions, and general
async composition remain rejected.

**2026-08-03 parameterized two-hop forwarding helper producer checkpoint:** the
same registered shape now admits exactly
`produce -> forward_stream -> middle_stream -> finish_stream`. Both private
forwarders pass `(writer, count, value)` unchanged and only await the next
same-typed helper; the final helper remains the existing countdown/close/sink
shape. Component lowering still emits only the root export and reuses frame
offsets 52 and 60. Component plus Rust/Wasmtime pending/ready/`Err(pipe)` gates
cover `count=0/1/3`, `value=90`, one host callback, and one stream drop. A third
forwarding edge, crossed or literal arguments, general async calls, arbitrary
producer expressions, and borrowed/nested/variant resource fields remain
outside G6.2.

**2026-08-03 parameterized three-hop forwarding helper producer checkpoint:**
the same registered shape now admits exactly
`produce -> entry_stream -> forward_stream -> middle_stream -> finish_stream`.
All three private forwarding helpers pass `(writer, count, value)` unchanged
and only await the next same-typed helper; the final helper remains the existing
countdown/close/sink shape. Component lowering still emits only the root export
and reuses frame offsets 52 and 60. The dedicated Component and Rust/Wasmtime
gates cover `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, one host
callback, and one stream drop. A sixth forwarding edge, crossed or literal
arguments, general async calls, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 parameterized four-hop forwarding helper producer checkpoint:**
the same registered shape now admits exactly
`produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> finish_stream`.
All four private forwarding helpers pass `(writer, count, value)` unchanged and
only await the next same-typed helper; the final helper remains the existing
countdown/close/sink shape. Component lowering still emits only the root export
and reuses frame offsets 52 and 60. The dedicated Component and Rust/Wasmtime
gates cover `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, one host
callback, and one stream drop. A sixth forwarding edge, crossed or literal
arguments, general async calls, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 nested owned-resource record checkpoints:** the private
`do:record-resource-stream-nested@0.1.0` descriptor admits one nested
`inner-entry` record, and the private
`do:record-resource-stream-nested-two-level@0.1.0` descriptor admits one
bounded `inner-entry -> deep-entry` path. Both contain one `own<ticket>` leaf.
The generated WIT keeps ownership private, the Core layout uses the canonical
nested handle slot at offset zero, and the frame-owned release helper clears
that slot after `[resource-drop]ticket`. Component lowering plus
pending/ready/error Rust/Wasmtime gates observe two records, two resource
drops, one stream drop, one future drop, and an empty resource table for each
descriptor. Borrowed, list, variant, a seventh level, and resource escape remain
rejected; multiple nested paths are covered by the bounded checkpoint below.

The pinned validator also supplies a hard boundary for borrowed fields:
`wasm-tools component embed` with `borrow<ticket>` fails with
`function read-via-stream returns a type which contains a borrow<T> which is
not supported`. This is a Component/WIT toolchain limitation, not a reason to
add public `borrow<T>` syntax to Do.

The manifest parser recursively validates the admitted paths and rejects a
seventh nested level, multiple children, mixed scalar/nested top-level fields,
or any unsupported child metadata at validation rather than silently lowering
it as a shallower record.

**2026-08-03 multiple nested owned-resource path checkpoint:** the private
`do:record-resource-stream-multiple-nested@0.1.0` descriptor admits two
top-level nested paths, `resource-entry.left -> left-entry.ticket` and
`resource-entry.right -> right-entry.ticket`. Each path has one final
`own<ticket>` leaf and one aligned Core `i32` slot at offsets zero and four.
The emitter walks both paths for WIT declarations, decode, and release; the
shared `ticket` resource declaration and `[resource-drop]ticket` import remain
deduplicated. The Component lowering gate and Rust/Wasmtime pending/ready/error
gates observe entries `[(1,111,222),(2,333,444)]`, four resource drops, one
stream drop, one future drop, and an empty resource table. Fifth-level paths,
multiple children, mixed top-level scalar/nested fields, borrow/list/variant
fields, and resource escape remain rejected.

**2026-08-03 three-level nested owned-resource checkpoint:** the private
`do:record-resource-stream-nested-three-level@0.1.0` descriptor admits one
`resource-entry.inner -> deep-entry -> deeper-entry -> own<ticket>` path. The
manifest ceiling is now four container levels; recursive WIT declaration, Core
decode/release, and the canonical frame-owned handle slot are reused without
adding public ownership syntax. Component lowering and Rust/Wasmtime
pending/ready/error gates observe `[111,222]`, two resource creates/drops, one
stream drop, one future drop, and an empty resource table. Fifth-level paths,
multiple children, mixed scalar/nested fields, borrow/list/variant fields, and
resource escape remain rejected. The exact gates are
`test_do_record_resource_stream_nested_three_level_probe_lowering.sh` and
`test_rust_record_resource_stream_nested_three_level_probe.sh`.

**2026-08-03 four-level nested owned-resource checkpoint:** the private
`do:record-resource-stream-nested-four-level@0.1.0` descriptor admits one
`resource-entry.inner -> deep-entry -> deeper-entry -> deepest-entry -> own<ticket>`
path. The recursive WIT declaration, Core decode/release, and canonical
frame-owned handle slot remain descriptor-driven; no public ownership syntax is
added. Component lowering and Rust/Wasmtime pending/ready/error gates observe
`[111,222]`, two resource creates/drops, one stream drop, one future drop, and
an empty resource table. Fifth-level paths, multiple children, mixed
scalar/nested fields, borrow/list/variant fields, and resource escape remain
rejected. The exact gates are
`test_do_record_resource_stream_nested_four_level_probe_lowering.sh` and
`test_rust_record_resource_stream_nested_four_level_probe.sh`.

**2026-08-03 five-level nested owned-resource checkpoint:** the private
`do:record-resource-stream-nested-five-level@0.1.0` descriptor admits one
`resource-entry.inner -> deep-entry -> deeper-entry -> deepest-entry -> ultra-entry -> own<ticket>`
path. The recursive WIT declaration, Core decode/release, and canonical
frame-owned handle slot remain descriptor-driven; no public ownership syntax
is added. Component lowering and Rust/Wasmtime pending/ready/error gates
observe `[111,222]`, two resource creates/drops, one stream drop, one future
drop, and an empty resource table. Seventh-level paths, multiple children, mixed
scalar/nested fields, borrow/list/variant fields, and resource escape remain
rejected. The exact gates are
`test_do_record_resource_stream_nested_five_level_probe_lowering.sh` and
`test_rust_record_resource_stream_nested_five_level_probe.sh`.

**2026-08-03 six-level nested owned-resource checkpoint:** the private
`do:record-resource-stream-nested-six-level@0.1.0` descriptor admits one
`resource-entry.inner -> deep-entry -> deeper-entry -> deepest-entry -> ultra-entry -> hyper-entry -> own<ticket>`
path. The recursive WIT declaration, Core decode/release, canonical
frame-owned handle slot, and deduplicated resource drop remain
descriptor-driven. Component lowering and Rust/Wasmtime pending/ready/error
gates observe `[111,222]`, two resource creates/drops, one stream drop, one
future drop, and an empty resource table. Seventh-level paths, multiple
children, mixed scalar/nested fields, borrow/list/variant fields, and resource
escape remain rejected. The exact gates are
`test_do_record_resource_stream_nested_six_level_probe_lowering.sh` and
`test_rust_record_resource_stream_nested_six_level_probe.sh`.

**2026-08-01 writer-frame evidence:** the pinned
`wasi:cli/stdout.write-via-stream` descriptor now emits a fixed `u8` writer
frame with queue head/count/capacity, pending-producer, terminal/error, and
pending pointer/length slots. The Core helper path contains explicit
`stream-write` promotion and backpressure transitions, while the Zig
`StreamWriterQueue` model covers FIFO, capacity-zero rendezvous, transfer,
close, abort, and wake flags. The completion frame follows the pinned compact
canonical Result layout: tag byte at offset 0 and `error-code` payload byte at
offset 1, each loaded with `i32.load8_u` before the two-word `task-return`.
`test_do_cli_stream_stdout_lowering.sh` and `test_rust_stream_writer.sh` pass
for the existing forwarding probe, including pending, immediately-ready, and
host `Err(pipe)` callbacks.

The generated writer frame now carries `[async-frame-budget-bytes] 64` and uses
the same instance-local checked counter as the GC frame emitters: it reserves
before `$frame-alloc`, releases before `$frame-free`, and exposes the Core-only
`[async-config]byte-budget-limit` hook with the `-1` unlimited default. The
writer's generated `cabi_realloc` is now covered by the shared transactional
realloc path described below. The external Component scheduler still has no
byte-budget owner or admission call site.

**2026-08-02 stdin-frame evidence:** the fixed scalar-u8
`wasi:cli/stdin.read-via-stream` lowering now carries
`[async-frame-budget-bytes] 32` and uses the same instance-local checked counter
and Core-only `[async-config]byte-budget-limit` hook. The generated
`$frame-alloc` reserves 32 bytes before either a fresh allocation or freelist
reuse, and `$frame-free` releases the charge exactly once before recycling the
frame. The 99-case Zig emitter suite, Core/WIT ABI and lowering scripts, and
Rust/Wasmtime stdin runner pass with this accounting present. The stdin
stream/future endpoint storage and generic scheduler admission remain outside
this boundary.

The pinned CLI stdin host runner now also exercises the 32-byte frame charge
through the host-only `BudgetGate`: a 31-byte limit rejects before the provider
is called, a second 32-byte admission is rejected while the first call is
live, and the released permit admits the next call. The same fixture augments
the temporary Component world with the private `byte-budget-limit` alias and
verifies 32-byte success plus 31-byte Component-side rejection before the
provider callback. This remains descriptor-specific evidence; stream/future
endpoint storage and generic scheduler policy are still outside the boundary.

**2026-08-02 cabi-realloc evidence:**
`src/build/codegen_component_cabi_realloc.zig` now owns the common generated
Core realloc contract. It reserves only `size - old_size` on growth, releases
`old_size - size` on shrink, leaves the byte counter unchanged for an equal
size, and releases the growth delta before trapping when `memory.grow` fails.
The `-1` limit remains unlimited. The rewrite is idempotent for templates that
already contain the budget helper and injects the instance-local limit,
reserve, release, and heap owner for older templates.

The path is exercised through the async component and special-target pipeline
for the pinned stream writer/stdin, HTTP response body/request/status, private
resource Result, wait-for, resource-probe, and filesystem-preopen templates.
The helper unit tests, component async Zig suite, WAT lowering scripts, and
relevant Rust/Wasmtime runners pass. This accounts allocation bytes only; it
does not claim external scheduler admission, general canonical buffer
ownership, or a complete host-configured quota API.

The standalone `examples/gc-p3-runtime/test_cabi_realloc_budget.sh` probe now
executes the shared transaction directly: an 8-byte grow followed by a 4-byte
shrink leaves usage at 4; a grow that exceeds the memory maximum returns the
failure sentinel after releasing its reservation and leaves both usage and the
heap owner unchanged; and a 4-byte limit rejects an 8-byte grow by trapping.
This is an allocator rollback probe only, not evidence that the external
Component scheduler or every canonical ABI allocation consumes the budget.

The fixed guest-producer probe is also executable: it creates a guest-owned
capacity-one `stream<u8>`, writes `65`, `66`, and `67`, and passes the writer to
the pinned stdout host function. `test_rust_guest_stream_writer.sh` observes
`[65, 66, 67]`, consumer early-drop after `[65]`, and host `Err(pipe)`; all three
paths close/drop the writer and reader exactly once. The later bounded producer
gates also exercise a source-level countdown operation plus one-, two-, three-,
and five-hop private helpers, including pending/ready/error runtime cases. None of these
gates claims arbitrary element layout or a mapping of Do `abort(writer, err)` to
an external WIT error payload.

**Writer boundary:** the admitted producer shapes use a descriptor-specific
writable queue pump and explicit frame-owned cleanup. They are intentionally
not a general producer language: arbitrary producer expressions, reordered or
literal helper arguments, a sixth forwarding hop, borrowed/list/variant
resource fields, and broader filesystem async methods remain rejected. A
general writable endpoint with unrestricted resumable reader-to-writer
composition is still outside the current gate.

## Component Model Delivery

**Status:** bounded slices delivered; general Component Model lowering remains
deferred.

**Evidence:** the existing Component pipeline has verified bounded scalar,
record, resource, stream, and future slices. General resource/stream/future
lowering remains deferred. WIT resources have `own`/`borrow`, but the
temporary Core callback id is not a WIT function value and must not be emitted
into a WIT interface.

**Required mapping:** `Subscription` maps to a WIT resource with an explicit
destructor. Long-lived event delivery maps to a stream or future/poll API, not
to the Core callback id.

**Unblock condition:** keep component planning rejected for host callback
imports until stream/future lowering, cancellation, and resource destruction
are executable and validated.

## Wasmtime 47 C Embedder Experiment

**Status:** an optional custom-host embedding experiment is blocked. It is not
a compiler, WIT, Component assembly, or general WASI P3 blocker.

**2026-07-28 generic async evidence:**
`examples/p3-runtime/test.sh` compiles and runs a local C embed runner against
Wasmtime 47.0.2. It creates one component call future, enters one host callback
registered through `wasmtime_component_linker_instance_add_func_async`, yields
once, and completes on the second continuation poll with result `27815`. The
fixture uses custom `do:component-async-probe@0.1.0`, not a P3 package, and its
WIT function is synchronous while the C host continuation supplies the async
boundary. A second fixture performs the same sequence with a Core GC `struct`
wholly inside the embedded core module; it does not enable component-model GC
or pass a GC ref over the component ABI. This proves the generic C API
mechanism, the core-GC/component coexistence boundary, and one-future Store
discipline only; it does not prove P3 async lowering or host binding.

**Evidence:** the locally installed Wasmtime is `47.0.2 (90fed3c6a,
2026-07-21)`. Its C API exposes
`wasmtime_component_func_call_async`, `wasmtime_call_future_poll`, and
`wasmtime_component_linker_instance_add_func_async`, so a C host can execute
and manually link a controlled async component fixture. The same headers expose
`wasmtime_component_linker_add_wasip2_async`, but no
`wasmtime_component_linker_add_wasip3*` helper. The CLI does expose `-S p3=y`.

**2026-07-28 exact P3 probe:** `examples/p3-runtime/async-wait-for-component.wat`
imports the pinned `wasi:clocks/monotonic-clock@0.3.0.wait-for` as
`async func(u64)`, lowers it through a minimal core wrapper, and returns through
`task.return`. `wasmtime_component_new` accepts that component. The runner then
registers `wait-for` with `wasmtime_component_linker_instance_add_func_async`,
but async instantiation rejects it with `instance export wait-for has the wrong
type`, caused by `type mismatch with async`. The C API name means that its host
callback may yield through a continuation; it does not expose a way to declare
the provider's Component Model function type as WIT `async`. The probe asserts
this exact failure and will fail loudly if a later Wasmtime revision links it,
requiring a new real suspend/resume success assertion.

**2026-07-29 Rust WIT async evidence:**
`examples/p3-runtime/test_rust_wait_for.sh` runs a separate Rust Wasmtime
47.0.2 adapter against the same `async-wait-for-component.wat` fixture. Its
checked-in Cargo manifest and lockfile pin `wasmtime = 47.0.2`. The adapter
enables component model async, more async builtins, and concurrency support;
it registers the exact `wasi:clocks/monotonic-clock@0.3.0` `wait-for` import
with `Linker::instance(...).func_wrap_concurrent`. One `Store::run_concurrent`
call invokes exported async `run` with `27815`. The host Future records the
argument, returns `Pending` exactly once, then uses `Accessor::spawn` to run a
host completion task in that Store's event loop. The task sends a one-shot
completion; only then does the Future complete. The test asserts one call, one
pending poll, one external wake, and one completion. The initial host poll uses
a noop Waker, so an embedder must use the Store event-loop API rather than
retaining that initial Waker for an external thread.

**2026-07-29 pinned compiler lowering evidence:**
`examples/p3-runtime/test_do_wait_for_lowering.sh` compiles
the `wait-for`, alias, and `wait-until` component fixtures with the unified
`do build --p3-async-component` target. The target classifies the pinned
scalar/unit descriptor, then emits Core WAT carrying
the legacy async ABI; the script explicitly embeds the pinned WIT metadata
with `wasm-tools component embed` and then runs `wasm-tools component new`
before giving the resulting Component binary to the Rust adapter. It exercises
two same-shape descriptors,
`wasi:clocks@0.3.0/monotonic-clock.wait-for` and `wait-until`; each fixture
uses one async `run(u64)` export, one `[async-lower]` subtask handle, a
task-local waitable-set `WAIT`, and one
`task.return` after `SUBTASK/RETURNED`; and one async lift/callback shape. The
Rust adapter verifies the `27815` argument, one Pending poll, one Store-loop
host wake, and one completion.

The CLI unit-Result probe still keeps task-local state in a linear-memory
frame: resume state at offset 0, waitable-set handle at offset 4, cleanup
flags at offset 8, and a completion value slot at offset 12. By contrast, the
selected P3 clocks and cancellation lowering now constructs `$async-frame` GC
structs, roots them in `$async-frames`, and exposes only an `i32` table handle
through `context-set-0`/`context-get-0`. Terminal cleanup clears the table root
before the handle enters the GC-private free-slot list. `codegen_async_model.zig`
still owns the source live-slot model; `codegen_gc_async_frame.zig` defines the
GC representation used by those selected P3 templates.

The target can write the assembly WIT sidecar with
`--p3-wit-output out.wit`; the supported assembly sequence is:

```bash
do build wait-for-component.do --p3-async-component \
  --p3-wit-output out.wit -o out.wat
wasm-tools component embed out.wit out.wat --world probe -o embedded.wasm
wasm-tools component new embedded.wasm -o component.wasm
```

**2026-08-01 immediate async completion evidence:** Wasmtime `47.0.2` returns
the pinned `Status::Returned` value as the bare Core word `2`; only
`Status::Started` encodes a subtask handle for `waitable-join`. The selected
clock unit, CLI unit-Result, scalar `Result<i32,i32>`, private resource
`Result<resource,error>`, and the pinned cancellation wrapper now branch on `2`
before shifting or joining/cancelling.
Each wrapper is exercised twice by its Rust/Wasmtime fixture: once with a
pending host future and once with an immediately-ready host future. The
multi-await/loop templates, arbitrary stream payloads, and HTTP resource
wrapper remain separate boundaries and are not implied by these checks.

**2026-07-31 sequential scalar evidence:**
`examples/p3-runtime/test_do_three_await_lowering.sh` compiles a single async
function that invokes `wait-for`, `wait-until`, then `wait-for` again. The
descriptor-driven plan emits one Core import/call site and one resume state per
invocation while de-duplicating the repeated WIT `wait-for` declaration. The
script validates Component assembly and runs two concurrent calls through the
Rust adapter; it observes six pending polls, six Store-loop wakes, and six
completions. This proves straight-line scalar/unit sequencing in the registered
clocks world. The separate `if-await-component.do` probe proves one restricted
two-way branch: `if @eq(input, u64-literal)` with one registered scalar await
and terminal return in each arm. It does not prove nested branches, joins,
general loops, payload, list, Stream, HTTP, or generic resource lowering.

For a scalar/unit function returning `nil`, the accepted straight-line terminal
forms are the final `await(future)` and `await(future)` followed immediately by
a bare `return`. A bare `return` with trailing source remains rejected; this
does not add general control-flow lowering.

Each registered scalar/unit operation may use the entry parameter (including a
straight-line alias) or a typed `u64` literal local. Literal values are emitted
at each host call, including after a resume; general scalar expressions and
mutable local-state lowering remain rejected. The only pure expression admitted
in this probe is `@add(parameter-or-alias, non-negative-u64-literal)`, which is
re-emitted at the initial and resumed call as `i64.add`.

The branch probe emits the selected operation's resume state before issuing its
subtask. Its callback accepts either terminal state and performs the same frame
cleanup and `task.return`. The separate if-join probe maps state 1 or 2 to the
same state-3 subtask, and only state 3 reaches cleanup. Neither probe lowers
arbitrary source CFG edges.

The separate countdown probes admit exactly one loop shape: a `u64` counter
before the loop initialized by a non-zero literal, the entry parameter, or
`@add(parameter, u64-literal)`; one registered scalar `Future<nil>` binding
and `await` in the body; `counter = @sub(counter, 1)`; and
`if @eq(counter, 0) { break }`. Its `$async-frame` contains the input and the
mutable counter. Each completion decrements the rooted counter, returns at
zero, or reissues state-1 `wait-for` with the stored input. The literal test
drives two calls through two iterations each and observes four Pending polls,
wakes, and completions. The parameter and parameter-add tests each observe five
for two calls with effective counts 2 and 3, proving the counter is initialized
and resumed per call. Parameter callers must supply a positive effective count;
this source shape underflows after its first await for zero. This proves only
that explicit form, not arbitrary loop CFG, `continue`, other assignments, or
non-zero break conditions.

The countdown await argument may be the entry parameter or the mutable counter.
The counter-argument fixture runs calls with initial counts 2 and 3 and the
Rust adapter observes five host calls with argument frequencies `{3: 1, 2: 2,
1: 2}`. That proves both the initial call and each resumed call load the rooted
counter rather than retaining the entry value.

An exact top-of-loop guard, `if @eq(counter, 0) { break }`, is also admitted.
It permits a literal zero initial count and changes the generated async lift to
release the frame and `task.return` before the first host call. The companion
probe invokes the export with 0 and 2 concurrently; only the latter produces
the two `wait-for` calls with arguments 2 and 1. This does not generalize to
arbitrary guard conditions or arbitrary break placement.

**Boundary:** this is an intentionally narrow source-to-Component probe, not
generic compiler lowering or a generic P3/WASI adapter. The explicit target
derives its Core import, ABI shape, async export names, and WIT sidecar from a
registered descriptor. It currently selects only scalar/unit clocks, the
no-payload CLI Result tag, or the private two-word resource Result probe. The
checked-in clocks execution fixture proves `wait-for` and `wait-until`; the
separate CLI/resource fixtures prove their respective layouts. The fixed
`@cancel` companion probe additionally validates Component subtask
cancellation. These probes do not add arbitrary resource cleanup, `Future<T>`
or `Stream<T>` lowering, frame serialization, scheduler lowering, or host-drive
semantics. The ordinary `do build` path keeps `AsyncLoweringUnavailable`.

**Boundary:** this fixture only proves or disproves a particular Wasmtime C
embedder API. A do build produces a standard Component artifact through the
pinned `wasm-tools` assembly path; it neither links Wasmtime nor calls this C
API. A runtime supplies the selected standard WASI imports when it loads that
artifact. `wasmtime_component_new` consumes an existing component binary; it
is not a component encoder for compiler-generated core WAT.

**Current input:** `examples/p3-runtime/p3-clocks-manifest.json` pins the
Wasmtime `v47.0.2` source snapshot (`90fed3c6adf53f112c4dea56851728557bb73799`)
for `wasi:clocks@0.3.0/monotonic-clock.wait-for`, an `async func(u64)` with no
result. `verify_p3_wit.sh` verifies the vendored WIT SHA-256 before every P3
probe run.

**Unblock condition:** an embedder that uses Wasmtime's C API still needs a C
API extension; the Rust `func_wrap_concurrent` route is a separate available
adapter surface. A runtime compatibility report must identify its API, pinned
WIT subset, and tested ownership/cancellation contract. Neither adapter result
makes the compiler artifact invalid or by itself proves its full execution.

## Component Task Cancellation

**Status:** verified for the fixed `wasi:clocks@0.3.0/monotonic-clock.wait-for`
P3 probe; it is not yet generic Future lowering.

**Evidence:** `examples/p3-runtime/test_rust_cancel_wait_for.sh` assembles the
legacy callback ABI fixture and runs it with Wasmtime `47.0.2`. The host async
function remains pending. `subtask.cancel` reaches `RETURN_CANCELLED (4)`, the
host future is dropped once, and `subtask.drop` then succeeds. The compiler
fixture `test_do_cancel_wait_for_lowering.sh` verifies the same sequence from
Do source through Component assembly.

The scalar Result companion extends this evidence without introducing a
source-level `Cancelled` value: `test_rust_scalar_result.sh` runs a host
`Result<i32, i32>` operation from a `nil`-returning async root, observes exactly
one committed external-effect marker and one host-future drop, and observes no
rollback marker. A root function with a non-`nil` result after bare `@cancel` is
rejected because the cancellation terminal has no result payload.

**Contract:** `@cancel(future)` consumes the Future and lowers directly to the
pinned `subtask.cancel` operation. The compiler does not create an operation
ID, host broker, cancellation acknowledgement, descriptor cancellation
capability, or public `Cancelled` result branch.

**Boundary:** Component task cancellation only ends the guest/host task
lifecycle. It does not prove an already-issued SQL update, HTTP request, or
other external side effect was rolled back, compensated, or made idempotent.
Those guarantees belong to the selected host API and business protocol.

## Wasmtime Store Async Serialization

**Status:** this is a constraint of the current Wasmtime C embedder experiment,
not a do compiler constraint or a universal WASI P3 property.

**Evidence:** `wasmtime/async.h` states that all parameters and the Store must
remain alive while a `wasmtime_call_future_t` exists, and that another function
must not be called on that Store while it is alive. The header also states that
only one future can be alive for a Store at a time. A do instance hosted in one
Store therefore cannot drive 1024 independent C API call futures concurrently.

**Required contract:** a runtime adapter using this C API uses one active
component future per Store. The compiler does not encode this rule into the
Component ABI; another conforming runtime may use a different host scheduling
strategy while preserving the Component's observable behavior.

**2026-08-02 checkpoint:** `examples/p3-runtime/test_c_api_host_drive_queue.sh`
now compiles the C runner and submits two logical tasks to one local host drive
queue. The drive loop polls the first future to completion, deletes it, and only
then starts the second. The probe passes with
`tasks=2 completed=2 calls=2 queued=1 active-futures-max=1
nested-call-attempts=0`, proving the adapter-side serialization rule and the
absence of nested C API calls. `examples/p3-runtime/test.sh` runs this probe as
part of the p3-runtime gate.

**Remaining boundary:** this is an adapter-specific queue proof, not a generic
Component scheduler, operation-ID protocol, or concurrent Store capability. It
does not remove the pinned P3 WIT/linker blocker or establish complete WASI
execution.

## Component Assembly Tooling

**Status:** v1 path verified. The repository's standard external tooling path
produces the explicitly named `wasmtime-p3-legacy` compatibility target; it is
not a standard-naming P3 or complete-WASI claim.

**Evidence:** `src/run/run.zig` already resolves `wasm-tools` and reports a
missing-tool diagnostic. The regression runner validates generated WAT and
Component WIT using that tool. The local binary is `wasm-tools 1.254.0
(bb58fdf91, 2026-07-20)`, SHA-256
`cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6`.
It provides `component embed` and `component new`, but its async callback
metadata currently requires legacy naming; standard32 naming is not supported
for async-related features.

**Decision:** pin this binary as the v1 component assembly tool and make
compiler codegen emit its legacy async ABI names. No Rust toolchain is required
at build time. A future standard-naming `wasmtime-p3` target must use a tooling
path proven against the same component assembly and execution matrix; it cannot
silently reuse a legacy artifact under the standard target name.

**Verified path:**
`examples/p3-runtime/assemble_wasmtime_p3_legacy.sh` is the canonical assembly
entrypoint. It rejects a missing, version-mismatched, or hash-mismatched
`wasm-tools`, then runs `component embed --dummy-names legacy --async-callback`,
attaches the generated component-type custom section to the real Core module,
runs `component new`, and validates with `cm-async,cm-more-async-builtins`.
`assemble_async_component.sh` remains a compatibility wrapper to this pinned
path. `examples/p3-runtime/test_wasmtime_p3_legacy_assembly.sh` builds the real
`wait-for-component.do` Core WAT, asserts the legacy async import/export names,
assembles and validates the Component, and executes it twice through the Rust/
Wasmtime clock host. It also asserts the target name, exact tool version/hash,
and rejection of an unpinned executable.

## Runtime Drive Boundary

**Status:** runtime-specific scheduling remains out of the compiler ABI. The
fixed Rust adapter uses Wasmtime's `run_concurrent` API; this is sufficient for
the wait-for and cancellation probes but does not establish a generic scheduler
or complete WASI execution model.

**Boundary:** Do emits the pinned Component operations only. A runtime chooses
how to poll and cancel its host futures while obeying its own Store re-entry
rules. Do does not define `HostDrive`, operation queues, IDs, acknowledgements,
or a cross-runtime event protocol for this purpose.

## Resource Admission And OOM

**Status:** blocked. Count-only quotas do not make the promised
`TaskExit.Failed(QuotaExceeded)` behavior true for variable-sized GC values.

**Evidence:** the current v1 memory specification represents `text`, `[T]`, and
managed structs as dynamically allocated ARC payloads (`doc/memory.md`); the
planned GC replacement retains variable-sized text/list/frame/ABI buffers.
Limits such as 65536 tasks or waiters do not bound their byte size. A Wasm GC
allocation failure can trap the instance before the guest has storage to record
a task-local error or unwind cleanup.

**Required contract:** every countable allocation has a byte-cost formula and
is admitted before it mutates a channel, Scope, or wait list. Admission denial
uses the normal task cleanup path. Backend allocations whose cost cannot be
preflighted are explicitly instance failure/host error, not a falsely
recoverable per-task quota result.

**Unblock condition:** define the v1 byte budget owner, accounting points, and
transactional admission tests for channel slots, TaskFrames, text/list backing,
and canonical ABI buffers. The default GC backend cannot claim deterministic
quota behavior before this exists.

**2026-08-02 contract checkpoint:** `src/build/async_byte_budget.zig` now
defines the instance-owned `ByteBudget` model with committed and in-flight
reservation bytes. `reserve` must succeed before a state mutation; `commit`
creates an allocation token, `rollback` releases an in-flight reservation, and
`release` returns committed bytes exactly once. Checked formulas cover TaskFrame
payloads, queue slots, text backing, list backing, and canonical ABI buffers;
overflow is an explicit `ByteSizeOverflow`, never a wrapped quota value.
`src/build/async_byte_budget_test.zig` covers the five formulas, overflow,
commit/rollback, capacity restoration, and duplicate finalization. The selected
generated frame, canonical-buffer, and `cabi_realloc` helpers now consume the
same checked counter, while generic channel/endpoint storage, text/list
backing, scheduler policy, and the active ARC/GC allocation backends still do
not. The resource-admission blocker and runtime/ARC NO-GO status therefore
remain unchanged.

**2026-08-02 variable-backing checkpoint:** `TextBackingPool` and
`ListBackingPool` in `src/build/async_byte_budget.zig` now consume the checked
text/list formulas through one transactional variable-allocation model. Focused
tests cover capacity-based charges, overflow, budget rejection without state
mutation, foreign allocation tokens, and exactly-once release. This advances
the compiler-side accounting model only; generated text/list allocation call
sites, generic endpoint storage, scheduler policy, and ARC/GC backend admission
remain outside the runtime contract.

The first model consumer is now `StreamWriterQueue.init_with_budget` in
`src/build/codegen_component_stream_writer.zig`. Accepted and pending queue
entries carry one committed allocation token; `pop` releases accepted slots,
and `close`/`abort` release pending slots. A budget failure occurs before the
queue mutates and is covered by the queue's focused tests. This is still a
compiler-side queue model, not a runtime scheduler or GC allocator call site.

The TaskFrame boundary now has the same compiler-side model in
`src/build/codegen_gc_async_frame.zig`. `bytes_for_frame_layout` accounts the
fixed 16-byte frame header plus the layout payload, `TaskFramePool` admits and
releases one allocation token per live frame, and emitted frame metadata records
`[async-frame-bytes]`. This connects the generated frame layout to the checked
budget contract. Generated Component frame allocators now carry the layout byte
count into an instance-local checked i64 counter before `table.grow`, and release
it from `$frame-free`; counter overflow or an impossible release traps before a
bad handle can escape. The generated allocator now also owns an explicit
instance-local limit: it starts at `-1` (unlimited) and exposes the Core-only
`[async-config]byte-budget-limit(i64) -> i32` hook. The hook accepts `-1` or a
non-negative limit, rejects a limit below current committed/reserved usage, and
leaves state unchanged on rejection. This is a runtime configuration boundary,
not a Do source API; a Component host still needs an adapter that invokes it
before admission. Scheduler admission policy and a configured default remain
open.

**Component visibility check (2026-08-02):** assembling the generated scalar
Result probe and running `wasm-tools component wit` exposes only the registered
`run` import/export; `[async-config]byte-budget-limit` remains an internal Core
module export and is not present in the Component world. An external scheduler
therefore cannot configure this limit through the current Component interface.
The generated budget owners now also carry the WIT-safe Core alias
`byte-budget-limit`, but the normal Do-generated sidecar still omits it. The
private adapter runner `examples/p3-runtime/test_rust_scalar_result_budget_adapter.sh`
augments that sidecar only at host assembly, calls the alias before the async
entry, and verifies both admission (`limit=20`, one 20-byte frame) and
pre-admission rejection (`limit=19`). This proves a host adapter boundary, not
generic Component scheduler admission; no public WIT API is inferred from the
Core hook.

**2026-08-02 host admission checkpoint:** the scalar Result Rust/Wasmtime
runner now places a `BudgetGate` before `run_concurrent`. It holds one 20-byte
permit for the first call, rejects a second call before entering the Store,
releases the permit after completion, and then admits the second call. The
gate has checked-add overflow and no-mutation-on-rejection unit coverage. This
is the first executable host admission call site, but it is still bound to the
private scalar Result frame charge; it does not define a generic scheduler,
queue policy, or canonical ownership protocol.

**2026-08-02 stream-writer admission checkpoint:** the pinned
`wasi:cli/stdout.write-via-stream` host runner now exercises the same
host-only `BudgetGate` with the generated 64-byte stream-writer frame charge.
With a 63-byte limit, admission is rejected before the Component call and the
host callback count remains zero. With a 64-byte limit, a second admission is
rejected while the first permit is held; after the first `run_concurrent`
completes, the permit is released, the second call is admitted, and both stream
readers are dropped exactly once. The executable gate is
`examples/p3-runtime/test_rust_cli_stream_stdout_scheduler.sh`. The bounded
guest-producer runner applies the same 64-byte gate and covers two sequential
producer calls plus the 63-byte pre-call rejection; its existing FIFO and
exactly-once cleanup assertions remain green. These remain descriptor-specific
host probes. A separate private sidecar run configures the generated
`byte-budget-limit` alias at 64 and verifies a 63-byte Component-side rejection
before the callback for both forwarding and guest-producer fixtures. None of
these probes defines a generic scheduler or makes arbitrary stream endpoint
storage quota-aware.

The canonical result-buffer boundary now has a matching fixed-slot model in
`src/build/async_byte_budget.zig`. `CanonicalBufferPool` computes one slot from
the checked canonical-buffer formula, reserves before admitting it, and releases
the committed token exactly once. The HTTP service emitter consumes that formula
for its 64-byte per-handle result slot and emits `[canonical-buffer-bytes] 64`
metadata. Its generated result-buffer helper now reserves those 64 bytes before
`memory.grow`, rolls back when grow fails, and releases the committed bytes after
`task-return` on the shared terminal path. This is checked accounting only: the
counter has no configured quota, and non-HTTP canonical allocations remain
outside this boundary.

The private two-word resource Result emitter now applies the same checked
accounting to its fixed 8-byte result slot. It emits `[canonical-buffer-bytes] 8`,
reserves before its result-buffer `memory.grow`, rolls back on grow failure, and
releases after immediate, resumed-success, and ready-error `task-return` paths.
This remains a probe-specific boundary; it does not make arbitrary resource
Result payloads or other canonical allocations quota-aware.

The Core GC probe `examples/gc-p3-runtime/async-frame-table.wat` now executes
the same admission ordering for its frame table and a canonical buffer: a fixed
16-byte budget admits two 8-byte frames or one frame plus one 8-byte buffer,
rejects the next allocation before `table.grow`/`memory.grow`, and releases bytes
on cleanup. `test_async_frame_table.sh` verifies both rejection paths and zero
post-cleanup usage. This is a standalone runtime probe; the generated HTTP
result-buffer helper now uses the same checked counter and limit hook, while the
Component scheduler and non-HTTP canonical allocators remain outside this gate.

## Async Host Descriptor Resolution

**Status:** partial. The compiler validates pinned descriptors in
`src/build/p3_async_registry.json`, including
`wasi:clocks@0.3.0/monotonic-clock.wait-for` and `wait-until`, both `async`,
`(u64) -> nil`, and without resources. `do check` accepts their `@host_func`
declarations and rejects an unknown member or signature drift. Their descriptor records retain
the same scalar/unit canonical shape
(`core_params: [i64]`, no core results, `completion: task-return`); the
operation token is explicitly absent. The same canonical record explicitly
stores the verified Core import module
`wasi:clocks/monotonic-clock@0.3.0` and import name
`[async-lower]wait-for` and `[async-lower]wait-until`; the compiler does not
derive either ABI string from the locator or member spelling. Their sibling
`wit` records explicitly store the
package, interface, operation, and world used for the WIT sidecar; those names
and the WIT parameter label are likewise not derived from locator/member or
source-local text.

Default compilation uses this as descriptor identity validation only. The
explicit `--p3-async-component` target classifies and consumes the verified
scalar/unit, unit Result-tag, or private two-word resource Result descriptor
to generate its Core import and WIT sidecar. It rejects every other descriptor;
it does not identify a complete reproducible P3 async ABI for arbitrary
descriptors.

**Evidence:** the current host-binding design uses only locator/member/do
signature and still documents two incompatible async source forms (`async (...)`
and `Future<T>`). The active Core-Wasm collector is explicitly an env import
collector (`src/build/codegen_host_imports.zig`), not a P3 world resolver. A do
signature cannot establish which WIT revision supplies the import, whether it
is async, its canonical lifting/lowering shape, which resource is owned, or
which Component task/subtask operations apply to its async lowering.

**Required contract:** a pinned P3 world/interface/member manifest is a compiler
input for every async descriptor. It records WIT revision/hash, canonical ABI
shape including Core import module/name and WIT package/interface/operation/
world/parameter names, async effect, resource ownership/drop function, and the
applicable pinned task/subtask ABI operations. Sema resolves `@host_func` against that
manifest; it does not infer ABI semantics from a member spelling or permit an
unregistered async descriptor.

**Remaining unblock condition:** the registry now classifies the two verified
canonical shapes: scalar/unit (`core_params: [scalar]`, no result words) and
the private two-word resource `Result`. The component probes consume their
registered Core import strings rather than deriving them from source-local
names. Additional descriptors still require generated canonical result layout,
resource transfer/drop behavior, cancellation cleanup, WIT sidecar generation,
and host execution coverage before they can lower. This is required before
accepting `@host_call` as a portable P3 source operation.

### P3 Result Descriptor Candidate

**Status:** host ABI and explicit compiler probe passed. The pinned Wasmtime
`90fed3c6adf53f112c4dea56851728557bb73799` P3 WIT tree contains
`wasi:cli@0.3.0/run.run`, declared as `async func() -> result`. It is the next
non-resource shape after the two verified clocks operations.

**Evidence:** `examples/p3-runtime/test_cli_result_probe.sh` assembles a Core
WAT probe against its matching WIT, then runs it through the pinned Rust
Wasmtime adapter. The host `run` Future is Pending once and completed by an
`Accessor::spawn` Store wake. Both `Ok(())` and `Err(())` are written through
the canonical result pointer, read by the resumed guest, and passed to the
typed `task.return`. This freezes the no-payload `result` representation as
one `i32` tag for this probe.

**Compiler evidence:** `examples/p3-runtime/test_do_cli_result_lowering.sh`
compiles `cli-run-result-component.do` through the unified
`--p3-async-component` target, assembles its generated Core WAT and WIT
sidecar, and runs its exact source Result branch through the Rust adapter. The
compiler accepts only the fixed no-parameter `Future<Result<nil, nil>>` source
form: either direct `return await(pending)`, or binding that await followed by
`if @is(replied, Ok) { return Err() }` and a final `return Ok()`. The latter
emits `i32.eqz` over the verified canonical tag before typed `task.return`.
The adapter invokes that export twice concurrently in one Store, returns
`Ok(())` from both host futures, and requires both guest results to be
`Err(())`; this makes source-level Result consumption observable.

**Remaining unblock condition:** generalize from this fixed descriptor without
losing descriptor-bound ABI ownership. The current path does not implement
arbitrary `Future<Result<T, E>>`, resources, lists, or generic task-return
lowering. Ordinary `do build` must keep `AsyncLoweringUnavailable` for all
other async programs.

**2026-08-02 scalar Result frame-accounting checkpoint:** the registered
private `Future<Result<i32, i32>>` lowering now derives its fixed 20-byte
linear frame charge from `bytes_for_task_frame(16, 4)`. Generated WAT emits
`[async-frame-budget-bytes] 20`, reserves the charge before frame allocation,
releases it from `frame-free`, and rolls it back before trapping on frame
pointer overflow or a memory boundary failure. The generated Core-only
`[async-config]byte-budget-limit(i64) -> i32` hook is shared by this probe;
the scalar Result pending, immediate, and cancellation adapters plus the
compiler lowering test pass. This remains a descriptor-specific accounting
boundary: it does not admit arbitrary Result payloads, resource ownership,
general canonical allocations, or external Component scheduler admission.

**2026-07-31 bounded payload checkpoint:** the registry now admits one private
scalar `Future<Result<i32, i32>>` descriptor. Its tag and shared payload use
descriptor-defined result-area words; normal completion and direct
`@cancel` cleanup are assembled and validated through the pinned Component
ABI. This does not admit lists, text, nested variants, payload-bearing
`error-code`, or arbitrary resources.

The registered scalar-u8 `wasi:cli/stdin.read-via-stream` probe now derives a
bounded one-to-three read plan, EOF/cancel/drop lifecycle, and canonical WIT
export names. A bounded internal writer FIFO/lease model is tested. The pinned
WIT/toolchain also generates the stdout `write-via-stream` async ABI, including
stream creation, read/write, cancel, and readable/writable drop imports. The
ABI is now copied into `p3_async_registry.json`. The descriptor forwarding
wrapper and fixed guest-producer Rust/Wasmtime fixtures now pass pending and
immediate host callback execution, normal three-item FIFO delivery, consumer
early-drop, and host `Err(pipe)`; each guest-producer scenario observes one
pending write and exactly-once writer close/reader drop. The writer WIT renderer consumes the
descriptor selected by the registry, with a private writer descriptor unit
probe and Component assembly script guarding against a stdout-package
fallback. General queue-to-stream codegen and external writable-endpoint
execution remain deferred. B1 is limited to the registered stdout `stream<u8>`
descriptor and a compile-time bounded source sequence; general dynamic iteration,
arbitrary payloads, and abort-to-WIT-error mapping remain deferred.

The Zig `StreamWriterQueuePump` model now covers bounded scalar source sequences,
pending-value advancement, capacity-zero rendezvous, FIFO preservation, and
delayed close. The fixed guest-producer WAT now routes its resumable entry and
callback through one `writer-pump-step` helper. This is still bounded scaffolding,
not evidence of a generic source-level Component pump or an externally writable
WIT endpoint.

`src/build/codegen_async_model.zig` now records the Core storage class for each
binding visible at an await (`i32`, `i64`, `f32`, `f64`, or `unsupported`). It
is frame-planning metadata only: it neither allocates a frame nor serializes a
binding, and `unsupported` values remain an explicit lowering boundary for
resources, managed values, containers, and generic futures.

**2026-08-01 single-await resumable checkpoint:** the pinned scalar/unit clock
path now consumes one narrow body shape with a local `u64` value live across
`await` and a scalar computation after resume. The plan records the post-await
operation, the Core emitter stores the live local in the GC frame, dispatches
the callback resume state, and runs the shared terminal cleanup on both pending
and immediately-ready completion. The fixture
`examples/p3-runtime/test_do_single_await_post_compute_lowering.sh` assembles
and validates the generated Component, then the Rust/Wasmtime adapter observes
one pending poll/wake/completion and the immediate path with zero polls/wakes.
The same fixture verifies that ordinary `do build` still returns
`AsyncLoweringUnavailable`.

This is still a pinned `wasi:clocks@0.3.0/monotonic-clock.wait-for` contract,
not general async body lowering. Result payloads, Stream operations, resources,
multiple arbitrary control-flow shapes, and unregistered descriptors remain
outside the admitted lowering boundary.

## G6.2 StreamMirror Runtime Closeout (2026-08-03)

The private `do:stream-probe` descriptor now has a complete bounded
`StreamMirror` runtime gate. The guest reads at most three `u8` values from the
registered source stream, forwards them through a capacity-one
`StreamWriter<u8>`, transfers the readable endpoint to the registered sink, and
cancels the independent source completion future. Core WAT/WIT lowering and
Component validation pass, and `test_rust_stream_mirror.sh` passes
`pending`, `ready`, `source-eof`, `error`, `cancel`, and `early-drop`.

The normal terminal failure was `resource has children`: the generated
`mirror-complete` path dropped the waitable set while the completed sink
subtask was still its child. The emitter now drops that subtask exactly once,
handles the immediate-completion marker, clears the frame slot, and only then
drops the waitable set. The runtime assertions observe one source stream drop,
one source future drop, one sink callback/drop, and `table-empty=true` in every
mode. This remains a private descriptor-specific gate; general producer leases,
arbitrary async calls, borrowed/list/variant resource fields, and public
`own<T>`/`borrow<T>`/`ref<T>` syntax remain blocked.

## Full WASI Compatibility Scope

**Status:** not started. The current implementation and P3 plan only cover a
small, explicit subset; that does not satisfy the long-term goal of do being a
first-class WASI language.

**Evidence:** current lowering is limited to selected Core-Wasm imports and the
first async plan intentionally starts from one waitable/future/byte-stream
subset. WIT package availability, type layouts, resource ownership and async
semantics vary by registry revision, so a growing hand-written host function
list cannot prove full coverage.

**Required contract:** define “complete WASI support” as all public
world/interface/member entries in a version/hash-pinned WIT registry, with a
generated world manifest and execution matrix. The compiler must use one common
type/resource/async lowering path rather than interface-specific compiler
special cases. Each registry upgrade is a separately versioned compatibility
release.

**Unblock condition:** after the P3 subset is executable, implement the
generated manifest, universal canonical ABI lowering and per-interface
Wasmtime execution/ownership/cancellation fixtures. Only a fully passing matrix
permits the corresponding complete-WASI release claim.
# Host ABI Blockers

## Verified Private Resource Probe

The private `do:resource-probe@0.1.0` `ledger.ticket` fixture is verified with
descriptor-bound `own`/`borrow` sema, Core WAT component assembly, and a
Wasmtime 47 `ResourceTable` host runner.

The separate `http.send` private fixture now additionally verifies the hard
async resource crossing: `async func(request: request) -> result<response,
error-code>`. `examples/p3-runtime/test_rust_async_resource_result.sh` builds
the component from the do fixture, runs pending and immediate success plus
ready-error exports in one Store, and proves that each request is consumed once
when `send` starts; success creates and drops one owned response per call, while
`Err(failed)` creates and drops no response. The `ResourceTable` is empty at the
end. Its explicit Core ABI is `(request-handle, result-pointer) ->
subtask-handle`, with a result tag and resource/error payload stored in an
8-byte canonical buffer. The private frame itself is an `$async-frame` GC
struct rooted in the `$async-frames` table; it stores only the `i32` canonical
result pointer and the runtime-private state. A host retains the table handle
across suspension, and terminal cleanup clears that GC root before recycling
the handle.

The same registered descriptor now has a bounded explicit cancellation source
shape: `Future<Result<HttpResponse, HttpError>>` must be consumed by
`@cancel(completion)` from a nil-returning async root. The compiler emits the
pinned `subtask.cancel` status check followed by exactly one `subtask.drop` and
`[task-return]cancel`; the generated Component and the hand-written ABI probe
both pass the Wasmtime pending-future-drop and empty-`ResourceTable` checks.
Negative fixtures cover implicit scope-drop, double cancellation, and
cancellation after terminal consumption. This is still a private descriptor
slice, not general resource cancellation or public ownership syntax.

The separate private owned-error descriptor also verifies
`result<response, error-resource>`: a ready `Err` transfers and releases exactly
one error-resource handle, while creating and releasing no response resource.
The generated and hand-written Components agree on pending `Ok`, immediate
`Ok`, ready `Err`, and explicit cancellation. This remains a registry-bound
result layout and does not generalize error payloads or resource ownership
syntax.

This is a private, pinned ABI probe, not generic WASI HTTP support. It does not
yet lower `wasi:http/client@0.3.0-rc-2025-09-16/send` in ordinary `do build`,
and it does not unblock generic WASI resources, arbitrary Future/Stream async
composition, generic resource cancellation, or Component-GC/ARC migration.
The selected clocks `@cancel` Component probe remains separate evidence;
neither probe generalizes this resource result ABI.

The pinned real HTTP WIT has separately verified the import signature
`[async-lower]send: (i32 request-handle, i32 result-pointer) -> i32
subtask-handle`; this exact shape is recorded in `p3_async_registry.json`.
It is not ABI-equivalent to the private probe: when the complete
`wasi:http/types.error-code` variant is present, the generated
`[task-return]run` takes eight `i32` parameters and the component imports the
full HTTP types surface. Real HTTP lowering therefore requires descriptor-led
result-layout generation and a complete types adapter, rather than changing
the private two-word completion-frame emitter.

## HTTP Payload Cancellation Slice (2026-08-04)

The real pinned HTTP package now has one additional private cancellation slice.
`examples/p3-runtime/http-payload-cancel.do` starts the versioned
`wasi:http/client.send` operation with an owned `HttpRequest`, stores the
`Future<Result<HttpResponse, HttpError>>`, and explicitly consumes it with
`@cancel(completion)`. The checked-in service-world fragment is copied into a
temporary package directory; the pinned package files are not modified.

The generated Core WAT imports the exact `[async-lower]send`, request-drop, and
response-drop symbols. Its nil-returning root passes the fixed `[64,128)`
canonical Result scratch to `send`; `Status::Returned` decodes the Result tag,
drops the owned response at offset `8` for `Ok`, and accepts the no-payload
`DnsTimeout` error tag. Both compiler-generated and hand-written Components
assemble and validate. The Rust/Wasmtime runner observes:

```text
request consumed=1
pending future drops=1
response create=0
response drop=0
table-empty=true

mode=ready-ok
request consumed=1
pending future drops=0
ready future polls=1
ready future drops=1
response create=1
response drop=1
table-empty=true

mode=ready-dns-timeout
request consumed=1
pending future drops=0
ready future polls=1
ready future drops=1
response create=0
response drop=0
table-empty=true
```

This closes pending, immediate `Ok(response)`, immediate `Err(DnsTimeout)`, the
bounded immediate `Err(DNS-error)` path with `rcode=None` or a nonempty `rcode`
string, and the same-layout `InternalError(None)` / `InternalError(Some(nonempty
string))` paths. Empty strings and every other payload/error shape remain
runtime traps. It does not add implicit
scope cancellation, cancellation after terminal completion, double
cancellation, rollback/compensation, arbitrary HTTP payload/error shapes,
general HTTP resource methods, or public `own<T>`/`borrow<T>`/`ref<T>` syntax.

**2026-08-04 HTTP service emitter hardening checkpoint:** the generic handler
and request-construction/send lowering paths both expand the shared
`[body-future-event-handler]` template slot to the normal no-body waitable
completion result. Before this checkpoint, the marker leaked into generated
WAT and failed `wasm-tools parse` for the service and empty-request fixtures.
The pinned `test_http_service_abi_surface.sh` assembly gate, the empty-request
Rust/Wasmtime runner, and all 189 `codegen_component_wasi_http` tests now pass.
This fixes template completeness only; it does not admit arbitrary HTTP body
methods, unregistered/general payload-bearing completion errors, general async
calls, or public `own<T>`/`borrow<T>`/`ref<T>` syntax.

`examples/p3-runtime/test_http_service_abi_surface.sh` characterizes that
adapter surface directly from the pinned WIT with `wasm-tools` async-callback
dummy generation. It verifies the `client.send` async-lower import, request and
response resource drops, the eight-word handler task-return signature, and
successful Component assembly/validation with the HTTP types and client
imports. Its minimal Core fixture also proves that the Component retains the
high-level HTTP types interface without importing every unused fields/request
method into Core; a future lowering may therefore emit a descriptor-reachable
subset, beginning with `send` and resource drops. This is an ABI baseline only;
it does not by itself make arbitrary `client.send` shapes lowerable. The
registered descriptor-backed payload slice is covered separately by the payload
error checkpoint above; general type adapters, error layouts, and resource/stream
cleanup paths remain bounded and explicit.

## HTTP Request Body Stream Slice (2026-08-02)

The executable body slice admits only the pinned
`wasi:cli/stdin@0.3.0-rc-2025-09-16/read-via-stream` descriptor as a finite
`Stream<u8>` source. The HTTP plan rejects other registered stream-reader
descriptors at its admission boundary, including a descriptor with a spoofed
canonical import under the same locator/member. The Rust/Wasmtime runner
executes ready and one-poll-pending source-completion configurations for the
cancellation path, two calls with `[65,66]`, success and no-payload
`DnsTimeout`, exactly-once source cleanup, and an empty `ResourceTable`.

The baseline `http-request-body.do` remains a fixed cancellation path: its
source completion is dropped after the send terminal callback. The companion
`http-request-body-await-completion.do` fixture now performs one serialized
source-completion await before `request.new`; it uses the registered
`[async-lower][future-read-1]read-via-stream` operation and executes both
pending-once and immediately-ready host futures through the Component callback.
The await path accepts only a successful no-payload completion and does not
introduce a send/source-completion concurrent state machine. Dynamic body
producers, source loops, trailer payload lifting, payload-bearing error-code
variants, and public `own<T>`/`borrow<T>`/`ref<T>` syntax remain unsupported.

The await lowering gate is
`examples/p3-runtime/test_do_http_request_body_await_completion_lowering.sh`;
the execution gate is
`examples/p3-runtime/test_rust_http_request_body_await_completion.sh`.

## G6.2 Bounded List-Owned Resource Stream Lowering (2026-08-04)

The registered private descriptor
`do:record-resource-list-stream-probe@0.1.0/source.read-via-stream` now lowers
one exact `stream<list<resource-entry>>` source shape. Every element contains
one WIT-internal `own<ticket>`; Do source still has no public
`Option<T>`/`own<T>`/`borrow<T>`/`ref<T>` syntax. The compiler admits one
`@next(reader)`, one await of that read, ignores the received list, awaits the
completion, and returns its `Err(io)` or `Ok()`. The seven internal bindings may
be renamed, but their types, data flow, order, and single-read count remain
pinned.

The compiler emits the private WIT world and a Core component using the verified
result area `ptr@64,len@68`. Each element is a four-byte handle with `ticket@0`
and alignment four. Only `len=0/1/3` is accepted: nonempty storage is exactly
`cabi_realloc(0,0,4,4|12)`, then released once by
`cabi_realloc(ptr,len*4,4,0)`. Validated tickets move to the three private frame
slots, are cleared before their `[resource-drop]ticket`, and all terminal paths
drop stream, future, tickets, storage, waitable, and frame exactly once.

`examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh` builds the
Do fixture, emits its WIT sidecar, parses, embeds, creates, and validates the
generated Component, then executes it through the Rust/Wasmtime runner. The
matrix covers ready `0/1/3`, pending-once completion, `Err(io)`, and early
cleanup. It also derives malformed-length and duplicate-release WAT variants
from stable markers: `len=4` traps before ticket ownership
(`resource-drops=0`, table nonempty), while the second release traps after the
first has dropped exactly three tickets and cleared the table. The gate also
requires the compiler-owned template to be byte-identical to the hand-written
canonical ABI oracle. `examples/p3-runtime/test_record_resource_list_stream_abi.sh`
keeps that oracle independently executable.

The same generated Component and Store also execute 6000 sequential
`ready-three` calls. The terminal frame and the validated last list backing
allocation both rewind their private bump pointers only after exactly-once
cleanup; the stress observation is 18,000 ticket creates/drops, 6,000 stream
and future drops, 6,000 reads, and an empty table. This proves sequential reuse
for the admitted single-active-frame shape, not concurrent invocation support.

`examples/p3-runtime/record-resource-list-stream-unregistered-component.do`
remains a negative fixture and
`examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh` requires
`UnknownP3AsyncHostDescriptor`. Generic list-resource lowering, a second stream
read, length `2` or `4+`, nested or variant elements, borrowed fields, public
ownership/Option syntax, and every unregistered descriptor remain blocked.
Pinned Wasmtime `47.0.2` `bindgen!` cannot generate this `do:...` package because
it emits the Rust keyword `do`; the runner therefore uses the established low-
level Linker API rather than renaming the private WIT package.
## G6.2 Variant Resource Stream Closeout (2026-08-05)

The private `do:variant-resource-stream-canonical@0.1.0` descriptor is now
registered and lowered only for the exact `Stream<Ticket | nil | EventError>`
source shape. The compiler-generated Component and Rust/Wasmtime gate cover
`ticket(own<ticket>)`, `idle`, `failed(io)`, pending, completion error, and
exactly-once stream/future/ticket cleanup. The measured event layout remains
`tag@0`, `payload@4`, `size=8`, `alignment=4`; canonical early-drop,
malformed-tag, and duplicate-release probes remain negative gates.

This does not admit generic variants, borrowed fields, arbitrary producer
expressions, or public `own<T>`/`borrow<T>`/`ref<T>` syntax.
