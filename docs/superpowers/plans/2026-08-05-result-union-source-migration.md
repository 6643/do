# Result Union Source Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ordinary Do and library host signatures use `T | E` for WIT results whose success and error types are distinct, while preserving internal tagged-result lowering for WIT compatibility.

**Architecture:** The source-facing representation becomes an exclusive Do union. The compiler continues to normalize a host result to an internal tagged `ok/err` shape before canonical ABI emission. Same-type WIT results remain private ABI/probe shapes and are not rewritten as duplicate Do union branches.

**Tech Stack:** Zig compiler, Do source libraries and fixtures, WIT host signature validation, existing compiler regression suite.

## Global Constraints

- Do not represent a result as multiple returns with zero-value conventions.
- Do not permit duplicate ordinary union branches such as `T | T`.
- Preserve the canonical WIT result discriminant and payload ownership/lowering.
- Keep same-type result probes such as `Result<i32,i32>`, `Result<nil,nil>`, and `Result<text,text>` private and unchanged until an internal-only representation exists.
- Do not expose `own<T>`, `borrow<T>`, or `ref<T>` as part of this migration.
- Preserve unrelated dirty worktree changes; do not stage, commit, reset, clean, or push.

---

### Task 1: Migrate Standard Library Host Signatures

**Files:**
- Modify: `lib/file.do`, `lib/dir.do`, `lib/io.stream.do`, `lib/tcp.do`, `lib/udp.do`
- Test: existing library compile fixtures and `./src/build/test/run_tests.sh`

**Interfaces:**
- Consumes: existing known-WASI union alternatives in `src/build/sema_imports.zig`.
- Produces: source host declarations using `T | E`; wrappers use the same union values and type-based `@is` narrowing.

- [x] **Step 1: Replace distinct Result host declarations with unions.**

Examples:

```do
.host_file_open_at = @host(... -> File | FileError)
.host_file_sync = @host(... -> nil | FileError)
.host_tcp_create = @host(... -> TcpSocket | TcpError)
```

- [x] **Step 2: Replace typed local Result bindings.**

Use `Tuple<[u8], bool> | FileError`, `u64 | FileError`, `nil | FileError`, and the equivalent socket/stream unions. Preserve wrapper return types.

- [x] **Step 3: Replace `Ok`/`Err` narrowing with payload-type narrowing.**

Use `@is(value, FileError)`/`@is(value, TcpError)` for error enums and `@eq(value, nil)` for unit-success unions. Do not introduce `is_ok` or `is_err`.

- [x] **Step 4: Run the focused library fixtures.**

```bash
./src/build/test/run_tests.sh
```

Expected: existing library and WIT union fixtures pass with no diagnostic drift.

### Task 2: Classify Private Runtime Fixtures

**Files:**
- Preserve: private `examples/p3-runtime/*.do` and `src/build/test` fixtures used to prove async/WIT lowering.
- Modify only: a fixture if it is a user-facing library/API example rather than a private probe.

**Interfaces:**
- Consumes: the union source forms from Task 1 and the existing Future/Stream container grammar.
- Produces: an explicit classification boundary; private probes keep the syntax needed to exercise internal tagged results.

- [x] **Step 1: Classify every remaining source `Result<...>` occurrence.**

The remaining occurrences are compiler Result tests, private P3 descriptors, or same-type ABI probes. No remaining occurrence is a standard-library public API after Task 1. Do not mechanically rewrite private probes.

- [x] **Step 2: Rewrite distinct source forms and branch selectors.**

The standard-library examples were migrated in Task 1. Private P3 examples remain unchanged because their registered targets currently match explicit Result source forms.

```do
Future<Result<nil, StdinError>> -> Future<nil | StdinError>
Result<HttpResponse, HttpError> -> HttpResponse | HttpError
```

- [x] **Step 3: Add or update focused compile fixtures for union host signatures.**

The existing `File | FileError` wrapper and `nil | i32` union fixtures cover distinct union host forms; keep the duplicate-union negative fixture unchanged.

- [x] **Step 4: Run focused compile and runtime gates.**

```bash
./src/build/test/run_tests.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_http_payload_cancellation.sh
```

### Task 3: Keep Internal Tagged WIT Result Normalization

**Files:**
- Inspect/modify only as needed: `src/build/codegen_collect_util.zig`, `src/build/sema_imports.zig`, `src/build/p3_async_manifest.zig`, `src/build/sema_result.zig`.
- Test: existing same-type result and canonical ABI probes.

**Interfaces:**
- Consumes: union source forms from Tasks 1-2 and registry WIT result shapes.
- Produces: one internal tagged result representation for canonical ABI, including `T == E` descriptors.

- [x] **Step 1: Verify union host signatures normalize to the same internal result layout.**

Do not infer the WIT branch from payload values; use the pinned WIT signature and enforce the declared source arm order.

- [x] **Step 2: Preserve same-type private probes.**

`Result<i32,i32>`, `Result<nil,nil>`, and `Result<text,text>` remain valid only where the existing private descriptor/probe requires an explicit tag.

- [x] **Step 3: Run canonical result tests and full regression.**

```bash
./src/build/test/run_tests.sh
```

### Task 4: Synchronize Documentation

**Files:**
- Modify: `docs/superpowers/specs/2026-07-29-result-core-design.md`, relevant WIT lowering/spec documents, and the automatic decision summary.

**Interfaces:**
- Consumes: the verified source migration and internal-tag boundary.
- Produces: documentation that no longer presents `Result` as the default ordinary Do API.

- [x] **Step 1: Document `T | E` as the default distinct-arm source form.**
- [x] **Step 2: Document same-type WIT result as an internal compatibility boundary.**
- [x] **Step 3: Run `git diff --check` and the complete regression suite.**
