# Task 5 Report: Shared Emitter Pilot

Date: 2026-09-13
Scope: direct owned-record producer route only

## Status

Implemented the private-by-convention `emit_component_wat_pilot` adapter and
shared `emit_pilot_wat` emitter. The default `emit_component_wat` and
`emit_component_wit` paths remain unchanged, and no CLI dispatch was added.

## TDD Evidence

1. RED: before implementation, the required pilot command failed because
   `codegen_component_producer_emitter.zig` did not exist. The test module was
   then corrected for Zig 0.16's redundant top-level `comptime` diagnostic.
2. GREEN: after the emitter and adapter were added, the pilot filter passed
   13/13 tests, including the review-fix regressions.
3. Regression: the old producer filter passed 15/15 tests after importing the
   direct producer module in the test root. This makes the existing exact-source
   and negative admission tests execute under the requested filter.

## Implemented Gates

- Direct route identity is fixed to `owned-record-direct` and
  `do:g6-2-owned-record-producer@0.1.0`.
- The descriptor hash must be non-empty and equal to the contract hash.
- Source, sink, record payload, ownership, list, and runtime shape checks are
  restricted to the measured direct route.
- `RouteFrameFacts` are borrowed from the existing direct mapping entry; the
  adapter supplies the plan descriptor identity.
- The emitter constructs `FrameMapInput`, `CanonicalFrameMap`, and
  `LifecycleStateIR` in fail-closed order before fragment assembly.
- The route template is represented by five explicit prefix/payload/lifecycle/
  metadata/suffix spans with marker coverage. The pilot assembles from the
  immutable canonical template source and uses golden bytes only as the parity
  oracle.
- ARC runtime markers and GC reference type tokens are rejected before parity
  success. Temporary assembled output is freed on every rejection path.
- Pilot failures return explicit `PilotError` values and never call the old
  emitter as a fallback.

## Focused Verification

Focused test commands were run from `src/` with the repository-local Zig
caches. Formatting and repository checks were run from the repository root:

```text
TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer shared emitter pilot"
=> All 13 tests passed.

TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "owned record producer"
=> All 15 tests passed.

zig fmt --check src/build/codegen_component_producer_emitter.zig src/build/codegen_component_producer_emitter_test.zig src/build/codegen_component_owned_record_stream_producer.zig src/main.zig
=> an initial attempt from `src/` with root-prefixed paths failed with exit 1
   (`FileNotFound`); the corrected root-directory command exited 0.

git diff --check
=> exit 0
```

## Residual Boundary

The full compiler/integration harness, `wasm-tools` Component validation, and
Rust/Wasmtime lifecycle matrix were not run in this focused task. Default route
promotion is intentionally not implemented.

## Task 5 Review Fixes

The parent review identified three P1 fail-open risks. First, `PilotFacts` had
an unapproved `template_wat` field and could use `golden_wat` as its assembly
source; the field was removed and assembly is now pinned to the canonical
embedded source, so a changed golden can only produce `ByteParityMismatch`.
Second, the direct adapter previously validated only part of the plan; it now
checks the measured descriptor/WIT identity, lowering shape, record/storage,
producer/stream operations, naming facts, ownership absence sentinel, terminal
contract, and the contract reconstructed from the descriptor. Third, GC
detection previously covered only a partial token set; it now scans WAT tokens
outside strings and comments and rejects the direct regression set, including
typed refs, `i31*`, ref conversions, struct/array operations, and branch casts.

TDD evidence for the fixes: the changed-golden, GC-family, and mutated-plan
tests were observed RED before their corresponding implementation changes;
after the fixes the pilot filter passed 13/13 and the old producer filter
passed 15/15. `zig fmt` and `git diff --check` also passed. The canonical
source is fixed to the direct-route pilot boundary and remains independent of
the golden input; default dispatch and the old emitter remain unchanged.

## Task 5 Review Fix Round 2

The second review found that direct descriptor admission still allowed
non-direct optional canonical shapes (`record_list_layout` and the
parameterized producer), and that a coordinated mutation of descriptor layout,
plan layout, and contract payload could remain self-consistent. The adapter now
requires every non-direct canonical optional shape to be absent and pins the
direct record alignment to `4` independently of the mutable lowering shape.
The coordinated mutation regression returns `InvalidAdmission` before WAT
assembly.

The review also identified missing standard GC/reference tokens and a scanner
delimiter gap. The token table now covers array fill/data/element creation and
initialization plus `call_ref`/`return_call_ref`; `;` terminates ordinary
tokens while `;;` line comments and nested block comments remain ignored.
Regressions cover omitted opcodes, `ref.null;;` adjacency, ordinary text,
comment false positives, and lone-semicolon progress. The latter caught a
scanner loop that produced an empty token without advancing; the scanner now
advances over a standalone `;` after preserving the comment branches.

Round-2 TDD evidence: the new descriptor/layout and GC boundary regressions
were observed RED before implementation, including a timeout on the standalone
semicolon case, then the pilot filter passed 13/13
and the old producer filter passed 15/15. The first format command was run from
`src/` with root-relative paths and failed with `FileNotFound`; the corrected
repository-root `zig fmt` command succeeded, followed by `zig fmt --check` and
`git diff --check` passing.
