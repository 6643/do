# Declarative WASI Surface Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the already-designed declarative WASI host surface (`@host` / `@wasi_resource` / `@wasi_record`, stdlib aligned, bare `@wasi` removed) with Superpowers discipline: TDD for residual gaps, verification evidence, no re-open of G6.2–G6.3.

**Architecture:** Compiler host import only accepts `@host`. Type shells use `@wasi_resource` / `@wasi_record` after the import prefix. Field collection clamps to `}`. Known targets still lower via existing result-area / resource-drop / preopens strategies. Coarse `DirError`/`FileError` stay plain `error =`; `@wasi_enum` remains optional grammar/parser stub unless a later task productizes it.

**Tech Stack:** Zig compiler under `src/build/`, `.do` fixtures under `src/build/test/`, docs under `doc/`, stdlib under `lib/`.

**Design status:** Approved in-session (declarative forms, import-prefix hosts, do sugar → WIT in codegen, delete bare `@wasi`). This plan does **not** re-brainstorm. It closes implementation debt and TDD holes.

## Global Constraints

- Do not reintroduce the removed single-locator WASI host form.
- Do not expand G6.2 (`read-directory` stream/future) or G6.3 (sockets variant) without separate design.
- Host imports stay in module import prefix; type bindings after hosts.
- Behavior changes require red → green fixture cycles under `src/build/test/`.
- Verification: `cd src && zig build -Doptimize=Debug` then `./src/build/test/run_tests.sh` before any completion claim.
- Prefer `src/` paths (not legacy `tool/`).

## Already landed (do not redo; verify only)

| Item | Evidence location |
|------|-------------------|
| Stdlib `@host` + resource/record | `lib/{dir,file,time,random,io.stream}.do` |
| Single-line field clamp | `src/build/codegen_api.zig` `appendStructFieldsInBraceRange`; `sema.zig` `collectStructInfos` |
| Fixtures multi-line + single-line | `compile_ok/276`, `compile_ok/277` |
| Bare `@wasi` removed from compiler checks | `parser`/`sema`/`codegen`/`imports`/`diag` only `wasi_func` for host |
| Docs §21.1 host-first legal sample | `doc/spec_rules.md` |
| Grammar only `@host` for host | `doc/grammar.peg` `WasiHostImport` |

## File map (closeout touches)

| Path | Role |
|------|------|
| `src/build/test/err/278_bare_wasi_alias_rejected.do` + `.expect` | TDD: bare `@wasi` must not parse as host import |
| `src/build/test/compile_ok/277_*.do` | Already present; re-verify red-green if regressing field scan |
| `src/build/diag.zig` | Messages already say `@host`; keep consistent with expect |
| `doc/spec_rules.md` / `doc/wit/wasi_p3_lowering.md` / `CHANGELOG.md` | Final doc sync only if drift found |
| `lib/*.do` | No API change unless host prefix order broken |

---

### Task 1: TDD lock — removed single-locator WASI host form rejected

**Files:**
- Create: `src/build/test/err/278_bare_wasi_alias_rejected.do`
- Create: `src/build/test/err/278_bare_wasi_alias_rejected.expect`
- Modify: none if current compiler already rejects (expect may match `InvalidBindingName` or `InvalidImportDecl` — capture **actual** diagnostic after red run)
- Test: `./src/build/test/run_tests.sh` filtered by case name if supported, else full suite later

**Interfaces:**
- Consumes: host import recognition that only accepts `wasi_func` / `env` / `lib`
- Produces: regression that bare `@wasi` cannot silently become a host binding

- [ ] **Step 1: Write the failing test (fixture)**

`278_bare_wasi_alias_rejected.do`:

```do
host_res = @legacy_host("clocks/system-clock/get-resolution", () -> u64)
start() {
    _ = host_res()
}
```

`278_bare_wasi_alias_rejected.expect` (first draft; adjust after Step 2 to exact substrings):

```text
error[
Invalid
```

- [ ] **Step 2: Run to confirm it fails for the right reason**

```bash
cd /home/_/._/do
./bin/do build src/build/test/err/278_bare_wasi_alias_rejected.do -o /tmp/278.wat 2>&1 | tee /tmp/278.out
```

Expected: non-zero exit; must **not** produce successful WAT with wasi-bind for `host_res`.
Copy real `error[...]` lines into `.expect` (one substring per line, project convention).

- [ ] **Step 3: If build currently accepts bare `@wasi`, fix compiler**

Only if Step 2 succeeds incorrectly:
- Ensure `isHostImportLine` / `isWasiHostImportStart` / parser import head reject `"wasi"` (keep `"wasi_func"` only).
- Minimal change in `src/build/sema.zig`, `imports.zig`, `codegen_api.zig`, `parser.zig` as needed.

- [ ] **Step 4: Run err case via suite**

```bash
./src/build/test/run_tests.sh 2>&1 | tee /tmp/wasi_closeout_t1.log | rg '278_bare|summary:|FAIL'
```

Expected: case PASS; no new fails.

- [ ] **Step 5: Commit**

```bash
git add src/build/test/err/278_bare_wasi_alias_rejected.do \
        src/build/test/err/278_bare_wasi_alias_rejected.expect \
        # plus any compiler files only if Step 3 changed them
git commit -m "test: reject bare @wasi host alias after wasi_func-only surface"
```

---

### Task 2: TDD lock — single-line resource field body (prove red/green if needed)

**Files:**
- Existing: `src/build/test/compile_ok/277_wasi_resource_single_line.do`
- Existing: `src/build/test/compile_ok/277_wasi_resource_single_line.expect`
- Modify only if green breaks: `src/build/codegen_api.zig` `appendStructFieldsInBraceRange`, `src/build/sema.zig` `collectStructFieldInfos`

**Interfaces:**
- Consumes: `Dir = @wasi_resource("…", { .id i64 })` same-line body
- Produces: ctor `@get(d, .id)` + drop lower with `local.set $d.id`

- [ ] **Step 1: Confirm green on current tree**

```bash
./bin/do build src/build/test/compile_ok/277_wasi_resource_single_line.do -o /tmp/277.wat
rg -n 'd\.id|resource-drop' /tmp/277.wat
```

Expected: exit 0; contains `local.set $d.id` and `[resource-drop]descriptor`.

- [ ] **Step 2: Optional red proof (recommended once)**

Temporarily remove `close_brace` clamp in `appendStructFieldsInBraceRange` (or force `line_end` past `}`), rebuild, re-run 277 — expect fail. Restore clamp, re-run — expect pass. Do **not** leave red code.

- [ ] **Step 3: Commit only if Step 2 required a code fix**

```bash
git commit -m "fix: clamp wasi_resource single-line field type end at close brace"
```

If already green and no code change, skip commit for this task.

---

### Task 3: Doc/impl consistency pass (declarative surface only)

**Files:**
- Read/Modify as needed: `doc/spec_rules.md` §21 / §21.1, `doc/grammar.peg`, `doc/wit/wasi_p3_lowering.md` Declarative host surface table, `CHANGELOG.md`
- Do **not** rewrite G6.2/G6.3 blocked text unless factually wrong

**Interfaces:**
- Spec must say: host form is `@host` only; no transition `@wasi`
- Legal sample: all hosts before resource/record
- `@wasi_enum` documented as optional / not required for stdlib coarse errors

- [ ] **Step 1: Grep drift**

```bash
rg -n '@wasi\(|过渡|transition alias|bare `@wasi`' doc lib src --glob '!**/CHANGELOG.md' || true
rg -n 'WasiHostImport|@host' doc/grammar.peg
```

Expected: no legacy single-locator host form outside historical notes.

- [ ] **Step 2: Fix any remaining doc contradictions**

Minimal edits only; keep §21.1 host-first legal example.

- [ ] **Step 3: Commit**

```bash
git add doc/ CHANGELOG.md
git commit -m "docs: declarative WASI surface is wasi_func-only"
```

---

### Task 4: Explicit non-goals check (`@wasi_enum`, G6.2/G6.3)

**Files:**
- Read only: `doc/pending_blocked.md`, `doc/spec_rules.md` §21.1, `src/build/parser.zig` wasi_enum stub

- [ ] **Step 1: Confirm product decision still holds**

| Item | Status to preserve |
|------|--------------------|
| `@wasi_enum` full lower + stdlib migration | **Out of scope** unless user re-opens |
| G6.2 read-directory | **Blocked** (async) |
| G6.3 sockets | **Blocked** (mapping) |
| Coarse DirError/FileError hand-written | **Keep** |

- [ ] **Step 2: No code unless decision flipped**

If user later wants `@wasi_enum` productized, open a **new** plan; do not sneak into this closeout.

---

### Task 5: Full verification before any “done” claim

**Files:** none (commands only)

- [ ] **Step 1: Debug build**

```bash
cd /home/_/._/do/src && zig build -Doptimize=Debug
```

Expected: exit 0; `bin/do` updated.

- [ ] **Step 2: Full regression**

```bash
cd /home/_/._/do && ./src/build/test/run_tests.sh 2>&1 | tee /tmp/wasi_closeout_full.log | tail -20
```

Expected: `fail=0`; note `pass=` and `skip=` counts in the commit message / handoff.

- [ ] **Step 3: Spot-check stdlib host surface**

```bash
rg -n '@host|@wasi_resource|@wasi_record|@wasi\(' lib/*.do
```

Expected: only `@host` / `@wasi_resource` / `@wasi_record` host declarations.

- [ ] **Step 4: Completion claim format**

Only after Steps 1–3 evidence:

```text
Closeout complete: pass=N fail=0 skip=M; 278 bare-wasi err locked; 277 single-line green; docs wasi_func-only.
```

Do not claim complete from earlier session logs alone.

---

### Task 6: Working tree commit hygiene (optional batch)

**Files:** current uncommitted wasi/stdlib/compiler/docs (large tree)

- [ ] **Step 1: Review `git status` / `git diff --stat`**

Group into logical commits if not already committed by Tasks 1–3:

1. compiler: wasi_func-only + field clamp + collectStructInfos  
2. stdlib: declarative hosts  
3. fixtures: 274–277 + migrated `@wasi`→`@host`
4. docs: grammar/spec/lowering/changelog  

- [ ] **Step 2: User-approved commit only**

Do not `git push` unless user asks. Prefer project subject style (short imperative).

---

## Spec coverage checklist

| Design requirement | Task |
|--------------------|------|
| `@host` preferred / only host form | 1, 3 |
| `@wasi_resource` / `@wasi_record` | landed + 2 |
| Import prefix hosts | landed + 3 sample |
| Single-line field body | 2 |
| Stdlib aligned | landed + 5 spot-check |
| Delete bare `@wasi` | 1 |
| No G6.2/G6.3 scope creep | 4 |
| Green regression | 5 |
| TDD for residual behavior | 1, 2 |

## Out of scope (explicit)

- Implementing `@wasi_enum` lowering and stdlib fine error-code enums  
- G6.2 async stream directory listing  
- G6.3 socket resource + address variant  
- Process-style inline ABI inside function bodies as default stdlib style  
- System prompt / AGENTS skill-gate wording (human-owned)

---

## Execution handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-12-declarative-wasi-surface-closeout.md`.**

Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — this session with executing-plans, batch + checkpoints  

Which approach?
