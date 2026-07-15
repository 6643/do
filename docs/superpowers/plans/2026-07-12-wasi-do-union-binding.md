# WASI Do-Union Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Accept do types in `@host` WASI signatures—especially `Ok | Err` and `T | nil`—map them to WIT, lower calls as exclusive unions, and migrate stdlib hosts off WIT `result<>` literals.

**Architecture:** Extend known-target `do_params`/`do_result` and host signature parsing so do sugar includes resource names and unions. Codegen synthesizes `Ok | Err` (payload + tag) from existing result-area/status strategies. No `@wasi_result` type constructor. Transition: keep accepting `result<…>` until fixtures/stdlib migrate.

**Tech Stack:** Zig compiler (`src/build/`), fixtures under `src/build/test/`, stdlib `lib/{dir,file,io.stream,time}.do`, docs under `doc/`.

**Spec:** `docs/superpowers/specs/2026-07-12-wasi-do-union-binding-design.md`

## Global Constraints

- Result model is exclusive `Ok | Err` / `T | nil` — never multi-return `Ok, Err` as source model.
- Phase-1 Err arm is `i32` status (0 is not an err arm value).
- No `@wasi_result` / `@wasi_option` / `@wasi_tuple` wrappers.
- Keep `@host` / `@wasi_resource` / `@wasi_record` only for entities.
- Do not implement G6.2/G6.3 or `@wasi_enum` productization.
- TDD: red fixture before compiler change; `./src/build/test/run_tests.sh` before done claims.
- Prefer `src/` paths; do not commit `bin/do` unless already tracked and required.
- Public stdlib APIs (`open_dir_at` → `Dir | DirError`) stay; only host lines + wrapper bodies thin out.

## File map

| Path | Responsibility |
|------|----------------|
| `src/build/sema.zig` | known table `do_result`/`do_params`; accept union/resource in host sig compare |
| `src/build/codegen_api.zig` | lower `host()` into `Ok\|Err` locals; statement discard; arg `Dir` → id |
| `src/build/imports.zig` | host binding type surface if needed |
| `src/build/diag.zig` | messages mention `Ok\|Err` / `nil\|i32` |
| `lib/dir.do`, `lib/file.do`, `lib/io.stream.do` | host sigs + thin wrappers |
| `src/build/test/compile_ok/279_*.do` … | new TDD fixtures |
| `src/build/test/compile_ok/100_*.do` etc. | migrate or dual-accept |
| `doc/spec_rules.md`, `doc/wit/wasi_p3_lowering.md`, `doc/grammar.peg` | document surface |

---

### Task 1: TDD — unit fallible host as `nil | i32` (statement + bind)

**Files:**
- Create: `src/build/test/compile_ok/279_wasi_union_unit_result_nil_i32.do`
- Create: `src/build/test/compile_ok/279_wasi_union_unit_result_nil_i32.expect`
- Modify (later steps): `src/build/sema.zig` known table + sig compare; `src/build/codegen_api.zig` if call lower needs union
- Test: build fixture; suite case 279

**Interfaces:**
- Consumes: existing unit result-area lower (`descriptor.sync`)
- Produces: host sig `(i32) -> nil | i32` accepted; statement call + `s nil | i32 = host(...)` both work

- [ ] **Step 1: Write failing fixture**

`279_wasi_union_unit_result_nil_i32.do`:

```do
host_file_sync = @host("wasi:filesystem/types@0.3.0", "descriptor.sync", (i32) -> nil | i32)

start() {
    host_file_sync(1)
    s nil | i32 = host_file_sync(1)
    _ = s
    return
}
```

`279_wasi_union_unit_result_nil_i32.expect` (adjust after first green to real substrings):

```text
;; wasi-bind
filesystem/types/descriptor.sync
result<_,error-code>
```

- [ ] **Step 2: Run red**

```bash
cd /home/_/._/do && ./bin/do build src/build/test/compile_ok/279_wasi_union_unit_result_nil_i32.do -o /tmp/279.wat 2>&1
```

Expected: non-zero (unknown sig / invalid import) until Task 1 implement.

- [ ] **Step 3: Extend known table `do_result`**

In `src/build/sema.zig` known entry for `filesystem/types/descriptor.sync`, set or add:

```zig
.do_params = "i32",
.do_result = "nil|i32",  // compact form without spaces; match compactTokenRangeEquals style used elsewhere
```

Also ensure signature comparison normalizes `|` unions (strip spaces: `nil | i32` → `nil|i32`).

If `compactTokenRangeEquals` fails on `|`, add a compact normalizer for host result spans that drops spaces around `|`.

- [ ] **Step 4: Manifest still stores WIT**

When source uses `nil|i32`, binding.result must remain `result<_,error-code>` (codegen strategies key off WIT).

- [ ] **Step 5: Call typing + lower**

- Statement `host_file_sync(1)`: keep existing statement-only unit path.
- Binding `s nil | i32 = host_file_sync(1)`: synthesize union from status (tag: nil vs i32). Reuse existing union payload+tag locals pattern from `File | FileError`.

Minimal approach if full union synth is large: **phase 1a** accept sig only + statement; **phase 1b** assignment to `nil|i32`. Prefer both green in Task 1 if feasible; if not, split 1b to Task 2 and note in report.

- [ ] **Step 6: Green + commit**

```bash
./bin/do build src/build/test/compile_ok/279_wasi_union_unit_result_nil_i32.do -o /tmp/279.wat
./src/build/test/run_tests.sh 2>&1 | tee /tmp/t1.log | tail -5
git add src/build/test/compile_ok/279_* src/build/sema.zig src/build/codegen_api.zig
git commit -m "feat: accept nil|i32 wasi host result for unit fallible"
```

---

### Task 2: TDD — payload fallible `i32 | i32` then `Dir | i32` open-at

**Files:**
- Create: `src/build/test/compile_ok/280_wasi_union_open_dir_i32.do` + `.expect`
- Create: `src/build/test/compile_ok/281_wasi_union_open_dir_resource.do` + `.expect` (Dir param + Dir|i32 result)
- Modify: `sema.zig` known `open-at` do_result; `codegen_api.zig` descriptor+status → `Dir|i32` or `i32|i32` union

**Interfaces:**
- Consumes: existing `emitWasiResultDescriptor*` 
- Produces: `-> i32 | i32` (descriptor sugar + status as union) and `-> Dir | i32` with `Dir` param

- [ ] **Step 1: Fixture 280 (no resource yet)**

```do
host_open = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at",
  (i32, i32, text, i32, i32) -> i32 | i32
)
start() {
    r i32 | i32 = host_open(1, 0, "x", 2, 0)
    _ = r
    return
}
```

Known table:

```zig
.do_result = "i32|i32",  // ok descriptor sugar | status
```

Note: both arms `i32` are ambiguous for `@is` — **prefer not shipping `i32|i32` as public style**. If `@is` cannot distinguish, skip 280 and go straight to 281 with `Dir | i32` only.

**Preferred 281 only:**

```do
.host_open = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at",
  (Dir, i32, text, i32, i32) -> Dir | i32
)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
start() {
    p Dir = Dir{id = 1}
    r Dir | i32 = host_open(p, 0, "x", 2, 0)
    _ = r
    return
}
```

- [ ] **Step 2: Red then implement**

- `do_params` allow leading `Dir` equivalent to `i32`/`descriptor` for open-at.
- Arg lower: `Dir` → `@get`/field `.id` as i32/i64 per existing drop paths.
- Result lower: build `Dir | i32` union (Dir payload = id, tag; err = status).

- [ ] **Step 3: Green + commit**

```bash
git commit -m "feat: Dir|i32 wasi open-at host union result and Dir param"
```

---

### Task 3: TDD — write path `u64 | i32` and read tuple payload as do types

**Files:**
- Create: `src/build/test/compile_ok/282_wasi_union_write_u64_i32.do` + expect
- Modify: known write entry `do_result = "u64|i32"`; codegen filesize multi → union assign
- Optional: read `Tuple<[u8],bool> | i32` if Tuple-in-union is ready; else keep transitional `result<tuple<…>>` for read only and document defer

**Interfaces:**
- Consumes: `emitWasiResultFilesize*`
- Produces: `s u64 | i32 = host_write(...)`

- [ ] **Step 1: Fixture**

```do
host_write = @host("wasi:filesystem/types@0.3.0", "descriptor.write",
  (i32, [u8], u64) -> u64 | i32
)
start() {
    n u64 | i32 = host_write(1, "ab", 0)
    _ = n
    return
}
```

- [ ] **Step 2: Implement + green + commit**

```bash
git commit -m "feat: u64|i32 wasi write host union result"
```

---

### Task 4: Stdlib migration (dir + file hosts)

**Files:**
- Modify: `lib/dir.do`, `lib/file.do`, `lib/io.stream.do`
- Modify: wrappers to use `r Ok|i32` + `@is` instead of multi-lhs where Task 1–3 enable
- Test: existing `124_*`, `125_*`, `103_*`, `275_*` compile_ok imports

**Interfaces:**
- Public functions unchanged.
- Private hosts use new sigs.

- [ ] **Step 1: dir.do hosts**

```do
.host_dir_create_at = @host("wasi:legacy@0.3.0", "…create-directory-at", (Dir, text) -> nil | i32)
.host_dir_open_at = @host("wasi:legacy@0.3.0", "…open-at", (Dir, i32, text, i32, i32) -> Dir | i32)
.host_dir_remove_at = @host("wasi:legacy@0.3.0", "…remove-directory-at", (Dir, text) -> nil | i32)
.host_dir_drop = @host("wasi:legacy@0.3.0", "…descriptor.drop", (Dir) -> nil)
// preopens: keep list sugar until list-of-Dir lands; may stay list<tuple<i32,text>> or [Tuple<Dir,text>] if ready
.host_preopens = @host("wasi:legacy@0.3.0", "…get-directories", () -> list<tuple<i32,text>>)
```

Place **all hosts before** `Dir = @wasi_resource` (import prefix rule). Resource type used in host sigs: if parser requires type already declared, either (a) allow forward ref for wasi_resource names in host sigs, or (b) keep `i32` params until forward-ref works. **Prefer (a)**; if blocked, document and use `i32` params + `Dir|i32` result only.

- [ ] **Step 2: Thin wrappers**

```do
open_dir_at(parent Dir, path text) -> Dir | DirError {
    r Dir | i32 = host_dir_open_at(parent, 0, path, 2, 0)
    if @is(r, Dir) return r
    return DirOpenFailed
}
```

Similar for create/remove/sync/write.

- [ ] **Step 3: file.do + io.stream.do analogously**

- [ ] **Step 4: Run import fixtures + full suite + commit**

```bash
./src/build/test/run_tests.sh 2>&1 | tee /tmp/t4.log | tail -10
git commit -m "refactor(stdlib): wasi hosts use Ok|Err and Dir params"
```

---

### Task 5: Migrate core wasi result fixtures off WIT `result<>` where lowerable

**Files:**
- Modify: `100_wasi_result_unit_statement_lower.do` → `nil | i32` (keep behavior)
- Modify: `101`/`102` write fixtures → `u64 | i32` if Task 3 done
- Modify: expects for wasi-bind result strings (WIT form may remain in manifest comments)
- Leave unsupported/complex signatures on WIT form

- [ ] **Step 1: Update fixtures one-by-one with TDD (expect adjust)**
- [ ] **Step 2: Suite green + commit**

```bash
git commit -m "test: migrate wasi result fixtures to Ok|Err do unions"
```

---

### Task 6: Docs + dual-accept policy

**Files:**
- Modify: `doc/spec_rules.md` §21/§23
- Modify: `doc/wit/wasi_p3_lowering.md` Declarative host surface
- Modify: `doc/grammar.peg` if HostImport result type needs union production note
- Modify: `CHANGELOG.md` brief

**Content to state:**
- Preferred: `Ok | Err`, `T | nil`, resource/record names in `@host`
- Forbidden: multi-return as WASI result model
- Transition: `result<…>` still accepted for known targets
- No `wasi_result` / `wasi_option` wrappers
- Structures: `Tuple` / record / multi-arg — not `@wasi_tuple`

- [ ] **Step 1: Edit docs**
- [ ] **Step 2: Commit**

```bash
git commit -m "docs: WASI host signatures use do Ok|Err and T|nil"
```

---

### Task 7: Full verification

**Files:** none

- [ ] **Step 1:** `cd src && zig build -Doptimize=Debug`
- [ ] **Step 2:** `./src/build/test/run_tests.sh` → `fail=0`
- [ ] **Step 3:** Spot-check `lib/*.do` host lines use unions/resources
- [ ] **Step 4:** Completion claim only with verbatim suite summary

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| `nil \| i32` unit result | 1, 5 |
| `Dir \| i32` / payload unions | 2, 3 |
| Resource params | 2, 4 |
| No wasi_result wrappers | all |
| Stdlib migration | 4 |
| Fixture migration | 5 |
| Docs | 6 |
| Regression green | 7 |
| Structures via Tuple/record not wasi_tuple | 6 (docs); Tuple-in-sig as follow-up if not in 2–3 |

## Out of scope / follow-ups

- `Tuple<[u8],bool> | i32` full read path (may ship later)
- `[Tuple<Dir,text>]` preopens element type
- Err arm as `DirError` / `@wasi_enum`
- Removing WIT `result<>` accept path entirely

---

## Execution handoff

Plan saved to `docs/superpowers/plans/2026-07-12-wasi-do-union-binding.md`.

**1. Subagent-Driven (recommended)** — fresh subagent per task + review  
**2. Inline Execution** — this session with executing-plans  

Which approach?

undefined
undefined
undefined
