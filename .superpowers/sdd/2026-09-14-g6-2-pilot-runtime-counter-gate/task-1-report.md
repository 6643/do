# Task 1 Evidence Report

Status: DONE_WITH_CONCERNS

## Files changed

- `src/build/codegen_component_producer_runtime_counters.zig`
- `src/build/codegen_component_producer_runtime_counters_test.zig`
- `src/build/codegen_component_owned_record_stream_producer.zig`
- `src/main.zig`

The producer change is a private test-only seam. The default emitter and canonical
artifact path remain unchanged.

## RED

Command:

```text
cd src
TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer runtime counter"
```

Observed output before implementation:

```text
build/codegen_component_producer_runtime_counters.zig:1:1: error: unable to load 'codegen_component_producer_runtime_counters.zig': FileNotFound
build/codegen_component_producer_runtime_counters_test.zig:2:26: note: file imported here
```

## GREEN

Command:

```text
cd /home/_/._/_/do
zig fmt src/build/codegen_component_producer_runtime_counters.zig src/build/codegen_component_producer_runtime_counters_test.zig src/build/codegen_component_owned_record_stream_producer.zig
TMPDIR="$PWD/.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache" zig test src/main.zig --test-filter "producer runtime counter"
git diff --check
```

Observed output:

```text
1/4 main.test_0...OK
2/4 ...producer runtime counter instrumentation preserves canonical WAT...OK
3/4 ...producer runtime counter instrumentation rejects missing anchors...OK
4/4 ...producer runtime counter instrumentation rejects duplicate anchors...OK
All 4 tests passed.
```

`git diff --check` passed with no output. The positive test verifies the input
bytes remain unchanged, the test-only marker exists, four counter globals exist,
and the counter export/function are unique. Negative tests verify named missing
and duplicate anchor errors. The helper also requires exact equality with the
embedded direct canonical artifact and all direct route markers before writing.

## Residual concerns

- Task 1 does not assemble or validate the instrumented WAT as a Component and
  does not exercise Wasmtime runtime observations; those are Task 2 and Task 3.
- Full repository regression, ReleaseSmall build, and `run_tests.sh` were not
  run because this task is scoped to the focused instrumentation unit gate.
- The private seam is intentionally not connected to default dispatch.

## Review fix

Review requested a regression test for plausible canonical drift. Added a test that
mutates the existing `$frame-alloc` anchor in an otherwise canonical copy and
asserts `error.MissingAnchor`.

Fix verification:

```text
zig test src/main.zig --test-filter "producer runtime counter"
git diff --check
```

Expected result: 5 focused tests pass and `git diff --check` is clean.
