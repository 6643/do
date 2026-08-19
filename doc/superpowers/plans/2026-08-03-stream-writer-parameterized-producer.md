# Parameterized Dynamic Producer Implementation Plan

- [x] Add red plan/WIT/WAT tests for `(count u64, value u8)` and preserve the
  literal countdown rejection boundary.
- [x] Extend the descriptor-specific plan with a strict `u8` value parameter
  and reject literal or unsupported value expressions in this two-parameter
  shape.
- [x] Add the `(i64, i32)` async entry type, frame value slot at offset 60, and
  per-pump byte-store lowering.
- [x] Add Component and Rust/Wasmtime pending/ready/error fixtures for
  `count=0/1/3`, `value=90`, exactly-once callback, and exactly-once drop.
- [x] Run the full regression, `RUN_WASM=1`, ReleaseSmall smoke, formatting,
  and shell/diff checks; update the roadmap only after those gates pass.
