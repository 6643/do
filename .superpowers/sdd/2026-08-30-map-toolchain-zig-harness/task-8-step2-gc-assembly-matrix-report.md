# Task 8 Step 2 GC assembly matrix batch

Date: 2026-09-04

## Scope

The Zig integration harness now owns equivalent pure assembly/validation cases
for the following GC fixtures:

- `examples/gc-p3-runtime/marshal-text-assembly.wit`
- `examples/gc-p3-runtime/marshal-record-assembly.wit`

The matrix generates the parser-backed record Core WAT with the existing Zig
probe, parses both modules, embeds them with the `none` feature profile,
creates and validates Components, and checks the extracted WIT member. It also
keeps two negative contracts: renaming the WIT member must make Component
construction fail, and injecting a GC reference into the canonical import must
be detected before assembly. No Rust host or runtime delivery is included.

## Verification

- `cd src && zig test build/test/test_harness.zig --test-filter 'GC assembly matrix covers text and parser-backed record fixtures'`: passed.
- `cd src && zig test build/test/test_harness.zig --test-filter 'integration harness case table'`: passed.
- `cd src && zig test build/test/test_cases.zig --test-filter 'integration case table'`: passed.
- `bash examples/gc-p3-runtime/test_gc_marshal_text_component.sh`: passed.
- `bash examples/gc-p3-runtime/test_gc_marshal_record_component.sh`: passed.
- The same two scripts from an unrelated `/tmp` cwd: passed.
- `cd src && zig build test --summary all`: `14/14` steps, `51/51` tests passed.
- `git diff --check`: passed.

## Remaining scope

This closes only the text and scalar-record pure assembly sub-batch. GC
marshal/host linker gates, async-frame Component shape, WASI random, C API
linker boundaries, and historical/legacy checks still require separate
classification. Task 8 Step 2 remains open until those direct-tool and pure
assembly entries have equivalent cases or documented oracle exclusions.
