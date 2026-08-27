# C15-A implementation plan: managed-field record lift

1. Lock the exact WIT shape and measured result-area facts in the descriptor
   manifest, source/world fragments, and a parser-backed route test. The route
   must reject an unknown descriptor and a measured child-count drift.
2. Extend the synchronous GC marshal plan only for record-lift `text` children;
   keep lower and unrelated aggregate kinds fail-closed.
3. Emit a typed GC record field `(ref null $do_text)`, copy the measured UTF-8
   bytes through `$do_bytes`, free the temporary canonical span with the
   configured realloc symbol, and construct the enclosing `$do_record`.
4. Add a probe, hand-authored linear-memory ARC reference, WIT assembly, Rust
   host runner, Rust equivalence runner, and two shell gates. The host gate
   must include source-hash drift rejection and the equivalence gate must reject
   a canonical import containing a GC reference.
5. Register the probe and runners, update the residual gate and migration
   inventory evidence, and document that text/list record lower and default
   host/WIT routing remain pending.
6. Run focused Zig tests, both C15 shell gates, `cargo fmt --check`, the full
   `./src/build/test/run_tests.sh`, ReleaseSmall, `git diff --check`, inventory,
   and the baseline residual gate.
