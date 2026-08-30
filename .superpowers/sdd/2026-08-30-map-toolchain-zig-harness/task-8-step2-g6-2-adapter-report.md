# Task 8 Step 2 G6.2 adapter report

Date: 2026-08-31

## Changes

- Added the absolute `repo_root/bin/do-toolchain` path and exported the absolute
  `repo_root/toolchain/toolchain.lock.json` path in all four G6.2 list producer
  compiler/assembly gates.
- Replaced direct wasm-tools operations with `parse-core`, `embed-component`,
  `new-component`, and `validate-component`.
- Removed the old `WASM_TOOLS` executable checks and version-related adapter
  assumptions. Existing fixture, marker, layout-value, negative, hash, cleanup,
  and exit-code assertions remain unchanged.

## Verification

1. Command:

   ```text
   for f in examples/p3-runtime/test_do_g6_2_c_min_list_resource_producer.sh examples/p3-runtime/test_do_g6_2_c_min_dynamic_list_resource_producer.sh examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh; do bash -n "$f"; done
   ```

   Result: exit 0.

2. Command:

   ```text
   ! rg -n '(^|[[:space:]])(wasm-tools|\$wasm_tools_bin|WASM_TOOLS)' examples/p3-runtime/test_do_g6_2_c_min_list_resource_producer.sh examples/p3-runtime/test_do_g6_2_c_min_dynamic_list_resource_producer.sh examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh
   ```

   Result: exit 0; no direct invocation remains.

3. Command:

   ```text
   git diff --check
   ```

   Result: exit 0.

4. Command (repository root):

   ```text
   for f in examples/p3-runtime/test_do_g6_2_c_min_list_resource_producer.sh examples/p3-runtime/test_do_g6_2_c_min_dynamic_list_resource_producer.sh examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh; do bash "$f"; done
   ```

   Result: all four gates passed; each exited 0.

5. Command (unrelated temporary cwd):

   ```text
   probe_cwd=$(mktemp -d /tmp/do-g6-2-adapter-cwd.XXXXXX); for f in "$PWD/examples/p3-runtime/test_do_g6_2_c_min_list_resource_producer.sh" "$PWD/examples/p3-runtime/test_do_g6_2_c_min_dynamic_list_resource_producer.sh" "$PWD/examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh" "$PWD/examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh"; do (cd "$probe_cwd" && bash "$f"); done; rmdir "$probe_cwd"
   ```

   Result: all four gates passed; each exited 0 and the temporary directory was removed.

6. Command:

   ```text
   bash examples/p3-runtime/test_wasm_tools_current_only.sh
   ```

   Result: `wasm-tools current-only guard passed through do-toolchain adapter`; exit 0.

## Concern

The adapter intentionally owns the wasm-tools feature flags and accepts the
embed world as a positional argument. The scripts therefore omit the old
`--features` and `--world` forms while preserving the same world and feature
semantics through the adapter.
