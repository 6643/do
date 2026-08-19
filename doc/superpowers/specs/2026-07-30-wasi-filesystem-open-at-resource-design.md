# WASI Filesystem Open-At Resource Design

## Goal

Extend the verified preopen descriptor Component probe with one pinned child
resource operation: borrow a preopen `Dir` for `descriptor.open-at`, receive an
owned `File` through `Result<File, FileError>`, borrow that File for `sync`,
then canonically drop File and Dir.

## Source Surface

Do source remains unchanged and exposes neither `own<T>` nor `borrow<T>`.
`Dir` and `File` are opaque `@wasi_resource("filesystem/types/descriptor",
{ .id i64 })` shells. The fixed probe imports preopens, `descriptor.open-at`,
`descriptor.sync`, and descriptor drop. It extracts the first preopen Dir,
opens a fixed relative path, checks `Ok(File)`, syncs the File, drops File, and
finally drops Dir.

## Ownership And ABI

The resource registry is the only ownership authority:

- preopens returns `list<tuple<own<descriptor>, string>>`;
- `descriptor.open-at` borrows its receiver and returns
  `result<own<descriptor>, error-code>`;
- `descriptor.sync` borrows its receiver;
- canonical descriptor drop consumes its resource.

The opt-in target accepts only this complete source flow. Its Core module
performs canonical result-area decoding for `open-at`, traps on an error tag,
and releases File before Dir. The WIT sidecar remains pinned to
`wasi:filesystem@0.3.0`.

## Runtime Verification

The Wasmtime host uses one `ResourceTable`. Preopens inserts Dir, open-at reads
Dir and inserts File, sync reads File, and each canonical destructor deletes
one resource. The runner asserts one preopen, one open, one sync, two drops,
and an empty table after `run`.

## Exclusions

This does not generalize lists, result unwrapping, arbitrary paths, open flags,
open/read/write APIs, error recovery, async/Future/Stream, Component-GC, or
ARC migration. Changed probe source must fail rather than receive unrelated
lowering.
