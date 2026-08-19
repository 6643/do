# D2 Real Host Runtime Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute already-generated Do Components against deterministic real local resources through Rust/Wasmtime without expanding compiler ABI or claiming full WASI support.

**Architecture:** Keep the existing private probe adapters intact and add opt-in real-host paths to the existing Rust/Wasmtime runners. Each invocation owns one Component and one Wasmtime Store, creates only temporary/local resources, records exact ownership and cleanup, and exits with a deterministic marker line. Shapes without a compiler-generated Component target remain explicit D2 pending items.

**Tech Stack:** Rust 1.97.1, Wasmtime 47.0.2, `wasm-tools` 1.254.0, Zig-built `bin/do`, local filesystem/pipe/loopback resources.

## Global Constraints

- Do not change Do source signatures or add compiler lowering for the purpose of a smoke test.
- Use one Component and one Store per runner; use the existing `run_concurrent`/Accessor drive loop.
- Use temporary directories, anonymous/local pipes, and loopback sockets only; no external network or shared user data.
- Assert exact poll/drop/ownership counts and final `ResourceTable` emptiness where the shape has resources.
- Cancellation does not roll back external side effects.
- Preserve unrelated dirty worktree changes; do not stage, commit, reset, clean, or push.

### Task 1: Build the Admitted-Shape Matrix

**Files:**
- Create: `examples/p3-runtime/d2-real-host-matrix.md`
- Inspect: `examples/p3-runtime/test_rust_wasi_filesystem_preopen.sh`, `examples/p3-runtime/test_rust_wasi_filesystem_read_directory.sh`, `examples/p3-runtime/test_rust_cli_stream_stdin.sh`, `examples/p3-runtime/test_rust_http_payload_cancellation.sh`
- Inspect: `src/build/codegen_component_async.zig`, `src/build/codegen_component_wasi_filesystem_preopen.zig`, `src/build/codegen_component_wasi_filesystem_read_directory.zig`, `src/build/codegen_component_wasi_http.zig`

**Interfaces:**
- Consumes: current generated-target dispatch and existing controlled adapters.
- Produces: an explicit matrix of shapes that can be generated today and shapes that remain blocked.

- [x] **Step 1: Record current generated targets.**

Run:

```bash
rg -n 'Target = enum|\.stream_reader|\.wasi_read_directory|\.http_|\.resource_result' src/build/codegen_component_async.zig
```

Record filesystem preopen/read-directory, CLI stream, HTTP request/response/cancellation, and any target that can produce a Component from Do source.

- [x] **Step 2: Record explicit D2 blockers.**

Mark G6.3 socket create/bind/drop, direct filesystem read/write, generic producer shapes, and external-network HTTP as pending when no Do Component target and pinned runtime gate exists. Do not create a hand-written Component to bypass this matrix.

- [x] **Step 3: Verify the matrix document.**

The document must distinguish controlled adapter evidence from real OS resource evidence and must name the exact script that will close each admitted row.

### Task 2: Real Filesystem Preopen/Open/Sync Runner

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_real.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_real.sh`
- Reuse: `examples/p3-runtime/wasi-filesystem-preopen.do`, `examples/p3-runtime/wit/wasi-filesystem-preopen.wit`

**Interfaces:**
- Consumes: existing `--p3-wasi-filesystem-preopen-component` output.
- Produces: a runner whose preopen and `open-at` use a temporary directory and whose `sync` validates a real file descriptor/path.

- [x] **Step 1: Create a temporary filesystem fixture.**

In the shell script create a temporary directory, write `probe` with known bytes, and pass its path to the runner through `DO_D2_FILESYSTEM_ROOT`. The script must remove the directory with a trap.

- [x] **Step 2: Map resource handles to real paths.**

In `wasi_filesystem_real.rs`, replace the fake enum payload with a path-carrying descriptor state. `get-directories` inserts the temporary root; `open-at` accepts only a directory handle, joins the supplied relative path, opens the real file with `std::fs::OpenOptions`, and inserts a file handle; `sync` calls `File::sync_all`; the destructor closes/removes the handle and increments the drop counter.

```rust
let root = std::env::var_os("DO_D2_FILESYSTEM_ROOT")
    .context("DO_D2_FILESYSTEM_ROOT is required")?;
let file = std::fs::OpenOptions::new().read(true).write(true).open(root.join("probe"))?;
file.sync_all()?;
```

- [x] **Step 3: Assemble and run both normal and error paths.**

Run the existing Do build command, `wasm-tools` assembly/validation, and the new runner. Require markers for one preopen, one successful open, one sync, two drops, real file bytes, and empty table. Add a missing-path mode that returns the registered error and still drops the directory exactly once.

- [x] **Step 4: Run the focused gate.**

```bash
bash examples/p3-runtime/test_rust_wasi_filesystem_real.sh
```

### Task 3: Real Directory Stream Provider

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_read_directory.rs`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_read_directory_real.sh`
- Reuse: `examples/p3-runtime/wasi-filesystem-read-directory.do`, `examples/p3-runtime/wit/wasi-filesystem-read-directory.wit`

**Interfaces:**
- Consumes: existing generated `read-directory` Component.
- Produces: a `StreamProducer<DirectoryEntry>` backed by `std::fs::read_dir` and a completion future that supports pending-once and ready modes.

- [x] **Step 1: Populate a temporary directory.**

Create `alpha` as a regular file and `bravo` as a subdirectory. Pass the root
through `DO_D2_FILESYSTEM_ROOT`; never read from `/` or a user project directory.

- [x] **Step 2: Implement deterministic stream production.**

Collect and sort `read_dir` entries by name before constructing the producer.
Convert file type to the existing WIT enum. The producer returns EOF once, then
`StreamResult::Dropped` on cleanup; OS directory errors remain explicit host
errors rather than being silently converted.

- [x] **Step 3: Run pending and ready modes.**

Require `alpha,bravo`, exactly one descriptor drop, one stream drop, one future
drop, expected read count, and `table-empty=true` in both modes. Preserve the
existing controlled adapter gate as a separate test.

### Task 4: Real OS Pipe Stream Gate

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/cli_stream_stdin.rs`
- Create: `examples/p3-runtime/test_rust_cli_stream_stdin_real.sh`
- Reuse: `examples/p3-runtime/cli-stream-stdin-component.do`, `examples/p3-runtime/wit/cli-stream-stdin.wit`

**Interfaces:**
- Consumes: current CLI stdin stream Component.
- Produces: a stream provider backed by a local pipe or socket pair, with explicit EOF and early-drop accounting.

- [x] **Step 1: Create a local producer/consumer pair.**

Use a Unix-domain socket pair created inside the runner; write fixed bytes
`[100,50]`, then close the producer. Do not read from the process terminal.

- [x] **Step 2: Implement pending and EOF behavior.**

The stream producer emits the pipe bytes in order and EOF exactly once; the
existing completion future covers pending-once and ready modes. Record stream
and completion drops.

- [x] **Step 3: Run the gate.**

Require `items=[100, 50]`, one provider call, EOF, one stream drop, one future
drop, and the existing cleanup markers. Keep this task Unix-specific and record
the platform requirement in the runner.

### Task 5: Host Matrix Closeout and Explicit Blockers

**Files:**
- Modify: `examples/p3-runtime/d2-real-host-matrix.md`
- Modify: `doc/pending_blocked.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/master_plan.md`
- Test: all D2 scripts from Tasks 2-4 and existing HTTP cancellation gate

**Interfaces:**
- Consumes: real filesystem/stream evidence and current HTTP controlled evidence.
- Produces: a truthful D2 status without overclaiming sockets or full WASI.

- [x] **Step 1: Run the complete admitted smoke set.**

```bash
bash examples/p3-runtime/test_rust_wasi_filesystem_real.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_real.sh
bash examples/p3-runtime/test_rust_cli_stream_stdin_real.sh
bash examples/p3-runtime/test_rust_http_payload_cancellation.sh
```

- [x] **Step 2: Keep unsupported rows explicit.**

If `codegen_component_async.zig` has no generated socket target or a real network HTTP target, leave those rows pending and record the exact missing target/fixture. Do not mark D2 complete from a hand-written WAT or controlled callback alone.

- [x] **Step 3: Run project-wide validation.**

```bash
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Update the roadmap only with the rows whose real-host gate passed; recover a skip only when its own generated Component and OS-resource test are green.
