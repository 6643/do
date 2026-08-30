# Task 8 Step 2 nested producer Shell adapter migration report

## Files changed

- `examples/p3-runtime/test_do_g6_2_owned_record_nested_producer.sh`
  - Replaced direct `wasm-tools` executable/version checks and assembly calls
    with the repository's current-only `bin/do-toolchain` adapter.
  - Sets `DO_TOOLCHAIN_LOCK` to the repository lock path.
- `examples/p3-runtime/test_g6_2_owned_record_nested_canonical.sh`
  - Replaced direct `wasm-tools` executable/version checks and assembly calls
    with the repository's current-only `bin/do-toolchain` adapter.
  - Sets `DO_TOOLCHAIN_LOCK` to the repository lock path.
- `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step2-nested-adapter-report.md`
  - This report.

No unrelated files were modified by this task.

## Preserved assertions

Both gates retain their existing source/WIT/WAT/hash/marker, ARC, and
reference-boundary assertions, plus existing temporary-directory cleanup.
Neither script retains a wasm-tools version guard or an old-version fallback.

Reviewer follow-up strengthens the canonical gate with the fixed WIT SHA-256
assertion and complete values for all layout, path, capacity, signature,
input-mode, ownership, transfer, drop, and cleanup markers.

## Commands and results

- From repository root `/home/_/._/_/do`:
  - `bash examples/p3-runtime/test_do_g6_2_owned_record_nested_producer.sh`
    - PASS, exit 0. Output included `G6.2 owned-record nested producer Do
      Component gate passed layout=outer:4 alignment:4 inner.ticket-offset:0
      capacity:1`.
  - `bash examples/p3-runtime/test_g6_2_owned_record_nested_canonical.sh`
    - PASS, exit 0. Output included
      `G6.2 owned-record nested canonical contract gate passed
      layout=outer:4 alignment:4 inner.ticket-offset:0 capacity:1
      source=(i32)->(i32)`.
- From unrelated cwd `/tmp/do-g6-2-nested-adapter-cwd.ZRueJ7`:
  - `bash /home/_/._/_/do/examples/p3-runtime/test_do_g6_2_owned_record_nested_producer.sh`
    - PASS, exit 0.
  - `bash /home/_/._/_/do/examples/p3-runtime/test_g6_2_owned_record_nested_canonical.sh`
    - PASS, exit 0. Output included the same canonical contract gate marker.
- `bash examples/p3-runtime/test_wasm_tools_current_only.sh`
  - PASS, exit 0: `wasm-tools current-only guard passed through do-toolchain
    adapter`.
- `git diff --check`
  - PASS, exit 0.

## Reviewer follow-up verification

Pending execution after strengthening the canonical assertions:

- `bash examples/p3-runtime/test_g6_2_owned_record_nested_canonical.sh`
- `bash examples/p3-runtime/test_do_g6_2_owned_record_nested_producer.sh`
- `bash examples/p3-runtime/test_wasm_tools_current_only.sh`
- `git diff --check`
