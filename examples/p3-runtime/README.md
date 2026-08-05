# P3 Runtime Probes

`--p3-async-component` is the explicit unified source-to-Component target. It
classifies the pinned descriptor before selecting a lowering: scalar/unit
clocks, `wasi:cli/run.run` with `Result<nil, nil>`, the private two-word
resource `Result` probe, the fixed `wasi:http/client.send` service, or the
fixed `wasi:filesystem/types.descriptor.read-directory` one-to-three-entry
slice. It
emits Core WAT plus a WIT sidecar for component assembly. List, generic Stream,
generic record streams, payload-bearing HTTP `error-code`, and every
unclassified descriptor are rejected rather than falling into a probe
template. Ordinary `do build` keeps its async-lowering guard.

Component assembly for the verified v1 path is centralized in
`assemble_wasmtime_p3_legacy.sh`. It pins `wasm-tools 1.254.0` by version and
SHA-256, forces the legacy async callback names, and labels the output target
`wasmtime-p3-legacy`; `assemble_async_component.sh` is retained as a
compatibility wrapper. Run `bash test_wasmtime_p3_legacy_assembly.sh` for the
Core-WAT -> Component -> Rust/Wasmtime golden gate. This target is deliberately
not named `wasmtime-p3` and does not claim standard32 or complete WASI support.

The C embedder uses one active `wasmtime_call_future_t` per Store. The
`test_c_api_host_drive_queue.sh` probe queues two logical calls, polls and drops
the first before starting the second, and asserts `active-futures-max=1` with
zero nested call attempts. This is an adapter scheduling proof only; it does
not add a compiler-level scheduler or operation-ID ABI.

The pinned `wasi:cli/stdin.read-via-stream` `u8` slice is the current admitted
Stream exception. `test_do_cli_stream_stdin_lowering.sh` validates its artifacts
and `test_rust_cli_stream_stdin.sh` validates direct unread-Future drop for both
pending and already-ready host futures, EOF handling, and endpoint cleanup. This is
not general Stream, backpressure, or arbitrary WIT future lowering. The reader
emitter now derives a bounded one-to-three read plan and WIT export name from
the source; `cli-stream-stdin-one-read.do` covers the one-read assembly path.

The stdin runner also has a host-only 32-byte admission probe: its scheduler
case rejects a second live frame and re-admits after release, while the private
sidecar case verifies Component-side limits of 32 (success) and 31
(pre-provider rejection). These checks do not define a generic scheduler or
endpoint quota.

`stream-probe-component.do` exercises the same reader lowering through the
descriptor-owned `do:stream-probe@0.1.0` package. Run
`test_do_stream_reader_descriptor.sh` for custom module/import and WIT checks,
then `test_rust_stream_reader_descriptor.sh` for Wasmtime execution. The host
verifies two items, EOF, an unread completion future, and exactly-once stream
and future disposal. This remains a bounded `Stream<u8>` slice, not general
WIT Stream or producer support.

The registered `do:result-probe@0.1.0` descriptor admits only scalar
`Future<Result<i32, i32>>` payload words. The tag and shared payload are stored
at descriptor-defined offsets and resumed through `task-return`; lists, text,
nested variants, and unregistered payload layouts remain rejected. The
`scalar-result-cancel.do` companion cancels that Result future from a `nil`
returning async root; its Rust host records one committed effect, one host
future drop, and no rollback. A non-`nil` root result after bare `@cancel` is
rejected because cancellation has no source-level result branch. The writer
work currently has an internal bounded FIFO/lease model with Zig coverage for
backpressure, FIFO order, transfer, close, abort, and wake state. Pinned
`wasi:cli/stdout.write-via-stream` WIT produces a complete async canonical ABI
with `wasm-tools 1.254.0`; the descriptor and A-route forwarding wrapper are
now registered. The wrapper now emits a fixed-capacity writer frame and
explicit `writer-enqueue`/`writer-promote` backpressure helpers, while
preserving the existing reader forwarding path. `test_rust_stream_writer.sh`
verifies pending and immediately-ready callbacks plus a host `Err(pipe)` Result
with a Rust/Wasmtime host. The fixed guest-producer fixture
`cli-stream-stdout-guest-producer.do` creates a capacity-one `Stream<u8>`, writes
three bound `u8` locals as `[65, 66, 67]`, and is exercised by
`test_rust_guest_stream_writer.sh` for normal,
consumer-early-drop, and host-error paths. The general queue-to-stream pump,
arbitrary writable endpoints, arbitrary WIT stream shapes, and external WIT
`abort` error mapping remain pending.
The forwarding and guest-producer runners also expose host-only 64-byte
admission probes and private sidecar checks for the generated frame limit; they
remain descriptor-specific evidence.
Run `bash test_cli_stream_stdout_abi_surface.sh` to verify the pinned WIT hash
and all eight generated stdout stream imports.

`stream-probe-writer-component.do` exercises the same writer emitter with the
registered private `do:stream-probe@0.1.0` sink descriptor. Run
`test_do_stream_writer_descriptor.sh` to verify descriptor-owned Core/WIT
module names and Component validation; this is an assembly probe and has no
claim of a generic producer runtime.

`stream-probe-guest-producer-helper.do` is the narrow helper-mediated lease
probe. It transfers the capacity-one `StreamWriter<u8>` once to an async helper
that directly calls the private sink and closes the lease. Run
`test_do_stream_writer_guest_producer_helper_descriptor.sh` and
`test_rust_stream_writer_guest_producer_helper_descriptor.sh` for WIT/Component
and pending/ready/`Err(pipe)` Wasmtime coverage. The helper is folded into the
`produce` root; this does not enable general async function-call lowering.

`stream-probe-guest-producer-helper-owned.do` covers the adjacent helper-owned
shape: the helper receives the lease, writes the bounded `[65, 66]` sequence,
then calls the private sink and closes the lease. Run
`test_do_stream_writer_guest_producer_helper_owned_descriptor.sh` and
`test_rust_stream_writer_guest_producer_helper_owned.sh` for the same
pending/ready/`Err(pipe)` matrix. This remains one descriptor-specific helper
gate, not general async calls or dynamic producer lowering.

`stream-probe-guest-producer-helper-two-hop.do` adds one private forwarding hop
before that final helper. The forwarder only transfers the still-open lease;
the final helper performs the same bounded writes, sink call, and close. Run
`test_do_stream_writer_guest_producer_helper_two_hop_descriptor.sh` and
`test_rust_stream_writer_guest_producer_helper_two_hop.sh` for the pending/ready/
`Err(pipe)` matrix. This unparameterized helper path remains bounded; general
async function-call lowering remains
rejected.

The parameterized producer has a separate bounded three-hop checkpoint:
`stream-probe-guest-producer-parameterized-three-hop.do` accepts
`produce -> entry_stream -> forward_stream -> middle_stream -> finish_stream`.
Each forwarding helper transfers `(writer, count, value)` unchanged and only
awaits the next helper; `finish_stream` owns the countdown, sink call, and
`defer close(writer)`. Run
`test_do_stream_writer_guest_producer_parameterized_three_hop.sh` and
`test_rust_stream_writer_guest_producer_parameterized_three_hop.sh` for the
`count=0/1/3`, value `90`, pending/ready/`Err(pipe)` matrix. A fourth forwarding
edge, arbitrary async calls, and arbitrary producer/resource shapes remain
rejected.

For `wasi:cli/run.run`, the source probe accepts either direct forwarding of
`Future<Result<nil, nil>>`, or one exact unit-result branch: bind
`await(pending)`, test `@is(replied, Ok)`, return `Err()` in that branch, then
return `Ok()`. The latter lowers the canonical unit Result tag through
`i32.eqz`; it proves source Result consumption, not arbitrary branch or
payload lowering.

`resource-probe.do` is a private `do:resource-probe@0.1.0` Component fixture.
It validates `ticket` ownership through `create`, `borrow-value`, `consume`,
and canonical resource drop. It is not a general WASI, HTTP, Future/Stream, or
Component-GC implementation.

Run `bash test_do_resource_probe_lowering.sh` for compiler and component
assembly, and `bash test_rust_resource_probe.sh` for Wasmtime execution.

The private async resource Result probe also records its fixed 8-byte canonical
result slot in the checked byte counter. Its result-buffer helper reserves before
`memory.grow` and releases after both immediate and resumed `task-return`; this
is accounting evidence only, not a configurable quota or general resource ABI.

`http-service.do` is the admitted real HTTP slice. It accepts only the pinned
`async handle(request HttpRequest) -> Result<HttpResponse, HttpError>` service
whose body transfers the request to `send`, binds the returned Future, and
either directly returns `await(pending)` or directly returns an identically
typed binding of that await. The emitter performs the request drop,
returns either an owned response or a no-payload `error-code`, and emits the
`wasi:http/handler.handle` task-return ABI. Run
`bash test_http_service_abi_surface.sh` for compiler lowering, Component
assembly, and the Rust Wasmtime host regression. It does not admit HTTP body
streams, trailers, payload-bearing errors, general branching, or multiple
awaits.

`http-request-empty.do` is the bounded constructor companion. It creates empty
headers, no body, an immediate `Ok(None)` trailers future, and no request options;
`http-service-empty-request.do` transfers that request once to `client.send`.
Run `bash test_do_http_request_empty_lowering.sh` for Core/Component assembly,
`bash test_rust_http_request_empty.sh` for constructor lifecycle cleanup, and
`bash test_rust_http_service_empty_request.sh` for successful and no-payload
error service outcomes. These scripts use the complete pinned WIT package when
assembling the combined path. Request body producers, dynamic trailers,
payload-bearing error variants, and general HTTP resource methods remain
unsupported.

`http-payload-cancel.do` is the separate bounded cancellation slice. It stores
the pinned `Future<Result<HttpResponse, HttpError>>` from `send` and explicitly
calls `@cancel(completion)`, covering pending, immediate `Ok`, `DnsTimeout`, and
the registered optional-string error payloads. The Rust/Wasmtime gate checks
exactly-once cleanup and an empty `ResourceTable`, including two sequential
nonempty payload calls in one component instance. Cancel-after-terminal, a
second cancellation of the same Future, implicit scope-drop, and unregistered
HTTP shapes remain rejected; concurrent calls on one instance are not covered by
this single-scratch gate. Run `bash test_do_http_payload_cancellation.sh`
and `bash test_rust_http_payload_cancellation.sh`.

`http-request-body.do` is a deliberately fixed slice. It admits only the
pinned CLI stdin `Stream<u8>` descriptor, sends that reader as the request body, and then
transfers the request once to `client.send`. The Rust host supplies `[65,66]`
and runs one success plus one `DnsTimeout` call, checking source stream/future
cleanup and an empty resource table. The runtime script runs both ready and
one-poll-pending source-completion modes, and a Rust unit test drives both
future states. Run
`bash test_do_http_request_body_abi.sh`,
`bash test_do_http_request_body_lowering.sh`, and
`bash test_rust_http_request_body.sh`.

`http-request-body-producer-send-first.do` is the bounded guest-produced body
variant. It creates `new_stream<u8>(1)`, constructs the request and starts
`send` before writing `[65, 66]`, awaits each write, closes the writer, and
awaits the transmission future. Component stream writes are rendezvous-based,
so `http-request-body-producer.do` deliberately preserves the rejected
write-before-request order as a negative fixture. Run
`bash test_do_http_request_body_producer_abi.sh`,
`bash test_do_http_request_body_producer_lowering.sh`, and
`bash test_rust_http_request_body_producer.sh` for ABI, Component, and
Wasmtime coverage. This remains a fixed probe, not generic producer syntax or
dynamic body lowering.

`http-request-body-await-completion.do` is the serialized completion variant.
It awaits the source completion before constructing the request, then follows
the same one-transfer `client.send` path. Its lowering imports the pinned
`[async-lower][future-read-1]read-via-stream`; the runtime checks pending-once
and ready host futures with four and two total polls respectively across two
calls, plus the same response/resource cleanup. Run
`bash test_do_http_request_body_await_completion_lowering.sh` and
`bash test_rust_http_request_body_await_completion.sh`.

`wasi-filesystem-preopen.do` is a separate, fixed real WASI 0.3 resource
probe. It imports `wasi:filesystem/preopens@0.3.0` `get-directories`, takes
the first opaque `Dir` descriptor, borrows it for `descriptor.open-at`, checks
the owned `File` `Ok` payload, borrows that File for `descriptor.sync`, then
performs canonical File and Dir drops. Run
`bash test_do_wasi_filesystem_preopen_lowering.sh` for WIT/Core assembly and
`bash test_rust_wasi_filesystem_preopen.sh` for Wasmtime `ResourceTable`
execution. This is not generic preopen-list/result lowering, arbitrary
filesystem API support, or broader filesystem Component support.

`bash test_rust_wasi_filesystem_real.sh` runs the same generated preopen
Component against a temporary real directory and file. It covers successful
open/sync plus a missing-file error path, with exact ResourceTable cleanup.

`wasi-filesystem-read-directory.do` is the fixed G6.2 one-entry record-stream
slice. It imports the pinned `descriptor.read-directory`, reads one
`directory-entry` (`name = "alpha"` in the host), awaits the entry and
completion futures, and drops the stream, completion future, and directory
resource exactly once. Run
`bash test_do_wasi_filesystem_read_directory_abi.sh`,
`bash test_do_wasi_filesystem_read_directory_lowering.sh`, and
`bash test_rust_wasi_filesystem_read_directory.sh`; the runtime covers both
pending-once and immediately-ready completion.

`wasi-filesystem-read-directory-bounded.do` extends the same pinned descriptor
to three statically visible `@next(reader)` blocks: `alpha`, `beta`, and an
empty EOF probe. Run
`bash test_do_wasi_filesystem_read_directory_bounded_lowering.sh` and
`bash test_rust_wasi_filesystem_read_directory_bounded.sh`; the host verifies
three stream reads, both completion modes, exactly-once cleanup, and
`table-empty=true`. Dynamic record-stream loops, payload-bearing completion
errors, arbitrary stream sources, and other filesystem async methods remain
unsupported.

`bash test_rust_wasi_filesystem_read_directory_real.sh` runs the bounded
read-directory Component against a temporary OS directory (`alpha` file and
`bravo` directory), checking sorted names, pending/ready completion, and exact
stream/future/resource drops. This is still a pinned record-stream slice, not
general filesystem async support.

`bash test_rust_cli_stream_stdin_real.sh` runs the pinned CLI stdin stream
Component through a Unix local socket-pair pipe, exercising pending/ready
completion and EOF cleanup with real bytes. It is a local Unix smoke, not a
portable stdin or general stream-provider implementation.

`cancel-wait-for-component.do` is a fixed Component async cancellation probe.
It lowers `@cancel(pending)` to the pinned `subtask.cancel` ABI operation,
waits for `RETURN_CANCELLED`, and only then drops the subtask. Run
`bash test_do_cancel_wait_for_lowering.sh` for the full Do-to-Component-to-
Wasmtime path, or `bash test_rust_cancel_wait_for.sh` for the standalone ABI
fixture. The host future stays pending and is dropped by cancellation; this
does not claim rollback or compensation of external side effects.

`two-await-component.do` is the first verified resumable-frame probe. It
stores the `u64` parameter and resume state in a GC `$async-frame` rooted by a
per-call Core table handle, then performs `monotonic-clock.wait-for` followed
by `wait-until`. Only the `i32` handle crosses the Component/context boundary.
Run
`bash test_do_two_await_lowering.sh` to verify Core/WIT assembly and a Rust
host that concurrently invokes the export with two distinct deadlines. The
host verifies that each call reaches both clock operations and that all four
pending/completion cycles complete without sharing a frame.
It covers only two sequential scalar clock awaits in the same pinned interface;
it is not general multiple-import, Result-payload, resource, Stream, or
Component-GC lowering.

`literal-two-await-component.do` verifies the same shape when both clock calls
take a typed `u64` local derived from `@add(input, 41)`. The compiler re-emits
the parameter and literal at the initial and resumed host call; the script
assembles and validates the resulting Component. General scalar expressions and
mutable local state are not part of this probe.

`if-await-component.do` is the first control-flow probe. It accepts only a
top-level `if @eq(input, u64-literal)` whose two branches each issue one scalar
clock await then return. The Component runner invokes both paths concurrently
and verifies one `wait-for` and one `wait-until`; nested branches, joins, and
general mutable control flow remain rejected.

`if-join-await-component.do` extends that probe with one common await after the
two branches. Both resume states dispatch the same third subtask before the
final callback returns; the runner verifies four pending/wake/completion cycles
across two concurrent calls. Nested branches, multiple joins, and general
mutable control flow remain rejected.

`three-await-component.do` extends that structural boundary to an arbitrary
ordered scalar/unit operation list. It reuses `wait-for` after `wait-until`,
so the generated WIT must declare the import once while the Core module retains
one distinct call site and resume state for each invocation. Run
`bash test_do_three_await_lowering.sh` for compiler output and Component
assembly plus a Rust Wasmtime adapter that observes all six pending/wake/
completion cycles from two concurrent calls. It does not cover branches,
loops, payload completion, resource Result, HTTP, list, or Stream.

`loop-countdown-component.do` is the one admitted loop shape. It initializes a
typed `u64` counter from either a non-zero literal, the entry parameter, or
`@add(parameter, u64-literal)`, awaits one registered scalar `Future<nil>` in
each iteration, decrements that counter by one, and breaks only when it reaches
zero. The GC frame retains both the input and the mutable counter; the literal
fixture makes two concurrent calls and observes four pending/wake/completion
cycles. The parameter fixture uses inputs `2` and `3`, while the addition
fixture uses `1` and `2`; each observes five, proving that the resumed callback
reuses the per-call counter rather than a static unroll. Run
`bash test_do_loop_countdown_lowering.sh` or
`bash test_do_loop_countdown_parameter_lowering.sh` or
`bash test_do_loop_countdown_parameter_add_lowering.sh`. Parameter callers
must provide a positive effective value; source-level zero underflows after the
first await. `wait_for` may take either the entry parameter or the countdown
counter; `test_do_loop_countdown_counter_argument_lowering.sh` verifies the
latter with aggregate host arguments `{3: 1, 2: 2, 1: 2}` across two calls.
Nested loops, `continue`, arbitrary assignments, other break conditions, and
general loop lowering remain rejected.

To terminate zero safely, the loop may instead start with the exact guard
`if @eq(remaining, 0) { break }` and omit the trailing break after decrement.
`loop-countdown-pre-guard-component.do` runs this form concurrently with
inputs `0` and `2`: the first completes without a host call, while the second
observes only `wait-for(2)` and `wait-for(1)`. Run
`bash test_do_loop_countdown_pre_guard_lowering.sh`.
