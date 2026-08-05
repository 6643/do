# Result Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add compiler-provided `Result<T, E>` values with contextual `Ok` and `Err` construction, generic `@is` narrowing, and lossless WIT `result<T, E>` host-signature mapping.

**Architecture:** `Result` is an intrinsic two-case tagged layout rather than a parsed payload-enum declaration. A focused semantic pass resolves constructors from a known result target; existing union value, local, return, narrowing, and ARC machinery consumes its normalized layout. Pinned WIT signatures accept `Result` as the explicit source representation of `result`.

**Tech Stack:** Zig compiler, WAT/Core Wasm lowering, pinned WIT registry, shell regression suite.

## Global Constraints

- Public spelling is `Result<T, E>`, `Ok`, and `Err`; lowercase is WIT-only.
- Do not add generic payload enums, `is_ok`, `is_err`, `unwrap`, public `own<T>`, or public `borrow<T>`.
- `Ok` and `Err` require a return, typed binding/assignment, or known-parameter Result context.
- Only `Result<nil, E>` accepts `Ok()`; `Err(value)` always has a payload.
- `@is(value, Ok/Err)` stays generic narrowing and is valid only for a Result value.
- Work in the existing dirty worktree without staging, committing, reverting, or changing unrelated work.
- Every compiler behavior change ends with `./src/build/test/run_tests.sh`.

---

### Task 1: Reserve And Validate The Source Surface

**Files:**
- Modify: `src/build/sema_tokens.zig`, `src/build/sema_type_checks.zig`, `src/build/sema_function_calls.zig`, `src/build/sema_error.zig`, `src/build/diag.zig`, `src/build/sema.zig`
- Create: `src/build/sema_result.zig`
- Create: `src/build/test/compile_ok/344_result_surface.do`
- Create: `src/build/test/err/344_result_type_arity.do`, `src/build/test/err/344_result_type_arity.expect`
- Create: `src/build/test/err/345_result_constructor_context.do`, `src/build/test/err/345_result_constructor_context.expect`
- Create: `src/build/test/err/346_result_constructor_payload.do`, `src/build/test/err/346_result_constructor_payload.expect`

**Interfaces:** Produces `sema_result.check_result_type_refs` and `sema_result.check_result_constructors`; later phases receive a stable Result-specific semantic error rather than an ordinary unresolved-name error.

- [x] **Step 1: Write red fixtures**

```do
parse_flag(value bool) -> Result<bool, u8> { return Ok(value) }
start() {
    result Result<bool, u8> = parse_flag(false)
    if @is(result, Ok) { value bool = result } else { code u8 = result }
}
```

```do
start() { bad Result<i32> = Ok(1) }
```

```do
start() { value = Ok(false) }
```

```do
unit() -> Result<nil, u8> { return Ok(1) }
value() -> Result<bool, u8> { return Ok() }
```

- [x] **Step 2: Verify red**

Run:

```bash
./bin/do build src/build/test/compile_ok/344_result_surface.do -o /tmp/result-surface.wat
./bin/do test src/build/test/err/344_result_type_arity.do
./bin/do test src/build/test/err/345_result_constructor_context.do
./bin/do test src/build/test/err/346_result_constructor_payload.do
```

Expected: the positive form is rejected and negatives lack a Result-specific diagnostic.

- [x] **Step 3: Implement source validation**

```zig
pub fn check_result_type_refs(tokens: []const lexer.Token) !void {
    // `Result` is valid only as Result<T, E> with two type arguments.
}

pub fn check_result_constructors(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    // Resolve Ok/Err only when the enclosing expression has an expected Result.
}
```

Reserve `Result`, `Ok`, and `Err` in declaration positions. Call the Result checks from `sema.check_program` after ordinary type-reference validation. Extend `check_is_type_args` so `Ok`/`Err` are accepted only after a Result value-side check.

- [x] **Step 4: Verify green**

Re-run Step 2, then run `./src/build/test/run_tests.sh`; expect exit code 0.

### Task 2: Resolve Context And Normalize Result Layouts

**Files:**
- Modify: `src/build/sema_result.zig`, `src/build/sema_function_calls.zig`, `src/build/sema_shapes.zig`, `src/build/codegen_model.zig`, `src/build/codegen_collect_util.zig`
- Create: `src/build/test/compile_ok/345_result_contexts.do`
- Create: `src/build/test/err/347_result_invalid_case_selector.do`, `src/build/test/err/347_result_invalid_case_selector.expect`

**Interfaces:** Produces `ResultShape` and `model.result_layout_for_type`, with `Ok = tag 0` and `Err = tag 1`; codegen receives the same normalized representation wherever Result occurs.

- [x] **Step 1: Write red context and selector fixtures**

```do
take(value Result<bool, u8>) -> Result<bool, u8> { return value }
pass() -> Result<bool, u8> { return take(Ok(true)) }
fail() -> Result<bool, u8> { return Err(7) }
unit() -> Result<nil, u8> { return Ok() }
```

```do
Choice = One(i32) | Two(i32)
start() { value Choice = One(1); if @is(value, Ok) { return } }
```

- [x] **Step 2: Verify red**

Run:

```bash
./bin/do build src/build/test/compile_ok/345_result_contexts.do -o /tmp/result-contexts.wat
./bin/do test src/build/test/err/347_result_invalid_case_selector.do
```

Expected: constructor propagation and value-side selector validation fail.

- [x] **Step 3: Implement expected-type propagation**

```zig
pub const ResultShape = struct {
    ok_type: []const u8,
    err_type: []const u8,
    ok_tag: i32 = 0,
    err_tag: i32 = 1,
};

pub fn result_shape_for_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?ResultShape {
    // Return null unless tokens[start_idx..end_idx] is Result<T, E>.
}
```

Propagate expected Result type through return values, typed bindings, assignment targets, and known direct-call parameters. Resolve constructors to the same branch abstraction used by payload-enum constructors. For `@is`, reject `Ok`/`Err` on non-Result values and narrow true/false branches to the selected payload types.

- [x] **Step 4: Verify green**

Re-run Step 2, then run `./src/build/test/run_tests.sh`; expect exit code 0.

### Task 3: Emit Result Values And Ownership Correctly

**Files:**
- Modify: `src/build/codegen_collect_declarations.zig`, `src/build/codegen_union_layout.zig`, `src/build/codegen_emit_union.zig`, `src/build/codegen_emit_expression.zig`, `src/build/codegen_emit_control.zig`, `src/build/codegen_ownership.zig`
- Create: `src/build/test/compile_ok/346_result_managed_payload.do`, `src/build/test/compile_ok/346_result_managed_payload.expect`
- Create: `src/build/test/ok/344_result_runtime_narrowing.do`

**Interfaces:** Consumes Task 2 ResultShape and emits calls, locals, returns, `@is`, and ARC cleanup as one tagged value.

- [x] **Step 1: Write red WAT and runtime fixtures**

```do
choose(ok bool) -> Result<text, text> {
    if ok { return Ok("yes") }
    return Err("no")
}
start() {
    result Result<text, text> = choose(true)
    if @is(result, Ok) { value text = result }
}
```

```do
choose(ok bool) -> Result<i32, i32> { if ok { return Ok(4) }; return Err(9) }
test "result selects payload" {
    value Result<i32, i32> = choose(true)
    if @is(value, Ok) { assert_eq(value, 4) }
}
```

- [x] **Step 2: Verify red**

Run:

```bash
./bin/do build src/build/test/compile_ok/346_result_managed_payload.do -o /tmp/result-managed.wat
./bin/do test src/build/test/ok/344_result_runtime_narrowing.do
```

Expected: no Result constructor lowering or branch extraction exists.

- [x] **Step 3: Reuse union emission with intrinsic layouts**

```zig
pub fn build_result_union_layout(
    allocator: std.mem.Allocator,
    shape: ResultShape,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !UnionLayout {
    // [Ok payload slots, Err payload slots, i32 tag]
}
```

Do not synthesize a source declaration. Dispatch intrinsic `Ok`/`Err` through `emit_union_value`, and use the intrinsic layout for Result locals, calls, returns, `@is`, and release plans. Confirm inactive managed slots are zeroed and only the active managed branch is retained or released.

- [x] **Step 4: Verify green**

Re-run Step 2, inspect `/tmp/result-managed.wat` for tag and ARC assertions, then run `./src/build/test/run_tests.sh`; expect exit code 0.

### Task 4: Map Pinned WIT Results To Result

**Files:**
- Modify: `src/build/sema_imports.zig`, `src/build/codegen_wasi_registry.zig`, `src/build/codegen_emit_wasi.zig`, `lib/file.do`, `lib/dir.do`
- Create: `src/build/test/compile_ok/347_wasi_result_open_at.do`, `src/build/test/compile_ok/347_wasi_result_open_at.expect`
- Create: `src/build/test/compile_err/347_wasi_result_mismatch.do`, `src/build/test/compile_err/347_wasi_result_mismatch.expect`

**Interfaces:** Consumes Task 3 intrinsic layout and produces a preferred `Result<DoOk, DoErr>` source form for each known WIT `result<Ok,Err>` signature.

- [x] **Step 1: Write red host-signature fixtures**

```do
File = { id i64 }
FileError = error { FileOpenFailed }
.host_file_open_at = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at", (File, i32, text, i32, i32) -> Result<File, FileError>)
start() {
    opened Result<File, FileError> = host_file_open_at(File{ id = 3 }, 0, "x", 0, 0)
    if @is(opened, Ok) { file File = opened }
}
```

```do
.host_file_open_at = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at", (i32, i32, text, i32, i32) -> Result<i32, bool>)
```

- [x] **Step 2: Verify red**

Run:

```bash
./bin/do build src/build/test/compile_ok/347_wasi_result_open_at.do -o /tmp/wasi-result-open-at.wat
./bin/do build src/build/test/compile_err/347_wasi_result_mismatch.do -o /tmp/wasi-result-mismatch.wat
```

Expected: the preferred source form is not yet accepted and mismatch diagnostics are not Result-aware.

- [x] **Step 3: Implement WIT mapping**

Add `Result<DoOk, DoErr>` as the preferred source result of every pinned WIT `result<Ok,Err>`, retaining legacy ordinary-union forms only where existing regressions require it. Parse Result arguments for host-signature matching; do not compare raw spelling. Change specialized WIT emitters to materialize tag `0` for WIT Ok and tag `1` for WIT Err with the canonical payload order. Migrate `open_file_at` and `open_dir_at` wrappers to Result.

- [x] **Step 4: Verify green**

Re-run Step 2, then run `./src/build/test/run_tests.sh`; expect exit code 0.

### Task 5: Publish The Verified Contract

**Files:**
- Modify: `doc/grammar.peg`, `doc/spec_rules.md`, `doc/wit/wasi_p3_lowering.md`, `doc/host-binding-design.md`, `doc/async-design.md`, `lib/file.do`, `lib/dir.do`

**Interfaces:** Produces a public language specification that distinguishes Result from ordinary unions and documents only implemented WIT behavior.

- [x] **Step 1: Add the acceptance example**

```do
open_file_at(dir Dir, path text) -> Result<File, FileError> {
    return host_file_open_at(dir, 0, path, 0, 0)
}
if @is(opened, Ok) { file File = opened } else { error FileError = opened }
```

- [x] **Step 2: Update rules and grammar**

Document intrinsic two-argument Result, contextual constructors, `Result<nil, E>`, and `@is` narrowing. Replace WIT-result-to-ordinary-union recommendations without redefining ordinary source unions.

- [x] **Step 3: Audit and verify**

Run:

```bash
rg -n 'result.*union|union.*result|own<|borrow<|is_ok|is_err|unwrap' doc lib src/build --glob '*.md' --glob '*.do' --glob '*.zig'
./src/build/test/run_tests.sh
git diff --check
git status --short
```

Expected: suite exit code 0, whitespace clean, and no public ownership or Result convenience API documentation.
