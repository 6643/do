# Result Policy Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the source-facing Result policy so ordinary Do APIs use `T | E` while private WIT/Component probes retain their tagged Result spelling.

**Architecture:** Treat `T | E` as the public source representation and normalize it to the existing internal `Ok/Err` tag plus payload at WIT boundaries. Keep `Result<T,E>` only for registered private descriptors, same-type ABI probes, and existing compiler compatibility tests.

**Tech Stack:** Do source library, Zig lexer/parser/sema/codegen, WIT registry, shell regression harness, Rust/Wasmtime probes.

## Global Constraints

- Do not replace Result with Go-style multiple returns or zero-value error conventions.
- Ordinary union branches remain unique; `T | T` stays rejected.
- Preserve private `Result<i32,i32>`, `Result<nil,nil>`, and managed same-type probes.
- Do not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- Preserve unrelated dirty worktree changes; do not stage, commit, reset, clean, or push.

### Task 1: Audit Public Result Surface

**Files:**
- Inspect: `lib/file.do`, `lib/dir.do`, `lib/io.stream.do`, `lib/tcp.do`, `lib/udp.do`
- Inspect: `src/build/sema_imports.zig`, `doc/spec_rules.md`, `doc/wit/wasi_p3_lowering.md`
- Test: `src/build/test/compile_ok/344_result_surface.do`, `src/build/test/compile_ok/345_result_unit_ok.do`, `src/build/test/err/115_duplicate_scalar_union.do`

**Interfaces:**
- Consumes: current public union signatures and registered private Result descriptors.
- Produces: a classification showing that every remaining public API uses `T | E` and every remaining `Result<...>` occurrence is private/compatibility-only.

- [ ] **Step 1: Scan public source for residual Result signatures.**

Run:

```bash
rg -n 'Result<' lib examples -g '*.do'
```

Expected: no `Result<...>` in `lib/`; remaining example matches are private P3 probes or explicit compatibility fixtures.

- [ ] **Step 2: Verify the known public union declarations.**

Confirm these declarations remain the source contract:

```do
.host_file_open_at = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at", (File, i32, text, i32, i32) -> File | FileError)
.host_file_read = @host("wasi:filesystem/types@0.3.0", "descriptor.read", (File, u64, u64) -> Tuple<[u8], bool> | FileError)
.host_tcp_create = @host("wasi:sockets/types@0.3.0", "tcp-socket.create", (u8) -> TcpSocket | TcpError)
```

Do not rewrite private `Future<Result<...>>` fixtures in this task.

- [ ] **Step 3: Run the focused compatibility fixtures.**

```bash
./bin/do build src/build/test/compile_ok/344_result_surface.do -o /tmp/result-surface.wat
./bin/do build src/build/test/compile_ok/345_result_unit_ok.do -o /tmp/result-unit-ok.wat
./bin/do check src/build/test/err/115_duplicate_scalar_union.do
```

Expected: the private Result fixtures compile and duplicate ordinary union input is rejected with the existing diagnostic.

### Task 2: Keep Internal Tagged Result Normalization

**Files:**
- Inspect: `src/build/p3_async_manifest.zig`
- Inspect: `src/build/codegen_component_async.zig`
- Inspect: `src/build/codegen_component_wasi_http.zig`
- Inspect: `src/build/sema_imports.zig`
- Test: `src/build/test/compile_ok/346_wasi_result_open_dir.do`, `src/build/test/compile_ok/357_wasi_result_read.do`, `examples/p3-runtime/test_do_cli_result_lowering.sh`

**Interfaces:**
- Consumes: source unions and registered WIT result descriptors.
- Produces: the existing internal `Ok/Err` tag, payload, resource transfer, and cleanup behavior.

- [ ] **Step 1: Confirm source-arm validation is descriptor-driven.**

For every registered `T | E` host signature, verify sema checks the pinned descriptor rather than inferring the WIT arm from the runtime value. A mismatched source signature must still return the existing unsupported/mismatch error.

- [ ] **Step 2: Confirm same-type probes remain private.**

Run:

```bash
./bin/do build src/build/test/compile_ok/344_result_surface.do -o /tmp/result-surface.wat
./bin/do build src/build/test/compile_ok/345_result_unit_ok.do -o /tmp/result-unit-ok.wat
bash examples/p3-runtime/test_do_cli_result_lowering.sh
```

Expected: same-type Result tags remain available to the private probes; no public union rule is loosened.

- [ ] **Step 3: Run the full frontend/codegen regression.**

```bash
cd src && zig test main.zig
cd ../
./src/build/test/run_tests.sh
```

Expected: all existing Result, union, WIT, and cleanup fixtures pass with no diagnostic drift.

### Task 3: Synchronize Result Documentation and Status

**Files:**
- Modify: `docs/superpowers/specs/2026-07-29-result-core-design.md`
- Modify: `docs/superpowers/plans/2026-08-05-result-union-source-migration.md`
- Modify: `doc/spec_rules.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/start_here.md`, `doc/pending_blocked.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: the verified public/private classification from Tasks 1-2.
- Produces: synchronized documentation that names `T | E` as the default source form and keeps private Result compatibility explicit.

- [ ] **Step 1: Remove stale claims that ordinary APIs require `Result<T,E>`.**

Keep private examples and WIT result syntax where they are required by a registered descriptor; change only public API guidance.

- [ ] **Step 2: Record the closed boundary.**

State that ordinary `T | E`, duplicate-union rejection, and private same-type Result probes are verified, while public ownership syntax remains outside this phase.

- [ ] **Step 3: Verify documentation consistency.**

```bash
rg -n 'ordinary|public|Result<|T \| E|own<T>|borrow<T>' doc docs/superpowers/specs/2026-07-29-result-core-design.md docs/superpowers/plans/2026-08-05-result-union-source-migration.md
git diff --check
```

Expected: no contradictory public Result recommendation and no whitespace errors.

### Task 4: Result Closure Gate

**Files:**
- Test: `./src/build/test/run_tests.sh`, `examples/p3-runtime/test_do_cli_result_lowering.sh`, `examples/p3-runtime/test_rust_cli_result.sh`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: a recorded Result policy checkpoint for the next phase.

- [ ] **Step 1: Run the complete default matrix.**

```bash
TMPDIR="$PWD/.tmp/do-tmp/result" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/result-zig" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/result-gzig" \
./src/build/test/run_tests.sh
```

- [ ] **Step 2: Run the private Component/Rust gates.**

```bash
bash examples/p3-runtime/test_do_cli_result_lowering.sh
bash examples/p3-runtime/test_rust_cli_result.sh
```

Expected: both gates pass when invoked through the repository's complete Rust wrapper and the same pinned toolchain.

- [ ] **Step 3: Update the checkpoint only after all commands pass.**

Record the exact pass counts in `doc/start_here.md` and `doc/roadmap_status.md`; if a command fails, leave the status pending and record the command/error instead of claiming closure.
