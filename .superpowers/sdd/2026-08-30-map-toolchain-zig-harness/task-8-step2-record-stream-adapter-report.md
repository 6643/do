# Task 8 Step 2 record-resource stream adapter batch report

## Scope

Migrated the nine record-resource stream pure assembly/validation gates named
in `task-8-step2-record-stream-adapter-brief.md`. Each now derives the
repository-root `bin/do-toolchain` path and exports the repository lock path;
all four assembly/validation operations use the typed adapter. Fixture,
world, marker/count/hash/negative assertions, explicit validation, cleanup,
and exit semantics were preserved.

## Verification

All commands were run from `/home/_/._/_/do` unless noted.

```text
bash -n examples/p3-runtime/test_do_record_resource_stream_probe_lowering.sh examples/p3-runtime/test_do_record_resource_stream_multi_probe_lowering.sh examples/p3-runtime/test_do_record_resource_stream_multiple_nested_probe_lowering.sh examples/p3-runtime/test_do_record_resource_stream_nested_probe_lowering.sh examples/p3-runtime/test_do_record_resource_stream_nested_two_level_probe_lowering.sh examples/p3-runtime/test_do_record_resource_stream_nested_three_level_probe_lowering.sh examples/p3-runtime/test_do_record_resource_stream_nested_four_level_probe_lowering.sh examples/p3-runtime/test_do_record_resource_stream_nested_five_level_probe_lowering.sh examples/p3-runtime/test_do_record_resource_stream_nested_six_level_probe_lowering.sh
exit=0

bash examples/p3-runtime/test_do_record_resource_stream_probe_lowering.sh
exit=0
bash examples/p3-runtime/test_do_record_resource_stream_multi_probe_lowering.sh
exit=0
bash examples/p3-runtime/test_do_record_resource_stream_multiple_nested_probe_lowering.sh
exit=0
bash examples/p3-runtime/test_do_record_resource_stream_nested_probe_lowering.sh
exit=0
bash examples/p3-runtime/test_do_record_resource_stream_nested_two_level_probe_lowering.sh
exit=0
bash examples/p3-runtime/test_do_record_resource_stream_nested_three_level_probe_lowering.sh
exit=0
bash examples/p3-runtime/test_do_record_resource_stream_nested_four_level_probe_lowering.sh
exit=0
bash examples/p3-runtime/test_do_record_resource_stream_nested_five_level_probe_lowering.sh
exit=0
bash examples/p3-runtime/test_do_record_resource_stream_nested_six_level_probe_lowering.sh
exit=0

unrelated_cwd=$(mktemp -d); cd "$unrelated_cwd"
bash /home/_/._/_/do/examples/p3-runtime/test_do_record_resource_stream_probe_lowering.sh
exit=0
bash /home/_/._/_/do/examples/p3-runtime/test_do_record_resource_stream_multi_probe_lowering.sh
exit=0
bash /home/_/._/_/do/examples/p3-runtime/test_do_record_resource_stream_multiple_nested_probe_lowering.sh
exit=0
bash /home/_/._/_/do/examples/p3-runtime/test_do_record_resource_stream_nested_probe_lowering.sh
exit=0
bash /home/_/._/_/do/examples/p3-runtime/test_do_record_resource_stream_nested_two_level_probe_lowering.sh
exit=0
bash /home/_/._/_/do/examples/p3-runtime/test_do_record_resource_stream_nested_three_level_probe_lowering.sh
exit=0
bash /home/_/._/_/do/examples/p3-runtime/test_do_record_resource_stream_nested_four_level_probe_lowering.sh
exit=0
bash /home/_/._/_/do/examples/p3-runtime/test_do_record_resource_stream_nested_five_level_probe_lowering.sh
exit=0
bash /home/_/._/_/do/examples/p3-runtime/test_do_record_resource_stream_nested_six_level_probe_lowering.sh
exit=0

bash examples/p3-runtime/test_wasm_tools_current_only.sh
wasm-tools current-only guard passed through do-toolchain adapter
exit=0

git diff --check -- \
  examples/p3-runtime/test_do_record_resource_stream_probe_lowering.sh \
  examples/p3-runtime/test_do_record_resource_stream_multi_probe_lowering.sh \
  examples/p3-runtime/test_do_record_resource_stream_multiple_nested_probe_lowering.sh \
  examples/p3-runtime/test_do_record_resource_stream_nested_probe_lowering.sh \
  examples/p3-runtime/test_do_record_resource_stream_nested_two_level_probe_lowering.sh \
  examples/p3-runtime/test_do_record_resource_stream_nested_three_level_probe_lowering.sh \
  examples/p3-runtime/test_do_record_resource_stream_nested_four_level_probe_lowering.sh \
  examples/p3-runtime/test_do_record_resource_stream_nested_five_level_probe_lowering.sh \
  examples/p3-runtime/test_do_record_resource_stream_nested_six_level_probe_lowering.sh \
  .superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step2-record-stream-adapter-report.md
exit=0
```

## Remaining direct-tool gates

This batch intentionally did not modify out-of-scope files. The following
reproducible inventory reports 127 remaining `examples/p3-runtime` shell
gates containing a direct `wasm-tools parse`, `component embed`, `component
new`, or `validate` invocation:

```text
rg -l 'wasm-tools (parse|component embed|component new|validate)' examples/p3-runtime --glob '*.sh' | sort
result: 127 paths
```

This batch does not claim Task 8 Step 2 or all pure scripts complete.
