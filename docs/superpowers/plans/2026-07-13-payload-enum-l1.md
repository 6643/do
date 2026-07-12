# Payload Enum L1 Implementation Plan

> **For agentic workers:** TDD per task; `fail=0` before done claim.

**Goal:** Ship payload enum L1: declare, construct, `@is` narrow, pass/return.

**Spec:** `docs/superpowers/specs/2026-07-13-payload-enum-design.md`

## Task 1: Declare + type exists

- Fixture `compile_ok/289_payload_enum_decl.do`: only decl + empty start referencing type as local type annotation if needed
- `isPayloadEnumDeclStart`, collect cases, register as declared type
- Exclude from InvalidBindingName / union-alias false positives
- `compile_err` for `Message = Red(0) | Text([u8])` mix if easy

## Task 2: Construct + @is + use

- Fixture: construct Quit/Text, `@is`, return Message
- Codegen: payload enum layout, construct, is-narrow
- Reuse union tag+payload patterns where possible; **tags by case name**, not payload type (Text vs Binary both [u8])

## Task 3: Docs + suite + push

- `doc/syntax/enum.md`, grammar note, CHANGELOG
- Full regression, push

## Constraints

- Do not implement L2/L3
- Prefer `src/` paths; no `bin/do` commit
