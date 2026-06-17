# Value Enum Eq/Is Doc Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync the syntax docs so `value enum` uses `@eq/@ne` for branch-value comparison and `@is` remains type-only.

**Architecture:** Keep the change purely in documentation. Update the enum syntax page to show the `ByteKind`/`OrderStatus` usage pattern, and tighten the builtin page so `@is(value, TypeExpr)` is explicitly type-only and cannot be used for `ByteDigit` or `nil`. Do not touch compiler behavior or tests in this change.

**Tech Stack:** Markdown docs only.

---

### Task 1: Update value enum usage docs

**Files:**
- Modify: `doc/syntax/enum.md`

- [x] **Step 1: Edit the usage section**

Add one rule line under `## 枚举值使用` stating that `value enum` branch values are compared with `@eq/@ne`, and `@is` is not for branch matching.

```md
规则: `value enum` 的分支值用 `@eq/@ne` 比较; `@is` 只做类型判断, 不用于分支值匹配。
```

- [x] **Step 2: Verify the edited doc reads cleanly**

Run: `sed -n '1,120p' doc/syntax/enum.md`
Expected: the `OrderStatus` example still shows `@eq(status, OrderPaid)`, and the new rule line appears after it.

- [x] **Step 3: Commit-ready diff check**

Run: `git diff -- doc/syntax/enum.md`
Expected: only the new rule line is added.

### Task 2: Tighten builtin `@is` wording

**Files:**
- Modify: `doc/syntax/builtin.md`

- [x] **Step 1: Edit the `@is` rule**

Replace the existing rule line with a version that says `@is(value, TypeExpr)` is type-only, and that `value enum` branch values and `nil` are values compared with `@eq/@ne`.

```md
规则: `@is(value, TypeExpr)` 只做类型分支判断, 第二个实参必须是类型表达式。`value enum` 的分支值和 `nil` 都是值, 统一使用 `@eq/@ne` 判断, 不写成 `@is(value, ByteDigit)` 或 `@is(value, nil)`。
```

- [x] **Step 2: Verify the wording is consistent**

Run: `sed -n '1,80p' doc/syntax/builtin.md`
Expected: the examples still show `@is(value, User)` and `@is(value, FileError)`, while the rule line excludes branch-value matching.

- [x] **Step 3: Commit-ready diff check**

Run: `git diff -- doc/syntax/builtin.md`
Expected: only the rule line changes, no surrounding example churn.

### Task 3: Cross-check doc consistency

**Files:**
- Read: `doc/syntax/enum.md`
- Read: `doc/syntax/builtin.md`

- [x] **Step 1: Confirm the two pages do not conflict**

Run: `rg -n "@eq\\(status, OrderPaid\\)|@is\\(value, TypeExpr\\)|ByteDigit|nil" doc/syntax/enum.md doc/syntax/builtin.md`
Expected: `enum.md` points to `@eq` for enum branches, and `builtin.md` reserves `@is` for type expressions only.

- [x] **Step 2: Final diff inspection**

Run: `git diff -- doc/syntax/enum.md doc/syntax/builtin.md`
Expected: the final diff matches the intended doc-only sync.

- [x] **Step 3: Stop before implementation**

Do not touch parser, sema, codegen, or tests in this plan. The next step after this plan is user approval, then implementation if requested.
