# Task 8 Step 2 G6.2 owned-record producer adapter report

## Scope

Updated only the four requested compiler/assembly-only gates:

- `examples/p3-runtime/test_do_g6_2_owned_record_producer.sh`
- `examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh`
- `examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer.sh`
- `examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh`

Each gate now uses the absolute repository `bin/do-toolchain` with the
absolute `toolchain/toolchain.lock.json` lock. Direct `wasm-tools` operations,
the old executable checks, and the parameterized gate's version guard were
removed. Existing WIT hashes, shape guards, layout/ownership markers, ARC
guards, cleanup traps, and explicit post-new validation remain intact.

## Verification

All commands below were run from `/home/_/._/_/do` unless noted.

1. `bash -n examples/p3-runtime/test_do_g6_2_owned_record_producer.sh examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer.sh examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh`
   - Passed (exit 0).
2. `if rg -n 'wasm-tools|WASM_TOOLS|component embed|component new|validate --' examples/p3-runtime/test_do_g6_2_owned_record_producer.sh examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer.sh examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh; then exit 1; else echo 'static scan: no direct wasm-tools invocation'; fi`
   - Passed; no matches.
3. `git diff --check`
   - Passed (exit 0).
4. `bash examples/p3-runtime/test_do_g6_2_owned_record_producer.sh`, `bash examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh`, `bash examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer.sh`, `bash examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh`
   - Passed from repository root; all four gates reported `gate passed`.
5. `tmp_cwd=$(mktemp -d); trap 'rmdir "$tmp_cwd" 2>/dev/null || true' EXIT; cd "$tmp_cwd"; bash /home/_/._/_/do/examples/p3-runtime/test_do_g6_2_owned_record_producer.sh; bash /home/_/._/_/do/examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh; bash /home/_/._/_/do/examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer.sh; bash /home/_/._/_/do/examples/p3-runtime/test_do_g6_2_owned_record_triple_producer.sh`
   - Passed from unrelated temporary cwd; all four gates reported `gate passed`.
6. `bash examples/p3-runtime/test_wasm_tools_current_only.sh`
   - Passed: `wasm-tools current-only guard passed through do-toolchain adapter`.

## Concerns

- The worktree contained unrelated pre-existing modifications and untracked
  files. They were preserved and excluded from the scoped commit.
- No full repository regression suite was run; the brief-requested targeted
  gates and static checks passed.
