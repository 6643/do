# Pinned Record Source-Mirror Checkpoint

**Status:** completed and verified on 2026-08-02.

## Goal

Keep the admitted `directory-entry` record-stream descriptor tied to the
checked-in pinned WIT source and reject stale `@wasi_record` declarations.

## Scope

- Verify the pinned filesystem `types.wit`, `world.wit`, and `preopens.wit`
  hashes.
- Verify the source record fields `%type: descriptor-type` and `name: string`.
- Record the `types.wit` hash on the async descriptor manifest.
- Validate `DirectoryEntry = @wasi_record("filesystem/types/directory-entry", …)`
  target, field order, and Do-side types for both `@host` and `@host_func`.

## Explicit Non-Goals

This does not add a general WIT parser, dynamic record streams, source loops,
payload-bearing completion errors, arbitrary record layouts, or other
filesystem async methods. The generic G6.2 runtime remains blocked.

## Verification

- `cd src && zig test build/p3_filesystem_wit_manifest.zig`
- `cd src && zig test build/p3_async_manifest.zig`
- `cd src && zig test build/sema_imports.zig`
- `./src/build/test/run_tests.sh` → `pass=1049 fail=0 skip=3`
- `bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh`
- `bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh`
- `bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_bounded.sh`
