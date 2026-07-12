# A+B Closeout: Thin read wrappers + `[Tuple<…>]` host sugar

> **For agentic workers:** Use superpowers:subagent-driven-development or execute inline with TDD.

**Goal:** (B) Accept `[Tuple<Dir, text>]` (and general `[T]`) in `@wasi_func` results; (A) Prefer exclusive-union host binds in `read_file` / `read_stream` wrappers instead of multi-lhs where possible.

**Architecture:** Extend `parseWitType` list-bracket sugar to recursive element types; add known-table alts; rewrite wrappers to `r = host_…` + `@is` / status map. Public multi-return APIs stay for compatibility.

## Task 1 (B): Nested `[T]` in host signatures

- [ ] Fixture `287_wasi_preopens_bracket_tuple.do`: `() -> [Tuple<Dir, text>]`
- [ ] `parseWitType`: `[` + `parseWitType` + `]`
- [ ] known preopens `do_result_alt = "[Tuple<Dir,text>]"` (compact, no spaces or match spaces)
- [ ] `lib/dir.do` host line use bracket form
- [ ] Green + commit

## Task 2 (A): Thin stream + file read wrappers

- [ ] `read_stream`: `r [u8]|i32 = host_…` then map to public `[u8], StreamError|nil`
- [ ] `read_file`: `r Tuple<[u8],bool>|i32 = host_…` then unpack ok leaves / err status to public multi-return
- [ ] Keep 110/116 compile_ok green
- [ ] Commit

## Task 3: Suite + push

- [ ] fail=0, push main
