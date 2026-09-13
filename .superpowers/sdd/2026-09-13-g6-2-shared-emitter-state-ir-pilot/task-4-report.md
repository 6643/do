# Task 4 Evidence: Named Producer Fragments

## Scope

Task 4 adds a private fragment descriptor and bounded assembler. The changed
source files are:

- `src/build/codegen_component_producer_fragments.zig`
- `src/build/codegen_component_producer_fragments_test.zig`
- `src/main.zig` (test-root import only)

The existing default compiler dispatch and all existing producer emitters remain
unchanged.

## RED evidence

The fragment tests and test-root import were added before the implementation.
The required command was run:

```text
TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer fragment"
```

Observed failure:

```text
build/codegen_component_producer_fragments.zig:1:1: error: unable to load 'codegen_component_producer_fragments.zig': FileNotFound
build/codegen_component_producer_fragments_test.zig:2:27: note: file imported here
```

This was the expected missing-descriptor failure.

## Implementation evidence

`validate_fragment_table`:

- rejects an empty table or empty fragment name;
- rejects zero-width, reversed, or out-of-template spans;
- rejects a fragment that covers the complete template;
- requires explicit orders `0..N-1` with no duplicate or missing order;
- follows explicit order when checking contiguous `[0, template.len)` coverage;
- rejects gaps and overlaps;
- requires the first and last kinds to be `prefix` and `suffix`;
- enforces monotonic `prefix -> payload -> lifecycle -> metadata -> suffix`
  kind order;
- scans each required marker only inside its declared source span.

`assemble` validates before allocation, allocates exactly one caller-owned output
buffer, copies each declared source span in explicit order, and frees that
buffer on the only post-allocation error path. It does not parse, rewrite,
discover, or fall back to an opaque complete-template fragment.

The tests cover:

- synthetic direct-route-shaped fragment coverage and byte parity;
- parity against the embedded `owned_record_stream_producer_template.wat`;
- empty table/name, invalid and out-of-range spans;
- gap, overlap, order drift, invalid kind order, whole-template fragment;
- missing marker and fail-closed assembly.

## GREEN and hygiene evidence

After implementation and `zig fmt` on both new files, the required focused
command passed:

```text
15/15 tests passed.
```

The following command passed with no output:

```text
git diff --check
```

## Residual concerns

- Task 4 validates and assembles named spans but does not wire the private pilot
  emitter; that is reserved for Task 5.
- The fragment API maps allocator failure to the existing `FragmentError`
  surface as `InvalidSpan`, because the required interface does not expose an
  allocation error. No output slice is returned on that path.
- Full repository, release, Component, Rust, and Wasmtime gates are outside
  the Task 4 focused slice and were not run here.

## Review round 1 evidence

Two review regressions were reproduced before the fixes:

1. A `std.testing.FailingAllocator` configured with `fail_index = 0` caused
   `assemble` to return `InvalidSpan` instead of the allocator's
   `OutOfMemory` error.
2. The missing-marker test did not prove marker ownership because its marker
   did not occur anywhere in the template.

The tests were updated first and the focused filter was rerun. The first
regression failed with:

```text
expected error.OutOfMemory, found error.InvalidSpan
```

The implementation now exposes `FragmentError.OutOfMemory` and propagates the
allocator error unchanged. The marker regression now requires
`[producer-record-transfer]` from the payload fragment even though that marker
exists in the lifecycle fragment, and correctly returns `MissingMarker`.

After the implementation fix, the required focused command passed:

```text
16/16 tests passed.
```

The failing allocator test also observed zero successful allocations and zero
deallocations, proving that no output artifact is produced on allocation
failure. `zig fmt` and `git diff --check` were rerun for the fix.
