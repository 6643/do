# Task 8 Step 2 filesystem lowering adapter report

## Scope

Updated only these three pure filesystem lowering gates:

- `examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh`
- `examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh`
- `examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh`

Each script now defines an absolute `toolchain_bin` and exports the repository
`DO_TOOLCHAIN_LOCK`. Core parsing, component embedding, component creation, and
component validation use the current-only typed adapter. The adapter supplies
the existing async component features and fixes `new-component` to use
`--skip-validation`; each script still performs explicit component validation.
Fixture, world, marker, negative/exit, output, and cleanup behavior are
unchanged.

## Verification

Every command below completed with `exit=0`.

```text
bash -n examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh  # exit=0
bash -n examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh  # exit=0
bash -n examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh  # exit=0
bash examples/p3-runtime/test_wasm_tools_current_only.sh  # exit=0
bash examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh  # repository root; exit=0
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh  # repository root; exit=0
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh  # repository root; exit=0
tmp_cwd=$(mktemp -d); (cd "$tmp_cwd" && bash /home/_/._/_/do/examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh); rmdir "$tmp_cwd"  # unrelated temporary cwd; exit=0
tmp_cwd=$(mktemp -d); (cd "$tmp_cwd" && bash /home/_/._/_/do/examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh); rmdir "$tmp_cwd"  # unrelated temporary cwd; exit=0
tmp_cwd=$(mktemp -d); (cd "$tmp_cwd" && bash /home/_/._/_/do/examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh); rmdir "$tmp_cwd"  # unrelated temporary cwd; exit=0
git diff --check -- examples/p3-runtime/test_do_wasi_filesystem_preopen_lowering.sh examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh  # exit=0
```

The root and unrelated-cwd runs both exercised the generated WIT/WAT marker
checks and typed adapter assembly/validation. Temporary directories were
removed by each script's existing trap.

## Residual direct-tool gates

This batch does not close Task 8 Step 2. Other gates still invoke `wasm-tools`
directly, including the remaining `examples/p3-runtime/test_do_*.sh`,
`examples/p3-runtime/test_rust_*.sh`, generic/core async probes, ABI gates, and
the shared `src/build/test/run_tests.sh`/smoke helpers. They remain outside
this batch and require separate scoped migration decisions.
