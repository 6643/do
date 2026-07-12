# WASI Nested Union Completion (P1–P4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish remaining do-side WASI nested forms: list-in-result, tuple-in-result, preopens list-of-resource-tuple, and host Err arm as coarse do errors.

**Architecture:** Extend known-table do_result alts + codegen union synthesis from existing result-area list/tuple strategies. Stdlib hosts migrate; public APIs stay `Dir|DirError` / `File|FileError` (P4 can make host match public).

**Tech Stack:** Zig `src/build/`, fixtures `src/build/test/`, `lib/{file,dir,io.stream}.do`.

**Depends on:** `nil|i32`, `Dir|i32`, `u64|i32` already landed.

## Global Constraints

- Exclusive `Ok | Err` only; no multi-return result model.
- No `@wasi_result` / `@wasi_tuple` wrappers.
- TDD per task; `fail=0` before done.
- Do not implement G6.2/G6.3.
- Prefer `src/` paths; do not commit `bin/do`.

---

### Task 1 (P1): `[u8] | i32` for stream/list results

**Files:**
- Create: `src/build/test/compile_ok/283_wasi_union_list_u8_i32.do` + `.expect`
- Modify: `src/build/sema.zig` known `io/streams/input-stream.read` do_result_alt `[u8]|i32` (and File/stream params as needed)
- Modify: `src/build/codegen.zig` list result-area → union (`[u8]` ok / i32 err)
- Modify: `lib/io.stream.do` host + wrapper
- Migrate fixture `115` if present

**Interfaces:**
- Consumes: existing stream read result-area
- Produces: `r [u8] | i32 = host_input_read(...)`

- [ ] **Step 1: Fixture 283**

```do
InputStream = @wasi_resource("io/streams/input-stream", { .id i64 })
.host_input_read = @wasi_func(
  "io/streams/input-stream.read",
  (InputStream, u64) -> [u8] | i32
)
start() {
    s InputStream = InputStream{id = 1}
    r [u8] | i32 = host_input_read(s, 64)
    _ = r
    return
}
```

Import-prefix order: hosts before type if required — mirror 281 (hosts first then resource; if Dir-in-sig needs type, use same pattern as Task2 open).

- [ ] **Step 2: Red → implement → green → commit**

```bash
git commit -m "feat: [u8]|i32 wasi list-in-result for input-stream.read"
```

---

### Task 2 (P2): `Tuple<[u8], bool> | i32` for descriptor.read

**Files:**
- Create: `src/build/test/compile_ok/284_wasi_union_read_tuple_i32.do` + `.expect`
- Modify: known read do_result_alt; codegen tuple+status → union
- Modify: `lib/file.do` host_file_read + read wrapper
- Migrate `109` fixture if feasible

**Interfaces:**
- Consumes: existing `result<tuple<list<u8>,bool>,error-code>` lower
- Produces: `r Tuple<[u8], bool> | i32 = host_file_read(...)`

- [ ] **Step 1: Fixture**

```do
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
.host_file_read = @wasi_func(
  "filesystem/types/descriptor.read",
  (File, u64, u64) -> Tuple<[u8], bool> | i32
)
start() {
    f File = File{id = 1}
    r Tuple<[u8], bool> | i32 = host_file_read(f, 0, 64)
    _ = r
    return
}
```

If grammar uses `Tuple<[u8],bool>` spacing, match existing Tuple syntax in repo.

- [ ] **Step 2: Implement + stdlib + commit**

```bash
git commit -m "feat: Tuple<[u8],bool>|i32 wasi descriptor.read union"
```

---

### Task 3 (P3): Preopens as do list of tuple with Dir

**Files:**
- Create: `src/build/test/compile_ok/285_wasi_preopens_dir_tuple_union.do` + expect (or extend 274/275)
- Modify: known preopens do_result; codegen list-of-tuple with Dir in first element
- Modify: `lib/dir.do` host_preopens + `preopen_directories` wrapper

**Target signature (prefer):**

```do
.host_preopens = @wasi_func(
  "filesystem/preopens/get-directories",
  () -> [Tuple<Dir, text>]
)
```

If `[Tuple<Dir,text>]` sugar not ready, accept `list<tuple<Dir,text>>` do form that still builds Dir shells.

- [ ] **Step 1: TDD fixture + implement + stdlib + commit**

```bash
git commit -m "feat: preopens list of Tuple<Dir,text> do binding"
```

---

### Task 4 (P4): Host Err arm as coarse `DirError` / `FileError`

**Files:**
- Create: `src/build/test/compile_ok/286_wasi_union_dir_error_arm.do` + expect
- Modify: known alts `Dir|DirError`, `nil|DirError`, `File|FileError`, …
- Modify: codegen map status≠0 → error tag (same coarse map as wrappers: any fail → *Failed)
- Modify: `lib/dir.do` / `lib/file.do` hosts + collapse wrappers to thin forward where possible

**Example:**

```do
DirError error = DirOpenFailed | DirCreateFailed | …
.host_dir_open_at = @wasi_func("…open-at", (Dir, i32, text, i32, i32) -> Dir | DirError)
open_dir_at(...) -> Dir | DirError {
    return host_dir_open_at(parent, 0, path, 2, 0)
}
```

Status→which DirError variant: reuse existing wrapper mapping functions (open→DirOpenFailed, create→DirCreateFailed).

- [ ] **Step 1: TDD + implement + stdlib + commit**

```bash
git commit -m "feat: wasi host Err arm uses DirError/FileError"
```

---

### Task 5: Full verification + push

- [ ] `zig build -Doptimize=Debug`
- [ ] `./src/build/test/run_tests.sh` → fail=0
- [ ] `git push origin main`

---

## Spec coverage

| Item | Task |
|------|------|
| P1 list-in-result | 1 |
| P2 tuple-in-result | 2 |
| P3 preopens Dir tuple | 3 |
| P4 Err as do error enum | 4 |
| Push | 5 (and initial docs push done) |
