# Task 8 Step 3 GC host CLI prerequisite follow-up

## Scope

Removed only the unused `WASMTIME_BIN`/`wasmtime_bin` declaration and its executable precondition from the 19 GC marshal record host gates below. Updated only the prerequisite error text where needed; toolchain, compiler, linker, runner, WIT mutation/validation, cleanup, markers, commands, and exit behavior were otherwise preserved.

Files:

- `examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lift_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_lift_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_lower_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_mixed_lift_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_mixed_lower_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_byte_list_lift_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_mixed_text_u32_list_lift_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deep_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deep_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_host.sh`
- `examples/gc-p3-runtime/test_gc_marshal_record_u32_list_lift_manifest_host.sh`

## Red evidence

Before editing:

```text
$ WASMTIME_BIN=/nonexistent bash examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lift_manifest_host.sh
exit=1
missing Wasmtime or Rust runner linker
```

This failure came from the stale Wasmtime executable precondition.

## Green verification

- `bash -n` over all 19 listed scripts: passed.
- Static scan of all 19 scripts for `WASMTIME_BIN`, `wasmtime_bin`, and `$wasmtime`: no matches.
- `git diff --check` over all 19 scripts: passed.
- `WASMTIME_BIN=/nonexistent bash examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lift_manifest_host.sh`: exit 0; byte-list lift host and Component execution passed.
- `WASMTIME_BIN=/nonexistent bash examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_host.sh`: exit 0; indirect scalar lower host and Component execution passed.

## Residuals and concerns

The full 19-script runtime matrix was not rerun; representative gates and structural checks passed. No direct Wasmtime invocation was added or changed.
