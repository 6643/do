# D2 Real Host Runtime Matrix

D2 only promotes compiler-generated Components that execute against a
deterministic local OS resource. Existing adapter probes remain useful ABI
evidence but are not real-host evidence.

| Shape | Generated target | Current evidence | D2 status / gate |
| --- | --- | --- | --- |
| filesystem preopen + `open-at` + `sync` | `--p3-wasi-filesystem-preopen-component` | controlled ResourceTable adapter + real temp file and missing-file path | passed: `test_rust_wasi_filesystem_real.sh` |
| filesystem `read-directory` stream | `wasi_read_directory` | controlled stream provider + real sorted temp directory, pending/ready | passed: `test_rust_wasi_filesystem_read_directory_real.sh` |
| CLI stdin stream | `stream_reader` | controlled bytes provider + real Unix local pipe, pending/ready | passed: `test_rust_cli_stream_stdin_real.sh` |
| private variant-resource stream | descriptor-specific G6.2 | canonical/generated controlled provider | D2 not applicable yet; no real OS resource is represented |
| HTTP payload cancellation | pinned HTTP service-world target | controlled local callback/provider | controlled only; no external-network claim |
| socket create/bind/drop | `--p3-wasi-sockets-create-bind-drop-component` | generated TCP/UDP Components + real loopback Rust/Wasmtime host with forced create/bind errors | passed: `test_do_wasi_sockets_create_bind_drop.sh` and `test_rust_wasi_sockets_real.sh` |
| filesystem read/write and general async methods | no admitted generated target | synchronous/result lowering only | blocked: separate lowering and runtime plan required |
| external-network HTTP | no permitted external fixture | controlled HTTP probes only | blocked by policy; use loopback only in a future target |

The real gates use a temporary directory, a local pipe/socket pair, one
Component and one Wasmtime Store per run, exact cleanup counters, and no shared
project or external-network data. Cancellation observes completion and cleanup;
it does not roll back external side effects.
