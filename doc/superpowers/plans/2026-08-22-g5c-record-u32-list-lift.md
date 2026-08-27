# G5c Bounded Record `list<u32>` Lift Plan

> Execute inline in the current checkout. Preserve unrelated dirty changes;
> do not reset, checkout, clean, commit, or push.

**Spec:** `doc/superpowers/specs/2026-08-22-g5c-record-u32-list-lift-design.md`

## Fixed contract

```text
Reading { code: u32, payload: [u32] }
record result area: 12 bytes, alignment 4
canonical lift: (i32) result-area pointer
payload lengths: 0..3, element stride 4
```

## Tasks

1. Add source/WIT/Do fixtures and a hash-pinned manifest descriptor.
2. Add exact host-boundary admission and six fail-closed negative fixtures.
3. Extend the typed record-lift plan/emitter only for this measured `list<u32>`
   child; copy linear values into `$do_u32`, free once, and build `$do_record`.
4. Add explicit compiler, host, ARC/GC equivalence, and ordinary default-route
   gates; assert no GC reference crosses the canonical import.
5. Run focused Zig tests, all gates, full regression, ReleaseSmall, release
   smoke, and `git diff --check`; keep the 15-row inventory pending.

## Rollback

If a gate fails, remove only this descriptor and its dedicated fixtures/routes;
leave prior lower/lift descriptors and ARC fallback unchanged.
