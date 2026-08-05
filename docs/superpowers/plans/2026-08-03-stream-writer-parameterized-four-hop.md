# Parameterized Stream-Writer Four-Hop Implementation Plan

> Bounded G6.2 follow-up. Do not widen public ownership syntax or general
> async-call lowering.

## Goal

Admit exactly four parameterized forwarding edges while preserving rejection of
the fifth edge and general producer/resource shapes.

## Tasks

- [x] Add positive parser/emitter tests for the four-hop chain and preserve
  rejection of a fifth forwarding edge.
- [x] Raise the named forwarding ceiling from three to four and reuse the
  existing final countdown metadata and frame layout.
- [x] Add the private Do fixture, WIT sidecar, Component lowering script, and
  Rust/Wasmtime pending/ready/error script.
- [x] Register the four-hop producer shape in the Rust runner and verify
  `count=0/1/3`, `value=90` in all three runtime modes.
- [x] Run the full default/WASM regression, ReleaseSmall smoke, formatting,
  shell syntax, and `git diff --check` checks.
- [x] Synchronize roadmap, blocker, async design, README, and changelog.

## Boundary

The accepted chain is:

`produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> finish_stream`

Each private forwarding helper transfers `(writer, count, value)` unchanged and
awaits one same-typed helper result. The final helper remains responsible for
the bounded countdown, sink call, and `defer close(writer)`. A fifth forwarding
edge, arbitrary async calls, producer expressions, and borrowed/list/variant or
more general resource shapes remain rejected.
