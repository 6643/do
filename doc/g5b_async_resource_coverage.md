# G5b Async/Resource Executable Coverage

This is the executable coverage ledger for the async/resource shapes admitted
by the private P3 compiler/component routes. It is prerequisite evidence for
G5b Task 9 Step 4; it does not close G5c or authorize a G5c cutover.

Evidence uses the current pinned toolchain: `wasm-tools 1.258.0`, Wasmtime
`48.0.1`, and Rust/Cargo `1.97.1` where a Rust host runner is used. The current
thin-entry regression `./src/build/test/run_tests.sh` and its `RUN_WASM=1` /
`RUN_GC_CORE=1` variants each complete with `14/14 steps; 53/53 tests`; the
underlying compiler test aggregate is `zig test main.zig 1561/1561`. These are
repository regression evidence only and do not by themselves prove that this
matrix is closed. Older `wasm-tools 1.255.0` / Wasmtime `47.0.2` numbers in
dated reports are historical snapshots, not active toolchain requirements.

`PASS` means the cited current script executed and asserted the relevant
terminal result and cleanup. `MISSING` means the shape is meaningful but the
current executable evidence is absent or failed. `N/A` is reserved for a
state that has no meaning in the exact admitted source/WIT contract.

| Admitted shape group | Coverage | Current executable evidence | Notes |
| --- | --- | --- | --- |
| scalar/unit clock: `wait-for`, `wait-until`, await/control-flow variants | PASS | `test_rust_wait_for.sh` | Canonical clock Component runtime covers pending and immediate terminal paths. Lowering scripts are separate evidence. |
| unit Result: `wasi:cli/run.run` | PASS | `test_do_cli_result_lowering.sh` | Current generated CLI Result Component runs the Rust/Wasmtime pending and immediate paths and asserts parallel calls and cleanup. |
| scalar `Future<Result<i32, i32>>` | PASS | `test_rust_scalar_result.sh` | Generated Component plus Rust/Wasmtime asserts `ok=43`, `err=-10`, pending cancellation, and `dropped=1`; immediate mode also runs. |
| async-call child/inline and inline scalar argument | PASS | `test_do_async_call_component.sh`, `test_rust_async_call_component.sh`, `test_do_async_call_inline_scalar_argument.sh`, `test_rust_async_call_scalar_argument.sh` | Current generated Components run ready, pending, inline-cancel, child-cancel, and scalar-argument ready/pending/cancel paths with exact child/future cleanup. |
| generated async scalar bindings | PASS | `test_rust_async_host_scalar_argument.sh` | Generated Component runtime asserts ready, pending, and cancel modes, argument `7`, future/pending drops, and `table-empty=true`. |
| CLI stdin `Stream<u8>` reader | PASS | `test_rust_cli_stream_stdin_real.sh` | Generated Component runs against a real local pipe and asserts the stream result. |
| CLI stdout `Stream<u8>` writer, guest producer/helper/forwarding forms | PASS | `test_rust_stream_writer.sh`, `test_rust_stream_writer_guest_producer_branch_terminal.sh` | Writer and branch-terminal generated producer paths assert terminal output and stream drops. Helper-owned form is rejected by the current admission boundary and is not counted. |
| generic record stream and record-resource stream, including nested variants | PASS | `test_rust_record_stream_probe.sh`, `test_rust_record_resource_stream_probe.sh`, `test_rust_record_resource_stream_nested_probe.sh` | Generated Component Rust/Wasmtime probes assert pending/ready/error results, EOF, resource/stream/future cleanup. Canonical-only probes remain separate evidence. |
| `StreamMirror` | PASS | `test_do_stream_mirror_lowering.sh`, `test_rust_stream_mirror.sh` | Current generated Component parses/validates and the six-mode Rust/Wasmtime matrix covers pending, ready, source EOF, source error, cancel, and early-drop cleanup. |
| direct/paired/parameterized/triple/nested owned-record producers | PASS | `test_rust_g6_2_owned_record_producer.sh`, `test_rust_g6_2_owned_record_pair_producer.sh`, `test_rust_g6_2_owned_record_pair_parameterized_producer.sh`, `test_rust_g6_2_owned_record_triple_producer.sh`, `test_rust_g6_2_owned_record_nested_producer.sh` | Generated Component lifecycle scripts pass valid, error, cancel/early-drop, repeat, and invalid modes with exact resource drops and `table-empty=true`. Canonical/generated parity is separate evidence. |
| list-resource, dynamic/batched list-resource, and scalar-list producers | PASS | `test_rust_g6_2_c_min_list_resource_producer.sh`, `test_rust_g6_2_c_min_dynamic_list_producer.sh`, `test_rust_g6_2_batched_list_resource_producer.sh`, `test_rust_g6_2_scalar_list_producer.sh` | Generated Component/Rust/Wasmtime scripts assert list values, source/sink errors, cancellation, resource/list cleanup, and `table-empty=true`. |
| variant-resource stream | PASS | `test_do_variant_resource_stream_lowering.sh` | Current path assembles and validates the generated Component, runs ready/pending/error modes, and invokes the canonical ABI oracle. |
| private async resource Result and owned-error resource Result | PASS | `test_rust_async_resource_result.sh`, `test_rust_owned_error_result_shape.sh` | Current shape scripts assert Result terminal and resource/table cleanup markers. |
| HTTP service/send | PASS | `test_http_service_abi_surface.sh`, `test_rust_http_service_empty_request.sh`, `test_do_wasi_http_client_send.sh` | Current pinned constructor/send signatures assemble and validate; generated service and client-send Rust/Wasmtime paths assert request/response and future cleanup. |
| HTTP payload cancellation | PASS | `test_rust_http_payload_cancellation.sh` | Generated Component and Rust/Wasmtime assert pending/ready/error cancellation modes, request/response ownership, future drops, and `table-empty=true`. |
| HTTP request-body and producer forms | PASS | `test_do_http_request_body_lowering.sh`, `test_do_http_request_body_await_completion_lowering.sh`, `test_do_http_request_body_producer_lowering.sh`, `test_do_http_request_body_abi.sh`, `test_do_http_request_body_producer_abi.sh`, `test_rust_http_request_body.sh`, `test_rust_http_request_body_await_completion.sh`, `test_rust_http_request_body_producer.sh` | Current pinned constructor/body signatures assemble and validate; ordinary, completion-await, and guest-producer Rust/Wasmtime paths assert body payloads, completion polling, stream/future drops, and empty tables. |
| filesystem preopen/read-directory and admitted methods: `get-type`, `get-flags`, `sync`, `set-size`, `sync-data`, `metadata-hash`, `metadata-hash-at`, `open-at`, `stat`, `stat-at` | PASS | `test_rust_wasi_filesystem_preopen.sh`, `test_rust_wasi_filesystem_read_directory_real.sh`, `test_rust_wasi_filesystem_get_type.sh`, `test_rust_wasi_filesystem_get_flags.sh`, `test_rust_wasi_filesystem_sync.sh`, `test_rust_wasi_filesystem_set_size.sh`, `test_rust_wasi_filesystem_sync_data.sh`, `test_rust_wasi_filesystem_metadata_hash.sh`, `test_rust_wasi_filesystem_metadata_hash_at.sh`, `test_rust_wasi_filesystem_open_at.sh`, `test_rust_wasi_filesystem_stat.sh`, `test_rust_wasi_filesystem_stat_at.sh` | Each current generated Component/Rust/Wasmtime script passed its method-specific result and cleanup assertions. Read-directory also uses a real temporary directory with pending/ready completion. |
| dedicated `cancel-wait-for` probe | PASS | `test_rust_cancel_wait_for.sh` | Current canonical Component probe asserts pending and immediate cancellation, terminal subtask cancellation, and no double completion. |

Summary: `PASS=18`, `N/A=0`, `MISSING=0` coverage rows. All currently admitted
async/resource shape groups now have a current executable lowering and/or
Rust/Wasmtime lifecycle gate. This closes the Task 9 Step 4 coverage ledger
only; it does not admit arbitrary async/resource lowering or authorize G5c.
