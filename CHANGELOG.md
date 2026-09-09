# Changelog

# 2026-09-10 G6.2 private mixed scalar/owned record producer:
  added the exact `do:g6-2-owned-record-mixed-producer@0.1.0` compiler route
  behind `--p3-async-component`. The route admits only
  `MixedEntry { code: u32, ticket: own<Ticket> }` in a capacity-one
  `stream<mixed-entry>`; its measured record is 8 bytes/alignment 4 with
  `code`/`ticket` offsets `0/4`, source `(i32) -> (i32)`, ticket seed `111`, and
  pinned WIT SHA-256
  `5fe1c2ed6a0c348bf6f0e96596afc419bbbd379345421f02fa36f05aa472d9ed`.
  The immutable `ProducerContract` gives ownership bit `0` only to `ticket`,
  commits transfer after a complete record write, and preserves exactly-once
  cleanup before and after transfer; scalar `code` is outside the ownership
  mask and handle value `0` remains valid.
  Do/Component positive admission, nine WAT-before-rejection negatives
  (`762`-`770`), canonical ABI, generated Rust/Wasmtime lifecycle, and
  canonical/generated parity pass ten ready/pending/error/cancel/early-drop/
  repeat/invalid modes. Valid rows drop one ticket (repeat `2/2`), invalid
  creates no resources, all modes leave `table-empty=true`, and generated WAT
  contains no `__arc_`. This is private fixed-shape evidence only: it does not
  add a GC inventory row or open public `own<T>`/`borrow<T>`/`ref<T>`, generic or
  arbitrary producer, borrowed/list/variant payload, or general async/resource
  lowering.

# 2026-09-09 Private async `map<u32,u32>` compiler admission:
  added the private `--p3-async-map-component` route for exactly
  `demo:map-async-probe/api@0.1.0.submit` with `HashMap<u32,u32>`, two literal
  pairs `[7,70]` and `[9,90]`, one helper/root await topology, and the pinned
  WIT hash `821f5a1d20b600284efca10ad78f16e64d3ca5f42df566d4f045ef5b5348d3a0`.
  The strict source matcher, fixed `(i32 ptr, i32 len, i32 result_area) -> i32`
  Core template, WAT/WIT snapshots, input-copy/overwrite/result/cleanup markers,
  five WAT-before-rejection negatives, Component validation, and Rust/Wasmtime
  `ready/pending/cancel/drop` lifecycle pass. The default route still returns
  `AsyncLoweringUnavailable` without artifacts; generic async map, other
  key/value combinations, Stream cross-poll buffers, arbitrary producers, and
  public ownership syntax remain pending. The older 2026-09-05 entry below is
  retained as the runtime-only probe checkpoint.

# 2026-09-09 GC-first runtime cutover:
  completed Task 6. The installed compiler now enters the GC-only production API
  `src/build/codegen_runtime_api.zig`; ARC is no longer an implicit fallback and is
  reachable only through the explicit test-only
  `src/build/test/gc_arc_equivalence_oracle.zig` route. The post-cutover ARC scan
  reports `rows=49 matches=480 unclassified=0 normal_route_matches=0`, the
  production dependency closure reports `modules=153 forbidden=0`, the default GC
  gate covers `87 fixtures`, and the semantic-equivalence matrix reports
  `26 rows; 0 pending`. Fresh default and `RUN_WASM=1 RUN_GC_CORE=1` harness runs
  are `14/14 steps; 53/53 tests`; `zig test main.zig` is `1561/1561`, and
  ReleaseSmall/release smoke pass on `wasm-tools 1.258.0`, Wasmtime `48.0.1`,
  Zig `0.16.0`, and Rust/Cargo `1.97.1`. The migration capability inventory
  intentionally remains `complete_rows=15 pending_rows=15` with exit `1`.
  Public `own<T>`/`borrow<T>`/`ref<T>` and general async/map/producer/resource
  lowering remain separate pending work.

# 2026-09-05 Async `map<u32,u32>` capability probe:
  added a pinned WIT/Component probe for `async func(values: map<u32, u32>) -> u32`.
  The private Core observation shape is `(i32 ptr, i32 len, i32 result_area) -> i32`.
  The Rust/Wasmtime host copies the pair-list before returning a Future, while the
  canonical WAT overwrites the guest input after the call to prove that no raw
  `ptr,len` survives suspension. `ready`, `pending`, `cancel`, and `drop` all pass
  the input-copy, result-area, exactly-once frame/future cleanup, and empty-table
  checks with current-only `wasm-tools 1.258.0` and Wasmtime `48.0.1`.
  This is runtime capability evidence only: no Do compiler lowering, generic map
  shape, Stream cross-poll buffer, public ownership syntax, or GC inventory row is
  opened. Gate: `examples/p3-runtime/test_async_map_capability.sh`.

# 2026-09-04 Synchronous map operation-frame lifetime guard:
  added a focused validator to the measured map memory plan. Lowering now
  requires pair-list copy before the canonical call and release after it;
  lifting requires result-area copy, GC-value construction/root publication,
  and only then release. Five unit tests cover valid order and reject early
  release, early publication, and an async escape marker. This is an internal
  guard for the existing synchronous route; generic async map copying, Stream
  cross-poll buffers, and broader cleanup authority remain blocked.

# 2026-09-04 G6.2 general producer/resource contract consolidation:
  closed the internal immutable `ProducerContract` gate for the nine already
  admitted private producer routes: direct record, fixed pair, parameterized
  pair, triple, nested record, list-resource, dynamic-list, batched-list, and
  scalar-list. The normalized contract carries measured source/sink and payload
  layout facts, ownership paths, transfer commit, and terminal cleanup authority;
  route-specific emitters keep their existing WAT/WIT templates, hashes, and
  markers. The consolidated current-only Component/Rust/Wasmtime gate passes
  `routes=9 canonical-parity=5 lifecycle=9 table-empty=true`, and the four
  source/lease negative fixtures reject arbitrary expression, shared lease,
  borrowed async payload, and hop overflow before WAT. Verification also passes
  the default harness (`pass=1070 fail=0 skip=3`), `RUN_WASM=1`
  (`pass=1072 fail=0 skip=3`), `RUN_GC_CORE=1` (`14/14 steps; 51/51 tests`),
  `zig test main.zig` (`785/785`), ReleaseSmall, and release smoke. This does
  not open public ownership syntax, generic/arbitrary producer lowering,
  borrowed/list/variant async payloads, unmeasured shapes, or a GC inventory row;
  inventory remains `complete_rows=15 pending_rows=15` with deliberate exit `1`.

# 2026-09-03 Synchronous WIT map Component gate:
  closed the exact manifest-backed `map<u32,u32>` lower/lift route. The checked-in
  WIT worlds, source hashes, measured pair-list layout, `HashMap<u32, u32>` host
  boundary, Do fixtures, Rust/Wasmtime oracle, negative signature fixture, and
  Zig harness case all pass with current-only `wasm-tools 1.258.0` and Wasmtime
  `48.0.1`. Lower and lift each perform one host call and observe one
  allocation/free pair. This is a fixed synchronous shape only; generic map
  values, async argument copy, Stream cross-poll buffers, and broader cleanup
  authority remain blocked.

# 2026-09-02 Zig harness entrypoint closeout:
  recorded the pre-cutover Shell/Zig fixture parity report and reduced
  `src/build/test/run_tests.sh` to the current-only
  `cd src && zig build test --summary all` wrapper. Compiler, WIT map parser,
  Component, GC, CLI/tool, socket ABI, structural, and Rust lifecycle cases are
  now explicit Zig harness routes; `RUN_WASM` and `RUN_GC_CORE` are inherited by
  that harness. `check_run_tests_entrypoint.sh` locks cwd, arguments, cache
  variables, and opt-in propagation. The bounded Core map node/emitter probe now
  passes current-toolchain parse/validate for `u32` key with `u32`/`text` values;
  generic Component/WIT map runtime remains independently blocked on lowering
  and lifecycle cleanup.

# 2026-09-01 Toolchain adapter gate and Rust host migration checkpoint:
  independently re-reviewed the current-only `bin/do-toolchain` active gate.
  Direct command, path, version, subcommand, same-file alias, `rg`/`find`
  failure propagation, root/unrelated-cwd, and negative fixtures pass. The
  active lock remains `wasm-tools 1.258.0` with Wasmtime `48.0.1`; older
  `1.255.0` references remain historical evidence only. Task 8 Step 3 Rust host
  adapter batches are closed by their scoped reports. Zig harness parity and
  Shell entrypoint reduction (Steps 4/5) remain open, and generic WIT map
  runtime lowering remains independently blocked on Component/WIT pair-list
  lowering and lifecycle cleanup.

# 2026-08-30 G6.2 private nested-owned-record producer compiler admission:
  admitted exactly the hash-pinned
  `do:g6-2-owned-record-nested-producer@0.1.0` shape behind
  `--p3-async-component`. The stream element is `Outer { inner: Inner }`,
  where `Inner { ticket: own<Ticket> }`; the measured outer record is 4 bytes
  with alignment 4 and the semantic `inner.ticket` leaf is flattened to an
  `i32` at offset `0`. The capacity-one stream uses source
  `(i32) -> (i32)` with ticket seed `111`. A separate ownership mask keeps
  `guest=1` and `transferred=2`: the nested leaf is released exactly once
  before transfer, while the host releases it exactly once after an accepted
  complete record write. Handle value `0` remains valid.
  The pinned WIT hash is
  `9662440709b01044544d4c4350f3e6f783a8f06aaa5c884a96a1e43a935a7543`.
  Manifest/source matching, generated WAT/WIT, Component validation, 21
  fail-closed compiler fixtures (`725`-`745`), and canonical/generated parity
  all pass. Rust/Wasmtime covers ten ready/pending/error/cancel/early-drop/
  repeat/invalid modes: valid rows drop one ticket, stream, and future;
  cancellation/early-drop rows record one cancel and pending-future drop with
  zero future completions; `repeat` observes `[111,111]` and two cleanups;
  `invalid` allocates no resources; every mode leaves `table-empty=true`.
  The nested-route checkpoint was initially recorded at full regression
  `pass=1446 fail=0 skip=3` and `zig test main.zig` `697/697`; the current
  post-fix standard release-candidate verification is `pass=1446 fail=0 skip=3`,
  `701/701`, while the extended `RUN_WASM=1` run is `pass=1448 fail=0 skip=3`.
  ReleaseSmall, release smoke, current-only
  `wasm-tools 1.255.0`, the 114-test manifest/negative gate, and all nested
  route gates passing. This is private fixed-shape Component/compiler evidence only:
  it does not open public `own<T>`/`borrow<T>`/`ref<T>` syntax, generic nested
  or arbitrary producer lowering, general async/resource lowering, or a GC
  inventory row; inventory remains `complete_rows=15 pending_rows=15` with
  deliberate exit `1`.

# 2026-08-28 G6.2 private fixed three-owned-field record compiler admission:
  admitted exactly the hash-pinned `do:g6-2-owned-record-triple-producer@0.1.0`
  shape behind `--p3-async-component`. `ResourceTriple` remains a 12-byte,
  4-byte-aligned record with `left/middle/right: own<ticket>` at offsets
  `0/4/8`, a capacity-one stream, and producer inputs in
  `(mode,left-seed,middle-seed,right-seed)` four-`u32` order. The manifest,
  dedicated source matcher/lowering, generated WIT/WAT, Component validation,
  and 13 fail-closed compiler fixtures (712-724) are pinned to WIT hash
  `73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1`.
  Canonical and generated WAT/WIT are byte-identical; canonical/generated
  Rust/Wasmtime observations agree across all ten ready/pending/error/
  cancel/early-drop/repeat/invalid modes. Valid rows retain `3/3` ticket
  cleanup, `repeat` retains `6/6`, cancellation/early-drop retain one
  pending-future drop and cancel, invalid creates no resources, and every row
  leaves `table-empty=true`. Fresh verification passes `zig test main.zig`
  `695/695`, full regression `pass=1424 fail=0 skip=3`, ReleaseSmall, release
  smoke, and the three triple gates with `wasm-tools 1.255.0`. The route is
  private compiler evidence only: it does not add public `own<T>`/`borrow<T>`/
  `ref<T>` syntax, generic/arbitrary producer lowering, borrowed/list/variant
  payload lowering, general async/resource lowering, or a GC inventory row;
  inventory remains `complete_rows=15 pending_rows=15` with exit `1`.

# 2026-08-28 G6.2 private fixed three-owned-field record producer probe:
  added the standalone, hash-pinned canonical WIT/WAT probe for
  `do:g6-2-owned-record-triple-producer@0.1.0`. `ResourceTriple` is a
  12-byte, 4-byte-aligned record with `left/middle/right: own<ticket>` at
  offsets `0/4/8`; the capacity-one producer accepts four `u32` words in
  `(mode,left-seed,middle-seed,right-seed)` order. An independent presence mask
  transfers all three handles only after a complete record write, releases
  `right -> middle -> left` before transfer, and leaves the host to drop each
  transferred ticket exactly once; handle `0` is valid. Canonical WAT
  parse/embed/component-new/validate and the Rust/Wasmtime ten-mode lifecycle
  gate pass with `3/3` ticket cleanup per valid row, `6/6` on `repeat`, expected
  cancellation/early-drop future cleanup, and `table-empty=true` for every row.
  This is private design/probe evidence only: it is not an ARC/GC
  semantic-equivalence row and adds no manifest entry, compiler dispatch, Do
  fixture, or public `own<T>`/`borrow<T>`/`ref<T>` syntax. Compiler admission
  requires a separate approved implementation plan.

# 2026-08-28 G6.2 private parameterized two-owned-field record producer:
  added the bounded, hash-pinned
  `do:g6-2-owned-record-pair-parameterized-producer@0.1.0` Component route for
  `stream<resource-pair>` with independent `(mode, left-seed, right-seed)`
  `u32` inputs. The record remains eight bytes with
  `left: own<ticket>` at offset `0` and `right: own<ticket>` at offset `4`,
  stream capacity `1`, and WIT hash
  `e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a`.
  The independent ownership mask transfers both fields only after a complete
  record write; pre-transfer cleanup remains `right` then `left`, and host
  cleanup drops both exactly once. Canonical ABI, compiler-generated Do/
  Component, ten fail-closed negative fixtures, generated Rust/Wasmtime
  lifecycle, and canonical/generated equivalence gates pass all ten
  ready/pending/error/cancel/early-drop/repeat/invalid modes with
  `table-empty=true`; valid rows observe `2/2` ticket cleanup and `repeat`
  observes `4/4`, while `invalid` creates no resources. Fresh repository
  verification passes full regression `pass=1410 fail=0 skip=3`,
  `zig test main.zig` `692/692`, ReleaseSmall, and release smoke with
  `wasm-tools 1.255.0`. The independent Component lifecycle evidence is not
  an ARC/GC semantic-equivalence row. Generic producers, arbitrary
  expressions, borrowed/list/variant payloads, general async/resource
  lowering, public `own<T>`/`borrow<T>`/`ref<T>` syntax, and full GC cutover
  remain pending.

# 2026-08-27 G6.2 private two-owned-field record producer:
  added the bounded, hash-pinned
  `do:g6-2-owned-record-pair-producer@0.1.0` Component route for
  `stream<resource-pair>`. The record is eight bytes with
  `left: own<ticket>` at offset `0` and `right: own<ticket>` at offset `4`;
  the stream capacity is `1`, the source seeds are `111` and `222`, and an
  independent ownership mask transfers both fields atomically. Before transfer
  cleanup drops `right` then `left`; after transfer the host drops both exactly
  once. The pinned WIT hash is
  `89345a5213936735d7f065cd54ed42b83d159b80305a1a900ae00df2e811704d`.
  Canonical ABI, compiler-generated Do/Component, negative admission,
  generated Rust/Wasmtime lifecycle, and canonical/generated equivalence gates
  pass all ten ready/pending/error/cancel/early-drop/repeat/invalid modes with
  an empty `ResourceTable`; repeat observes `4/4` ticket creation/drop and
  invalid observes zero creation/drop. The independent Component lifecycle
  evidence is not an ARC/GC semantic-equivalence row. Generic producers,
  arbitrary expressions, borrowed/list/variant payloads, public
  `own<T>`/`borrow<T>`/`ref<T>` syntax, general async/resource lowering, and
  full GC cutover remain pending. The ABI runner additionally records host
  callback count, stream-consumer poll/finish count, and host-future completion,
  drop, and cancellation; Wasmtime 47.0.2 reports `finish-calls=0` for this
  task-cancel path and one pending future drop for each cancel/early-drop mode.
  Verification also passes full regression
  `pass=1400 fail=0 skip=3`, `zig test main.zig` `688/688`, default GC
  `86 fixtures`, semantic equivalence `26 rows; 0 pending`, ReleaseSmall, and
  release smoke with `wasm-tools 1.255.0`.

# 2026-08-26 G6.2 direct owned-record producer lifecycle checkpoint:
  added the private exact `do:g6-2-owned-record-producer@0.1.0` Component route
  for `stream<resource-entry>`. The pinned WIT hash is
  `6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace`; the
  record is four bytes with `ticket: own<ticket>` at offset `0`, stream capacity
  is `1`, and the source ticket seed is `111`. Canonical ABI, Do admission,
  generated Component validation, and Rust/Wasmtime lifecycle gates pass the ten
  ready/pending/error/cancel/early-drop/repeat/invalid modes with exactly-once
  ticket, stream, and future cleanup plus an empty `ResourceTable` (repeat has
  two creations and two drops). The canonical/generated comparison is recorded
  as a separate Component lifecycle equivalence gate, not as an ARC/GC semantic
  matrix row. Generic producers, arbitrary expressions, borrowed/list/variant
  payloads, broader resource lowering, public ownership syntax, and full GC
  cutover remain pending. Gates: `test_g6_2_owned_record_producer_abi.sh`,
  `test_do_g6_2_owned_record_producer.sh`,
  `test_rust_g6_2_owned_record_producer.sh`, and
  `test_g6_2_owned_record_producer_equivalence.sh`.

# 2026-08-26 G6.2 parameterized six-hop forwarding:
  the existing `StreamWriter<u8>` producer descriptor now admits exactly six
  static helper forwarding edges. The analyzer bound changed only from five to
  six; the descriptor, WIT world, `(writer, count, value)` parameters, single
  `produce` export, canonical ABI, and cleanup contract are unchanged. The
  positive Component gate, seventh-hop/arbitrary-producer negatives, and the
  Rust/Wasmtime matrix for `count=0/1/3`, `value=90`, pending/ready/error,
  early-drop, and cancel-after-transfer pass with one callback, one stream drop,
  empty `ResourceTable`, and exactly-once cleanup. General producer/resource,
  borrowed/list/variant, seventh-hop, and full GC cutover remain pending.

# 2026-08-26 G5c residual capability gate and exact candidate verification:
  the 15-row capability matrix was reviewed exactly once per row and selected
  one synchronous descriptor,
  `demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower`.
  Its source/WIT hash matches the manifest at
  `sha256:2d966dfc68f27f42ba7ce5f44c471907cf2ebe922a9af24d3cfc810847cce9c3`;
  the fixed `Writing { code: u32, label: text, bytes: [u8], values: [u32] }`
  route passes focused `90/90`, `43/43`, and `66/66` suites, Component host,
  ARC/GC equivalence (`allocations=3/3`, `frees=3/3`, `write-calls=1/1`),
  and seven pre-WAT descriptor-drift negatives. Default GC, residual,
  semantic-equivalence, full regression (`pass=1398 fail=0 skip=3`), Zig
  (`686/686`), ReleaseSmall, and release smoke also pass with the pinned
  toolchain. The inventory remains deliberately open at
  `complete_rows=15 pending_rows=15` with exit `1`; general aggregate/list,
  async/resource, ownership syntax, and full GC cutover remain pending.

# 2026-08-26 G5c verification refresh:
  reran the mixed-text/two-`list<u32>` lower and lift batch with focused marshal
  module/operation/WAT suites (`90/90`, `43/43`, `66/66`), Component host,
  ARC/GC equivalence, and descriptor-drift negative gates. Fresh repository
  evidence is `run_tests.sh` `pass=1388 fail=0 skip=3`, Zig `682/682`, default
  GC `86 fixtures`, residual/semantic-equivalence, ReleaseSmall, and release
  smoke passing with pinned `wasm-tools 1.255.0`. The migration inventory stays
  intentionally open at `complete_rows=15 pending_rows=15` with exit `1`;
  general aggregate/list, async/resource, ownership syntax, and full G5c
  cutover are unchanged.

# 2026-08-25 G5c mixed text + two `list<u32>` record lift promotion:
  the ordinary synchronous `@host_func` route now admits only the hash-pinned
  `demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift`
  descriptor for `Reading { code: u32, label: text, first: [u32], second: [u32] }`.
  The measured result area is 28 bytes (`code@0`, `label.ptr@4`, `label.len@8`,
  `first.ptr@12`, `first.len@16`, `second.ptr@20`, `second.len@24`) and the
  canonical import is one `i32` result-area pointer with no GC reference. Three
  linear spans are range-checked before copy and freed exactly once in reverse
  order: `second`, `first`, `label`. Pinned Component/Rust/Wasmtime host
  execution observes `code=7`, `label=hello`, `first=[10,20,5]`, `second=[3,4]`,
  `result=54`, `stats=51`, one callback, and `3/3` allocations/frees;
  ARC/GC equivalence observes `54/54`, `51/51`, and `1/1`. Fixtures `674`–`681`
  reject drift before WAT. The default GC gate covers 85 fixtures; full
  regression is `pass=1380 fail=0 skip=3`, Zig is `678/678`, and residual,
  ReleaseSmall, and release smoke gates pass. This is fixed-shape evidence only;
  general aggregate/list, async/resource lowering, ownership syntax, and full
  G5c cutover remain pending, with inventory `complete_rows=15 pending_rows=15`
  and exit `1`.

# 2026-08-25 G5c mixed text + two `list<u32>` record lower promotion:
  the ordinary synchronous `@host_func` route now admits only the hash-pinned
  `demo:marshal-record-mixed-text-two-u32-lists-lower/api.write@1.0.0/lower`
  descriptor for `Writing { code: u32, label: text, first: [u32], second: [u32] }`.
  The measured root is 28 bytes (`code@0`, `label.ptr@4`, `label.len@8`,
  `first.ptr@12`, `first.len@16`, `second.ptr@20`, `second.len@24`) and the
  canonical import has seven `i32` words with no GC reference. Three linear
  spans are range-checked before copy and freed exactly once in reverse order:
  `second`, `first`, `label`. Pinned Component/Rust/Wasmtime host execution
  observes `code=7`, `label=hello`, `first=[10,20,5]`, `second=[3,4]`, one
  callback, and `3/3` allocations/frees; ARC/GC equivalence observes the same
  values and cleanup. Fixtures `666`–`672` reject drift before WAT. The default
  GC gate now covers 85 fixtures; full regression is `pass=1380 fail=0 skip=3`,
  Zig is `678/678`, and residual, semantic-equivalence, ReleaseSmall, and release
  smoke gates pass. This is fixed-shape evidence only; general aggregate/list,
  async/resource lowering, ownership syntax, and full G5c cutover remain pending,
  with inventory `complete_rows=15 pending_rows=15` and exit `1`.

# 2026-08-23 G5c scalar-list route parameterization:
  the synchronous record lowerer now uses one internal
  `ManagedScalarListField` specification for both manifest `byte_list` and
  `list` inputs. The external manifest schema and canonical Component ABI are
  unchanged. Element kind selects `$do_bytes`/`array.get_s $do_bytes`/
  `i32.store8` with stride `1`, or `$do_u32`/`array.get $do_u32`/`i32.store`
  with stride `4`; measured capacity remains `u8=4` and `u32=3`. Length,
  multiplication, linear-span, allocation, canonical-call, and exactly-once
  free guards remain unchanged. This is synchronous bounded lowering only;
  arbitrary lists, list lift, async/resource lowering, ownership syntax, and
  full G5c cutover remain pending.

# 2026-08-23 G5c bounded byte-list record lift promotion:
  the hash-pinned `demo:marshal-record-byte-list-lift/api.read@1.0.0/lift`
  descriptor now admits only `Reading { code: u32, payload: [u8] }` through
  the ordinary synchronous `@host_func` route and the explicit
  `--gc-wit-marshal` route. The canonical lift receives one result-area pointer
  for the measured 12-byte record (`code@0`, `payload.ptr@4`,
  `payload.len@8`), copies the bounded byte list into `$do_bytes`, frees the
  temporary linear span exactly once, and constructs the GC record. Pinned
  `wasm-tools 1.255.0` Component host execution observes `code=7`,
  `payload=[10,20,30]`, `result=67`, one callback, and one allocation/free
  pair; ARC/GC equivalence observes `67/67`, `17/17`, and `1/1` cleanup.
  Async, locator, member, field-order, element-type, and extra-field drift
  reject before WAT. The default GC build gate now covers 75 fixtures.
  General list-record lift, async/resource lowering, ownership syntax, and full
  G5c cutover remain pending.

# 2026-08-22 G5c bounded `list<u32>` record lower promotion:
  the hash-pinned `demo:marshal-record-u32-list-lower/api.write@1.0.0/lower`
  descriptor now admits only `Writing { code: u32, payload: [u32] }` through
  the ordinary synchronous `@host_func` route and the explicit
  `--gc-wit-marshal` route. The measured 12-byte root is lowered through the
  canonical `(i32, i32, i32)` import; the GC `u32` array is copied to a
  temporary linear span and freed exactly once after the host call. Pinned
  `wasm-tools 1.255.0` host execution observes `code=7`,
  `payload=[10,20,30]`, `result=42`, one callback, and one allocation/free
  pair; ARC/GC equivalence observes `42/17` and `1/1` cleanup. Async, locator,
  member, field-order, element-type, and extra-field drift reject before WAT.
  The default GC build gate now covers 74 fixtures. General list-record lower,
  async/resource lowering, ownership syntax, and full G5c cutover remain
  pending.

# 2026-08-22 G5a generic nested managed-struct path refactor:
  the synchronous typed GC `@get/@set` route now parses and emits all admitted
  one-through-five managed-link paths through one fixed-capacity internal
  `GenericNestedFieldPath` record and loop-based chain/rebuild emitters. The
  former depth-specific records and parsers are removed without changing
  public syntax, ABI, or the five-link admission boundary; the sixth managed
  segment still rejects before WAT. Focused `codegen_gc_sync` is `245/245`,
  `gc_sync_probe` is `65/65`, one-through-five Wasmtime probes still return
  `27815`, the default GC gate remains 72 fixtures, and the equivalence matrix
  remains 26 rows. Producer expressions, deeper paths, async/resource,
  general host/WIT lowering, and G5c full cutover remain pending.

# 2026-08-22 G5a five-level nested managed-struct field path:
  the synchronous typed GC route now admits the direct-local
  `Top -> Outer -> Inner -> Middle -> Leaf -> Core` `@get/@set` path. `@set`
  rebuilds six GC structs from terminal to root while preserving unchanged
  fields and the original `[u8]` payload reference. The compiled fixture,
  standalone Wasmtime GC probe (`27815`), five-link/six-constructor WAT
  markers, and ARC/GC semantic-equivalence row pass; the default GC build gate
  now covers 72 fixtures and the equivalence matrix 26 rows. A sixth managed
  segment and producer/deeper/async/resource/general host-WIT shapes remain
  fail-closed; migration inventory remains `complete_rows=15 pending_rows=15`
  with exit 1. Focused tests are `codegen_gc_sync 245/245` and
  `gc_sync_probe 65/65` under `wasm-tools 1.255.0`.

# 2026-08-22 G5c private byte-list record lower descriptor:
  the hash-pinned `demo:marshal-record-byte-list-lower/api.write@1.0.0/lower`
  route now accepts only `Writing { code: u32, payload: [u8] }`; both the
  ordinary `@host_func` fixture and the explicit `--gc-wit-marshal` compiler
  option use the same manifest-backed plan. The measured root is 12 bytes
  (`code@0`, `payload.ptr@4`, `payload.len@8`) and the canonical import is
  `(i32, i32, i32)` with no GC reference crossing the boundary. Pinned
  `wasm-tools 1.255.0` Component host execution observes
  `code=7`, `payload=[10,20,5]`, `result=42`, one callback, and one
  allocation/free pair; the ARC/GC equivalence gate observes
  `result=42/17`, `stats=17/17`, and `allocations=1/1` and `frees=1/1`.
  Async, locator, member, field-order, element-type, and extra-field drift
  reject before WAT. The default GC build manifest now contains 70 fixtures.
  This is a fixed-shape promotion only; general
  list-record lower, async/resource lowering, ownership syntax, and full G5c
  cutover remain pending.

# 2026-08-22 G5c mixed scalar-record lower default host/WIT route promotion:
  the ordinary `@host_func` pipeline now admits the exact manifest-backed
  `demo:marshal-record-mixed-lower/api.write@1.0.0/lower` descriptor for
  `Writing { code: u32, count: u64, status: i64 }`. The measured 24-byte
  record lowers through canonical `(i32, i64, i64)` with no GC reference at the
  boundary. Default host execution and compiler-vs-ARC equivalence both report
  `result=42` and `write-calls=1/1`; async, shape, and member drift reject before
  WAT, and unadmitted host imports retain the ARC route. The default GC build
  manifest is now 69 fixtures. General aggregates, async/resource, ownership
  syntax, and full G5c cutover remain pending.

# 2026-08-22 G5c C14 default synchronous host/WIT route promotion:
  the ordinary `@host_func` pipeline now admits only the two manifest-verified
  four-level pure-scalar record descriptors for C14 lift/lower. The inline
  scalar bridge keeps canonical `(i32)` lift and
  `(i32, i64, i64, i64, i64)` lower imports, with no GC reference crossing the
  boundary. Default host/equivalence/negative gates and focused emitter tests
  pass; the private `--gc-wit-marshal` route remains available for measured
  coverage, while broader aggregate/async/resource/ownership paths and the
  migration inventory remain pending.

# 2026-08-22 G5c C14 four-level scalar-record compiler boundary:
  the explicit `--gc-wit-marshal` route now admits only the manifest-pinned
  `demo:marshal-record-nested-lift-deeper/api.read@1.0.0/lift` and
  `demo:marshal-record-nested-lower-deeper/api.write@1.0.0/lower` descriptors.
  Recursive Do/WIT record-shape, scalar-order, synchronous host declaration,
  and locator/member validation runs before WAT output. The canonical imports
  remain `(i32)` for lift and `(i32, i64, i64, i64, i64)` for lower, with no GC
  references at the boundary. Four compiler host/equivalence gates, one
  negative gate, and focused emitter tests pass; the ordinary C14 route stays
  ARC-backed and the migration inventory remains `15/15` pending.

# 2026-08-22 G5c default host/WIT route promotion:
  the ordinary `@host_func` pipeline now admits only the manifest-verified
  C15-B lower descriptor and C16-C lift descriptor. C15-B uses the canonical
  `(i32, i32, i32)` lower import and C16-C uses the `(i32)` result-area lift;
  both routes emit typed GC WAT without `__arc_` symbols and reject async or
  locator drift before WAT output. The focused marshal emitter regression
  locks compiler root `$writing` and numeric field indices. C15-D/C16-D and
  general aggregate/async/resource/ownership paths remain ARC-backed or
  pending; the migration inventory remains unchanged.

# 2026-08-21 G5c manifest-driven bounded compiler route closeout:
  the four private synchronous managed-record compiler routes now obtain
  `measured_layout` from the checked-in descriptor manifest and derive the
  source-level host boundary from the resolved WIT member plus Do tokens.
  The route remains explicit `--gc-wit-marshal` opt-in, synchronous, bounded
  to four descriptors, canonical-ABI free of GC references, and separate from
  the default ARC `@host` path. Eight compiler host/equivalence gates and four
  negative/default gates pass; `zig test main.zig` is `598/598`, the full
  regression is `pass=1279 fail=0 skip=3`, ReleaseSmall and release smoke pass,
  and the pinned toolchain is `wasm-tools 1.255.0`. The migration inventory is
  intentionally unchanged at `complete_rows=15 pending_rows=15` (exit 1).
  General aggregate, async/resource, ownership syntax, and full G5c cutover
  remain pending.

# 2026-08-21 G5c C16-D private multi-managed-field lift compiler boundary:
  promoted the measured C15-D `Reading { code: u32, label: text, note: text }`
  lift into the explicit
  `--gc-wit-marshal demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift`
  compiler route. The source validator requires one synchronous `@host_func`,
  zero parameters, and the ordered three-field record. The manifest-backed
  emitter uses the measured 20-byte result area and canonical `(func (param
  i32))` import, constructs both managed text fields, and returns `17` from
  the fixed `7 + 5 + 5` probe. Compiler host execution returns `17`, ARC/GC
  equivalence is `17/17`, and async/locator mismatch cases fail before WAT
  while default builds remain ARC-backed. Verification: focused `3/3`, full
  Zig `591/591`, `run_tests.sh` `pass=1279 fail=0 skip=3`, ReleaseSmall build,
  release smoke, `git diff --check`, and all three compiler gates pass. This
  remains private opt-in evidence; no inventory row or general
  aggregate/default host/WIT/async/resource/ownership boundary changed.

# 2026-08-21 G5c C16-C private managed-record lift compiler boundary:
  promoted the measured C15-A `Reading { code: u32, label: text }` result
  lift into the explicit
  `--gc-wit-marshal demo:marshal-record-managed-lift/api.read@1.0.0/lift`
  compiler route. The source validator requires the exact synchronous
  `@host_func`, zero parameters, `Reading` result, and ordered fields; the
  emitter uses the 12-byte result area and canonical `(func (param i32))`
  import, copies the managed text into GC values, and exports the fixed
  `run` probe. Compiler host execution returns `12`, ARC/GC equivalence is
  `12/12`, and async/locator mismatch cases fail before WAT while default
  builds remain ARC-backed. Verification: focused `3/3`, full Zig `589/589`,
  `run_tests.sh` `pass=1276 fail=0 skip=3`, ReleaseSmall build and release
  smoke pass. This remains private opt-in evidence; no inventory row or
  general aggregate/default host/WIT/async/resource/ownership boundary
  changed.

# 2026-08-21 G5c C16-B fixed-descriptor host validator expansion:
  extended the private source-level `@host_func` admission validator to both
  the C15-B `demo:marshal-record-managed-lower/api.write@1.0.0/lower`
  descriptor (`Writing { code: u32, label: text }`) and the C16-A
  multi-managed-text descriptor. The explicit `--gc-wit-marshal` route now
  selects a descriptor-specific locator/member/record-field specification;
  unknown descriptors, async markers, and locator drift remain fail-closed.
  C15-B compiler host and ARC/GC equivalence gates pass with one allocation
  and free, while the new negative/default gate confirms rejection leaves no
  WAT and ordinary `@host` remains ARC-backed. No generic type inference,
  ownership syntax, async/resource lowering, or inventory pending row changed.
  Verification: `cd src && zig test main.zig` (`587/587`),
  `./src/build/test/run_tests.sh` (`pass=1273 fail=0 skip=3`), and
  `cd src && zig build -Doptimize=ReleaseSmall` pass; the inventory command
  retains the expected 15 pending rows and exit status 1. The release smoke
  suite also passes all compiler, test, check, fmt, run, and LSP rows.

# 2026-08-21 G5c C16-A real source-level host boundary:
  added the dedicated host-first fixture
  `src/build/test/compile_ok/564_gc_wit_managed_record_host_boundary.do` and a
  private token-level adapter check for the exact
  `demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower` descriptor.
  The adapter requires one synchronous `@host_func`, exact locator/member and
  `nil` result, and the ordered `Writing { code: u32, label: text, note: text }`
  record. The canonical boundary remains five `i32` parameters over a 20-byte
  root with no GC reference crossing; compiler host/equivalence gates observe
  `code=7`, `label=hello`, `note=world`, two allocations/frees, and one callback.
  Async/mismatch cases fail before WAT, and the default route remains
  ARC-backed. General aggregate, async/resource, ownership, and G5c cutover
  remain pending.

# 2026-08-21 G5c C15-D private multi-managed-text record lower:
  added the hash-pinned `demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower`
  descriptor for `writing { code: u32, label: string, note: string }`. The
  measured layout is 20 bytes with `code@0`, `label.ptr@4`, `label.len@8`,
  `note.ptr@12`, and `note.len@16`; the canonical lower import is
  `(i32, i32, i32, i32, i32)`. The private GC route allocates and copies each
  text span, calls the host, then frees both spans in reverse order. Standalone
  and real compiler Component host/equivalence gates pass with
  `code=7`, `label=hello`, `note=world`, two allocations/frees, and one host
  callback on both GC and ARC paths. Default `@host` remains ARC-backed;
  general managed records, default host/WIT routing, async/resource lowering,
  and G5c full cutover remain pending.

# 2026-08-21 G5c C15-C explicit compiler host/WIT wiring:
  added the private `--gc-wit-marshal` opt-in for the pinned
  `demo:marshal-record-managed-lower/api.write@1.0.0/lower` descriptor. The
  real `do build` path now emits the existing C15-B canonical
  `(i32, i32, i32)` lower module only when explicitly selected; default
  `@host` remains unchanged. Compiler-output wasm-tools 1.255.0, Rust/Wasmtime
  host, and ARC/GC equivalence gates pass with one allocation/free and one host
  callback. General host/WIT routing, aggregate expansion, async/resource
  lowering, and G5c full cutover remain pending.

# 2026-08-21 G5c C15-B private manifest-backed scalar-plus-text record lower:
  added the hash-pinned `writing { code: u32, label: string }` descriptor,
  measured 12-byte layout, flat canonical `(i32, i32, i32)` import, typed GC
  text-byte copy through `cabi_realloc`, and exactly-once post-call cleanup.
  Dedicated Component host/equivalence gates observe `code=7`,
  `label=hello`, one host call, and one allocation/free pair on both GC and
  linear-memory paths. General managed-record lower, text/list record lower,
  default host/WIT routing, async/resource paths, and G5c cutover remain
  pending.

# 2026-08-20 G5c C15-A private manifest-backed scalar-plus-text record lift:
  added the hash-pinned `reading { code: u32, label: string }` descriptor,
  measured 12-byte result-area lift, typed GC `do_text` field construction,
  source-hash/shape negative checks, and dedicated Component host/equivalence
  gates. Generated GC and linear-memory Components both return `12` (`7` plus
  the five-byte label length). Text/list record lower, arbitrary managed
  aggregates, default host/WIT routing, async/resource paths, and G5c cutover
  remain pending.

# 2026-08-20 G5c C14 private manifest-backed four-level nested scalar-record lift/lower:
  added hash-pinned `leaf`/`header`/`detail`/`reading` and `writing` descriptors,
  recursive measured GC record probes, and dedicated Component host/equivalence
  gates. The measured layouts are 16/24/32/40 bytes with flattened leaf offsets
  `code@0`, `count@8`, `status@16`, `marker@24`, and `tail@32`; lower uses
  `(i32, i64, i64, i64, i64)` and lift uses `(i32)`. Generated GC and
  linear-memory Components both return `42`, with one lower callback. This is
  private measured evidence; arbitrary/deeper/general aggregates, default
  host/WIT routing, async/resource paths, and G5c cutover remain pending.

# 2026-08-20 G5c C13 private manifest-backed three-level nested scalar-record lift:
  added a hash-pinned `header`/`detail`/`reading` descriptor, recursive measured
  GC record construction, and dedicated host/equivalence gates. The pinned
  canonical result-area layout is `header=16`, `detail=24`, and `reading=32`
  bytes with leaf offsets `code@0`, `count@8`, `status@16`, and `tail@24`; the
  canonical import remains `(i32)`. Generated GC and linear-memory Components
  both return `42`, with source-hash and measured-shape rejection. This is
  private measured evidence; default host/WIT routing, deeper/general
  aggregates, async/resource paths, and G5c cutover remain pending.

# 2026-08-20 G5c C12 private manifest-backed three-level nested scalar-record lower:
  added a hash-pinned `header`/`detail`/`writing` descriptor, recursive measured
  GC record flattening, and dedicated host/equivalence gates. The measured
  layouts are 16/32/48 bytes and the canonical lower ABI is
  `(i32, i64, i64, i64)`; the generated GC and linear-memory Components both
  return `42` with one callback each. Three-level nested records remain private
  measured evidence; default host/WIT routing, deeper/general aggregates,
  async/resource paths, and G5c cutover remain pending.

# 2026-08-20 G5c C11 private manifest-backed nested scalar-record lower:
  added a hash-pinned two-level `header`/`writing` descriptor, recursive
  measured GC record flattening, and dedicated host/equivalence gates. The
  canonical lower ABI is the WIT-derived `(i32, i64, i64)` flattened import;
  the generated GC and linear-memory Components both return `42` with one
  callback each. Nested records remain private measured evidence; default
  host/WIT routing, deeper/general aggregates, async/resource paths, and G5c
  cutover remain pending.

# 2026-08-20 G5c C10 private manifest-backed nested scalar-record lift:
  added a hash-pinned two-level `header`/`reading` descriptor, recursive
  measured GC record construction, and dedicated host/equivalence gates. The
  generated GC and linear-memory Components both return `37`; the measured
  `header` is 16 bytes, the outer `reading` is 32 bytes, and the canonical
  boundary remains a single `(i32)` result-area pointer. Ordinary host/WIT
  routing, deeper/general aggregates, async/resource paths, and G5c cutover
  remain pending.

# 2026-08-20 G5c C9 private manifest-backed indirect scalar-record lower:
  added a hash-pinned 17-field `u64` `writing` descriptor, parser-backed GC
  indirect record-area probe, and dedicated host/equivalence gates. The
  generated GC and linear-memory Components both return `42` with `1/1`
  callback counts; ordinary host/WIT routing remains ARC-backed and layouts
  beyond the pinned shape remain pending.

# 2026-08-20 G5c C8 private manifest-backed mixed scalar-record lift: added a
  hash-pinned `u32/u64/s64` `reading` descriptor, parser-backed GC result-area
  probe, and dedicated host/equivalence gates. The generated GC and
  linear-memory Components both return `37` from `{7, 35, -5}`; ordinary
  host/WIT routing remains ARC-backed and broader aggregate/cutover work
  remains pending.

# 2026-08-20 G5c C7 private manifest-backed scalar-record lift: added a
  hash-pinned `reading` record descriptor, parser-backed GC result-area probe,
  and dedicated host/equivalence gates. The generated GC and linear-memory
  Components both return `42`; ordinary host/WIT routing remains ARC-backed
  and broader aggregate/cutover work remains pending.

# 2026-08-20 G5c C6 private manifest-backed scalar-record lower: added a
  hash-pinned `writing` record descriptor, parser-backed GC record probe, and
  dedicated host/equivalence gates. The generated GC and flat linear-memory
  Components both return `42` with one `write` callback; ordinary host/WIT
  routing remains ARC-backed and broader aggregate/cutover work remains
  pending.

# 2026-08-20 G5c C5 private manifest-backed `list<u32>` lift: added a
  hash-pinned lift descriptor, parser-backed GC-array result-area probe, and
  generated host/equivalence gates. The generated GC Component and the
  linear-memory ARC reference both return checksum `60`; ordinary host/WIT
  routing remains ARC-backed and arbitrary lifts/aggregates remain pending.

# 2026-08-20 G5c C4 private manifest-backed `list<u32>` lower: added a
  hash-pinned package/interface plus world descriptor, parser-backed GC-array
  probe, and route regression. The existing list<u32> ARC/GC equivalence gate
  now generates the GC module from the manifest and still observes
  `[10, 20, 30]` with exactly one allocation/free per path. Ordinary host/WIT
  routing remains ARC-backed; arbitrary aggregates, async/resource paths, and
  G5c cutover remain pending.

# 2026-08-20 GC third-level nested managed field path: admitted the bounded
  direct-local `@get/@set(outer, .inner, .middle, .leaf, ...)` synchronous shape.
  The compiler rebuilds the leaf and each parent in typed GC order while
  preserving unchanged managed payloads and scalar fields. A compiled fixture,
  pinned `wasm-tools 1.255.0`/Wasmtime GC probe, and ARC/GC equivalence row pass
  with the `27815` oracle. A fourth managed segment, arbitrary producers,
  async/resource, and host/WIT remain fail-closed; G5c full cutover is pending.

# 2026-08-11 D2 private filesystem `descriptor.set-size` promotion: admitted
  only `wasi:filesystem/types@0.3.0-rc-2025-09-16 / descriptor.set-size` with
  the pinned upstream WIT hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`
  and measured async import `(descriptor, size, result-area) -> i32` with
  `(i32,i64,i32)` Core parameters, `(i32,i32)` task-return, and
  `unit | error-code` completion. The opt-in `--p3-async-component` compiler
  gate admits fixture `552`, rejects `553`-`563` before WAT, and enforces the
  declared host binding name. The Core template hash is
  `db09b4c2fe6f1f0a8c26f582759e9937249e352b6c852c40dc88ff753ce29385`; regular/
  cancel WIT mirror hashes are
  `f09241f8fcf4b94e1a684553b439b592f254c83c7d23a3708930040a2324c3f4` /
  `7030161e35a18fe40220cb2701864141a00a6c8d897cdfc8291839f2b742cc67`.
  Generated Component assembly/validation and the Rust/Wasmtime ready,
  pending, error, cancel, Store-disposal early-drop, repeat, and generated
  ready/pending/error/repeat rows pass with exactly-once live-Store cleanup.
  Cancellation preserves a file-size mutation already issued to the host and
  does not claim rollback. Generic filesystem async, external HTTP, and public
  `own<T>`/`borrow<T>`/`ref<T>` remain outside this private method slice.

# 2026-08-11 D2 private filesystem `descriptor.stat-at` promotion: admitted
  only `wasi:filesystem/types@0.3.0-rc-2025-09-16 / descriptor.stat-at` with
  the pinned upstream WIT hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`
  and measured five-argument async import
  `(descriptor, path-flags, path-ptr, path-len, result-area) -> i32`;
  task-return is `(i32,i32,i64,i64,i32,i64,i32,i32,i64,i32,i32,i64,i32)` for
  `descriptor-stat | error-code`. The opt-in `--p3-async-component` compiler
  gate admits fixture `530`, rejects `531`-`539` before WAT, and matches Core
  template hash `4503fa7634560c66463f96ac142bcc7cfb7b90cca93a8b705c1d1eb05040ddef`.
  Regular/cancel WIT mirror hashes are
  `92afa427efedc960fd60ce2edbd3ced26521225ae8857377554956646a1059bd` /
  `420fb95fae7505e568414e55f19dc2f89f5b32e015e8d999166e38b48e4a4a49`.
  The generated Component and Rust/Wasmtime ready/pending/error/repeat plus
  hand-authored cancel/Store-disposal early-drop rows pass; the host verifies
  relative UTF-8 path copying and `symlink-follow` propagation. Generic
  filesystem async, external HTTP, and public `own<T>`/`borrow<T>`/`ref<T>`
  remain outside this private method slice.

# 2026-08-10 D2 private filesystem `descriptor.metadata-hash` promotion:
  admitted only `wasi:filesystem/types@0.3.0-rc-2025-09-16 /
  descriptor.metadata-hash` with upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f` and
  measured import `[async-lower][method]descriptor.metadata-hash`
  `(i32,i32)->i32`; task-return is `(i32,i64,i64)` and the private Result
  payload is `metadata-hash-value { lower:u64, upper:u64 } | error-code`.
  The opt-in `--p3-async-component` compiler gate admits fixture `516`,
  rejects `517`-`519` before WAT, and matches Core template hash
  `f51c82887174a7ed1adf95a1cbe0e333f80a487962a2a8478334ca9750933b6b`.
  WIT mirror hashes are
  `6976359b3a4813d6771b3ef9a7fdcfb2ee9323e70c33b9ac7d6b628519fecfed` /
  `b6e98cf2ae6f76e105f53c7ea09666b1c5684d33edb9838d034862a27b09f5c3`.
  Generated ready/pending/error/repeat and hand-authored cancel/Store-disposal
  early-drop Rust/Wasmtime oracle rows pass. General filesystem async,
  `metadata-hash-at`, and public `own<T>`/`borrow<T>`/`ref<T>` remain outside
  this private method slice.

# 2026-08-10 D2 private filesystem `descriptor.sync-data` promotion: admitted
  only `wasi:filesystem/types@0.3.0-rc-2025-09-16 / descriptor.sync-data`
  with upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f` and
  measured async import `[async-lower][method]descriptor.sync-data`
  `(i32,i32)->i32`; task-return is two `i32` words and the private Result is
  `unit | error-code`. The opt-in `--p3-async-component` compiler gate admits
  fixture `511`, rejects `512`-`515` before WAT, and matches the canonical Core
  template hash `3269e6f8c61a34dbea99f2637a257d582d79ab860f812d6ddfc46392e4fc3e7b`.
  Hand-authored and generated Components pass ready/pending/error/repeat; the
  hand-authored cancel Component passes explicit cancellation with exactly-once
  Future/descriptor cleanup and an empty `ResourceTable`. Store-disposal
  early-drop is recorded as `descriptor-drops=0` and
  `table-empty=not-applicable`, not generic host-future cancellation. General
  filesystem async, external HTTP, and public `own<T>`/`borrow<T>`/`ref<T>`
  remain outside this private method slice. Closeout gates: `zig test main.zig`
  `343/343`, default regression `pass=1195 fail=0 skip=3`, WASM regression
  `pass=1197 fail=0 skip=3` with smoke `6/6`, and ReleaseSmall smoke passed.

# 2026-08-10 wasm-tools current-only migration: made
`wasm-tools 1.255.0 (76e20611d 2026-07-30)` with SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013` the only
active Component/async toolchain. Active gates now use
`assemble_async_component.sh` and direct `component embed/new/validate`; the
removed 1.254.0 assembler and version selectors are no longer executable
paths. `--dummy-names legacy` remains only as the current async callback naming
mode. Historical 1.254.0 measurements remain dated evidence and are not
compatibility support. The current-only guard and the full gate matrix cover
the migration.

# 2026-08-09 private async host scalar-argument compiler promotion: added the
  opt-in `--p3-async-host-arg-component` target for the exact registered
  `do:async-call-arg-probe/host@0.1.0 / work` shape. The source contract has one
  `u32` helper argument, root literal `@async(helper(7))`, and a 20-byte frame
  with argument slot `+12`; the generated WIT remains pinned to hash
  `b9f5f8355e87231317ec05cccf692ee465c6f339bd509640aedc196e58f81e61`.
  Compiler fixtures `490`–`497` reject descriptor, marker, type, arity,
  topology, dynamic-root, and payload drift before WAT. Current and legacy
  Component assembly/validation pass, and the generated Rust/Wasmtime gate
  passes ready/pending/cancel with argument `7`, exactly-once Future cleanup,
  and an empty `ResourceTable`. General async-call lowering, arbitrary
  producers, payload/resource/list/stream futures, borrowed values, root
  hard-cancel, general filesystem/HTTP async, and public
  `own<T>`/`borrow<T>`/`ref<T>` remain pending.

# 2026-08-09 probe-only async host scalar-argument ABI: added the private
  `do:async-call-arg-probe@0.1.0` WIT/Core-WAT Component gate and a dedicated
  Rust/Wasmtime oracle. Both pinned `wasm-tools` 1.255.0 and legacy 1.254.0
  routes assemble and validate the measured 20-byte root frame with `u32@12`;
  ready/pending/cancel receive argument `7`, preserve exactly-once host-Future
  cleanup, and leave `ResourceTable` empty. This is ABI evidence only: no Do
  registry/sema/codegen admission, public ownership syntax, or general
  async-call lowering was added.

# 2026-08-09 G6.2 scalar-list producer promotion and async boundary closeout:
  refreshed the pinned borrow capability matrix against `wasm-tools 1.255.0`;
  synchronous `list<borrow<T>>` remains the only nested-list row with canonical
  evidence, while `future<borrow<T>>` and borrowed stream records remain
  rejected at `component embed`. Promoted the exact private
  `do:g6-2-scalar-list-producer@0.1.0 / consume-via-stream` shape for
  `stream<list<u32>>` through an isolated manifest/sema/codegen adapter and
  independent WAT/WIT template (`ptr=64`, `len=68`, stride `4`, max `3`, stream
  capacity `1`). The Do fixtures and generated Component/Rust/Wasmtime gates
  pass count `0..3`, invalid count `4`, pending/error/drop, cancellation before
  and after transfer, exactly-once list release, and an empty `ResourceTable`;
  fixtures `483`-`489` reject descriptor/topology drift before WAT. This is a
  private bounded capability only: generic list/producer lowering, arbitrary
  producer expressions, borrowed async payloads, general filesystem methods,
  external HTTP service worlds, and public `own<T>`/`borrow<T>`/`ref<T>` remain
  pending. Fresh closeout gates: Zig `319/319`, default regression
  `pass=1167 fail=0 skip=3`, WASM regression `pass=1169 fail=0 skip=3` with
  smoke `6/6`, and ReleaseSmall smoke passed.

# 2026-08-08 bounded scalar-argument async-call promotion: extended the
  private `--p3-async-call-component` root-owned local-frame adapter to exactly
  one `u32` helper argument. The admitted source is `@async(helper(7))`; the
  value is carried in frame slot `u32@12`, with no independent helper task
  return endpoint. The Do compiler gate and Rust/Wasmtime ready/pending/cancel
  matrix pass with child-before-parent cleanup and an empty `ResourceTable`;
  fixtures `467`-`469` reject helper payload, two live children, and nested
  helper drift. This remains a private bounded shape: arbitrary producer
  expressions, generic payloads, and public `own<T>`/`borrow<T>`/`ref<T>` stay
  outside scope.

# 2026-08-08 D2 private filesystem `descriptor.get-flags` promotion: admitted
  only `wasi:filesystem/types@0.3.0-rc-2025-09-16 / descriptor.get-flags` with
  upstream WIT hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`
  and WIT mirror hash
  `12afdb48b07d7160c76f04231fb8da4862350d42f6170174e6e27264b7307be9`. The
  measured async import is `[async-lower][method]descriptor.get-flags`
  `(i32,i32)->i32`; canonical result storage is `u8`, flat task-return is a
  promoted `i32`, completion is `descriptor-flags | error-code`, and the
  receiver uses `[resource-drop]descriptor (i32)->nil`. Current and legacy
  `wasm-tools` ABI gates, compiler fixtures `471`-`474`, and Rust/Wasmtime
  ready/pending/error/cancel cleanup rows pass with exactly-once drops and an
  empty `ResourceTable`. This closes one bounded method only; general
  filesystem async, arbitrary producers, borrowed payloads, and public
  ownership syntax remain outside scope. Fresh gates: `zig=308/308`, default
  regression `pass=1149 fail=0 skip=3`, WASM regression `pass=1151 fail=0 skip=3`
  with smoke `6/6`, and ReleaseSmall smoke passed.

# 2026-08-08 D2 private filesystem `descriptor.sync` promotion: admitted only
  `wasi:filesystem/types@0.3.0-rc-2025-09-16 / descriptor.sync` with upstream
  WIT hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`.
  The independently measured import is `[async-lower][method]descriptor.sync`
  `(i32,i32)->i32`, with unit/error-code component-variant completion and
  `[resource-drop]descriptor (i32)->nil`; current `wasm-tools 1.255.0` and
  legacy `1.254.0` ABI paths both pass. Mirror hashes are
  `18ce7dc9efb991cd8e5f945797aea73edeed79f0cfc51ea664cb81537e54e719` and
  `9898cd734708a2ab14760da706d69063e5cd6262a5e03d07d8eedd8074745f36` for the
  regular and test-only cancel probes. The private `--p3-async-component`
  adapter and fixtures `462`-`465` pass positive and fail-closed negative
  compiler gates. Hand-authored ready/pending/error/cancel and generated
  ready/pending/error Components pass the Rust/Wasmtime matrix with one host
  call, exactly-once future/descriptor cleanup, and `table-empty=true`.
  Cancellation does not roll back an already-issued host sync. This closes one
  additional bounded method only; other filesystem async methods, arbitrary
  producers, borrowed payloads, and public `own<T>`/`borrow<T>`/`ref<T>` remain
  outside scope. Fresh gates: `zig=304/304`, default regression
  `pass=1141 fail=0 skip=3`, WASM regression `pass=1143 fail=0 skip=3` with
  smoke `6/6`, and ReleaseSmall smoke passed.

# 2026-08-08 D2 private filesystem `descriptor.get-type` promotion: admitted
  only `wasi:filesystem/types@0.3.0-rc-2025-09-16 / descriptor.get-type` with
  WIT hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`.
  The measured async import is `[async-lower][method]descriptor.get-type`
  `(i32,i32)->i32`, completion is two `i32` task-return words, the Result
  payload is a component variant (`descriptor-type | error-code`), and the
  receiver uses `[resource-drop]descriptor`. The private
  `--p3-async-component` adapter and fixtures `459`-`461` pass positive and
  fail-closed negative compiler gates. Hand-authored and generated Components
  pass pinned `wasm-tools 1.255.0`/legacy `1.254.0` validation. The hand-authored
  Component covers ready-directory, ready-regular, pending, error, and cancel;
  the generated Component covers ready-directory, ready-regular, pending, and
  error with matching cleanup and an empty `ResourceTable`. This closes one bounded D2
  method only; general filesystem async, arbitrary async producers, borrowed
  payloads, and public `own<T>`/`borrow<T>`/`ref<T>` remain outside scope.

# 2026-08-08 G6.2 private batched list-resource producer promotion: added the
  exact `do:g6-2-batched-list-producer@0.1.0 / consume-via-stream` descriptor
  with WIT hash `a0717b2ac8525c4b1f684a4222f66939312a19c959c66b0ace5ebca16f45299f`
  and the measured two-batch layout (`[111,222]`, `[333]`, pointer/length
  `64/68` and `72/76`, stride `4`, ticket offset `0`, stream capacity `1`).
  The isolated Do adapter, generated Component gate, and Rust/Wasmtime matrix
  pass ready, pending, both sink-error, and both transfer-boundary cancellation
  modes with exactly-once resource/list cleanup and an empty `ResourceTable`.
  Fixtures `454`–`458` reject descriptor/topology/body drift before WAT. This
  remains a private fixed bounded slice; generic producer expressions/lists,
  borrowed async payloads, public `own<T>`/`borrow<T>`/`ref<T>`, root hard-cancel,
  and general filesystem/HTTP async remain outside scope.

# 2026-08-08 G6.2 private bounded dynamic list producer promotion: added the
  exact `do:g6-2-c-min-dynamic-producer@0.1.0` descriptor with WIT hash
  `95f6d2d616e80248a8710e10199fa3674aa80b76247f25c2e71d3d87ea4afe76` and
  world `dynamic-list-producer`. The compiler-generated Component and
  Rust/Wasmtime gate pass runtime counts `0/1/2/3` with ordered tickets,
  reject count `4` before allocation, and pass pending, sink-error, early-drop,
  partial source failure, and pre-/post-transfer cancellation with an empty
  `ResourceTable`. The measured list facts remain `ptr=64`, `len=68`,
  `stride=4`, ticket offset `0`, and stream capacity `1`; four negative
  fixtures remain fail-closed. This extends only the private bounded slice;
  generic producer expressions/lists, borrowed async payloads, public
  `own<T>`/`borrow<T>`/`ref<T>`, and root hard-cancel remain outside scope.

# 2026-08-08 G6.2 private C-min list/resource producer promotion: registered
  `do:g6-2-c-min-producer@0.1.0 / consume-via-stream` and promoted the exact
  `StreamWriter<[ResourceEntry]> -> Result<nil, ProducerError>` Do shape through
  the measured list layout (`ptr=64`, `len=68`, `stride=4`, ticket offset `0`,
  capacity `1`, cardinalities `0/1/3`). The generated Component/WIT and
  Rust/Wasmtime matrix passes ready, pending, sink error, early drop, invalid
  mode, and transfer-boundary cancellation with an empty `ResourceTable`; three
  negative fixtures remain fail-closed. This is a private bounded slice only:
  generic list/producer lowering, borrowed payloads, public `own<T>`/
  `borrow<T>`/`ref<T>` syntax, and root hard-cancel remain outside scope.

# 2026-08-07 private owned-future Component promotion: added the isolated
  `--p3-owned-future-component` target for the exact registered
  `Future<Ticket>` source shape. It emits a private `future<own<ticket>>` WIT
  sidecar and uses the measured `+12/+16/+20` frame protocol with a separate
  resource-presence bit. The compiler-generated Component passes pinned
  `wasm-tools 1.255.0` parsing, legacy `1.254.0` async assembly, and the
  Wasmtime ready/pending/cancel matrix with exactly-once cleanup and an empty
  `ResourceTable`. Unknown descriptors, scalar payloads, and second awaits
  reject as `UnsupportedP3OwnedFutureComponent`; public `own<T>`/`borrow<T>`/
  `ref<T>` syntax and generic owned/borrowed async lowering remain outside
  this promotion.

# 2026-08-07 bounded general async-call lowering: added the opt-in
  `--p3-async-call-component` target for one no-parameter, `nil` helper called
  through `@async(helper())` from a root function. The emitter uses a root-owned
  local helper frame/state and the root `[task-return]run` path; it does not
  export or synthesize an independent helper task. Pinned
  `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)`, Wasmtime `47.0.2`, and Rust
  `1.97.1` Component gates pass `ready`, `pending`, and `cancel` with exactly
  once child/future cleanup and an empty `ResourceTable`. Payload, multiple
  child, and nested-helper forms reject as `UnsupportedP3AsyncCallComponent`
  before WAT; parameter/resource/Stream/list/legacy forms remain outside this
  bounded slice, as do arbitrary producer expressions, filesystem async, and
  D2 host I/O.

# 2026-08-07 G6.2 StreamMirror handoff refresh: the current plan baseline is
  green with Bun-backed `./src/build/test/run_tests.sh` at `pass=1113 fail=0
  skip=3`, `RUN_WASM=1 SKIP_BUILD=1` at `pass=1115 fail=0 skip=3` with
  `pass=6 fail=0`, and ReleaseSmall smoke passed. The focused StreamMirror and
  artifact checks remain pinned to the legacy `wasm-tools 1.254.0` binary
  while capability probes use `wasm-tools 1.255.0`. This refresh keeps
  general producer lease, borrowed/list/variant fields, general async-call
  composition beyond the new bounded slice, and public
  `own<T>`/`borrow<T>`/`ref<T>` syntax outside the plan.

- 2026-08-06 Generated async scalar i64 lowering: the separate private
  `component-async-scalar-i64-v1` capability now accepts the generated
  `Future<i64>` caller with the measured `offset=16`, `byte-size=8`,
  `alignment=8`, `encoding=core-s64` payload descriptor. The generated
  Component and Rust/Wasmtime ready/pending/cancel gate passes with exact
  cleanup; generic Future payloads, text/list/resource shapes, and unrestricted
  generated WIT async lowering remain pending.

- 2026-08-06 Generated async scalar lowering: the private
  `component-async-scalar-u32-v1` capability now accepts the generated
  `Future<u32>` caller through manifest validation, a measured Component
  payload state machine, and a project-root `wit/` Rust/Wasmtime gate. Ready,
  pending, and cancel cleanup are verified; generic Future payloads, streams,
  resources, and unrestricted generated WIT async lowering remain pending.

- 2026-08-05 D2/G6.3 socket real-host gate: the compiler-generated TCP and UDP
  `create/bind/drop` Components now use the measured canonical argument order,
  result tags, IPv4 flattening, and result-area pointers. The Rust/Wasmtime
  loopback matrix passes success, forced create error, and forced bind error
  with exact resource cleanup; listen/connect/accept and general socket I/O
  remain out of scope.

- 2026-08-05 Result source policy closure: ordinary Do and standard-library
  host APIs use `T | E` (or `nil | E`) for distinct WIT result arms, with
  type-based narrowing. Duplicate ordinary union branches remain rejected.
  `Result<T, E>` and its explicit tag are retained only for registered private
  WIT/Component compatibility probes, including same-type arms; no public
  `own<T>`/`borrow<T>`/`ref<T>` syntax is introduced.

- 2026-08-04 G6.2 HTTP payload cancellation: the registered pinned
  `wasi:http/client.send` shape now accepts an explicit
  `@cancel(completion)` nil-returning root. The generated and hand-written
  service-world Components assemble and pass the Rust/Wasmtime pending and
  admitted immediate-terminal gates with exactly-once request/future/resource
  cleanup and an empty `ResourceTable`; sequential nonempty payload calls reuse
  the released private slot. Cancel-after-terminal, double cancellation of one
  Future, implicit cancellation, broader HTTP payload shapes, and public
  ownership syntax remain blocked.

- 2026-08-04 G6.2 HTTP payload-error lowering: the descriptor-registered
  `InternalError(option<string>)` and
  `DNS-error(option<string>, option<u16>)` branches now preserve exact canonical
  values through pending and ready Component/Rust/Wasmtime delivery. Error paths
  create no response resource and leave the resource table empty; `Some` to
  `None` host-lowered substitution and every unregistered payload tag remain
  explicitly blocked. The separate registered HTTP payload-cancellation gate is
  documented independently; general HTTP shapes remain outside both bounded
  gates.

- 2026-08-04 test harness: `run_tests.sh` now creates an explicitly configured
  `TMPDIR` before Node-based Component probes call `mkdtemp`. Release and full
  regression commands can therefore use a fresh worktree-local temp root
  without a manual directory pre-step.

- 2026-08-04 HTTP Component emitter placeholder hardening: the generic service
  and request-construction/send paths now expand the shared
  `[body-future-event-handler]` slot to the normal no-body waitable event
  result. The pinned HTTP service ABI probe, empty-request Rust/Wasmtime gate,
  HTTP emitter suite (`183/183`), default/WASM regressions, and ReleaseSmall
  smoke pass. This only closes template leakage; it does not add general HTTP
  body, payload-bearing error, or public ownership syntax.

- 2026-08-04 G6.2 private resource Result cancellation: the registered
  `do:resource-probe/http@0.1.0` shape now accepts an explicit
  `@cancel(completion)` nil-returning async root. The generated Component calls
  `subtask.cancel`, checks terminal status, drops the subtask exactly once, and
  returns through `[task-return]cancel`. Generated and hand-written
  Component/Rust/Wasmtime gates cover pending future drop, request consumption,
  zero response create/drop, and an empty `ResourceTable`; implicit scope-drop,
  double cancellation, and cancellation after terminal consumption remain
  rejected. No rollback protocol or public `own<T>`/`borrow<T>`/`ref<T>` syntax
  was added.

- 2026-08-04 G6.2 private resource Result error terminal: the registered
  `do:resource-probe/http@0.1.0` async resource now completes a ready
  `Err(failed)` through the same task-return, canonical-buffer, context, and
  GC-frame cleanup path as success. The Component/Rust/Wasmtime gate proves two
  requests are consumed, no response resource is created or dropped on error,
  and pending/immediate success behavior remains green. Cancellation is still
  excluded until an explicit `@cancel` source shape is designed; no public
  `own<T>`/`borrow<T>`/`ref<T>` syntax or arbitrary resource Result payloads were
  added.

- 2026-08-04 G6.2 capability-matrix closeout: the full private positive
  Component/Rust/Wasmtime matrix passed, including record consumers through
  six nested owned-resource levels, producer helpers through five forwarding
  hops, reordered/branch-terminal producers, and all six StreamMirror modes.
  The pinned negative gates still reject arbitrary producers, sixth forwarding,
  shared leases, borrowed stream fields, and seventh-level nesting. Fresh
  regressions remain `pass=1068 fail=0 skip=3`, WASM `pass=1070 fail=0 skip=3`
  with six WASM smoke cases, and `zig test main.zig` is `232/232`.

- 2026-08-03 G6.2 producer lease closeout: the private `do:stream-probe`
  producer now has verified branch-selected `close(writer)` / `abort(writer, 2)`
  terminal lowering, while typed parameter reordering resolves the actual
  `StreamWriter<u8>` formal slot. Component and Rust/Wasmtime gates cover
  pending/ready/abort or error paths with one callback and one stream drop;
  the producer-only runner has no `ResourceTable` and therefore makes no
  `table-empty=true` claim. The capability matrix retains rejection of
  arbitrary producer expressions, shared leases, borrowed stream fields,
  sixth forwarding, seventh nesting, and public `own<T>`/`borrow<T>`/`ref<T>`.

- 2026-08-03 G6.2 StreamMirror runtime closeout: the private
  descriptor-bounded source-to-writer mirror now drops its completed sink
  subtask before dropping the waitable set, preventing Wasmtime's
  `resource has children` failure. The Core/WIT lowering gate and the Rust/
  Wasmtime matrix pass pending, ready, source EOF, `Err(pipe)`, cancellation,
  and early-drop modes with exactly-once source stream/future and sink cleanup
  and an empty resource table. The change keeps ordinary async lowering
  guarded by `AsyncLoweringUnavailable` and does not add public
  `own<T>`/`borrow<T>`/`ref<T>` syntax.

- 2026-08-03 G6.2.3 path-sensitive producer-lease semantic foundation:
  `sema_stream_lease.zig` now checks `StreamWriter<T>` ownership across
  if/else joins, loop exits, lexical `defer`, same-typed transfer, helper
  transfer, writer writes, finalization, and async scope exits. Unequal join
  states report `StreamWriterLeasePathConflict`; moving a deferred writer
  reports `StreamWriterDeferredTransfer`. Fixtures 350, 405-407, and 409-410
  now lock the refined diagnostics, while 351-404 and 408 remain green. The
  change is semantic-only: no public `own<T>`/`borrow<T>`/`ref<T>` syntax,
  general async-call lowering, or arbitrary producer runtime shape was added.
  Focused Zig tests, ReleaseSmall, the full `SKIP_BUILD=1` regression
  (`pass=1065 fail=0 skip=3`), `RUN_WASM=1` (`pass=1067 fail=0 skip=3`), and
  the existing five-hop/six-level Rust/Wasmtime gates pass.

- 2026-08-03 G6.2 six-level nested owned-resource and five-hop forwarding
  checkpoints: the private `do:record-resource-stream-nested-six-level@0.1.0`
  descriptor now admits the exact `inner -> deep -> deeper -> deepest -> ultra
  -> hyper -> own<ticket>` path, and the private `do:stream-probe` producer
  admits five same-typed `(writer, count, value)` forwarding helpers. Component
  lowering plus Rust/Wasmtime pending/ready/error gates pass with two resource
  creates/drops, one stream drop, one future drop, one host callback, and empty
  resource tables. Sixth forwarding, seventh nested level, borrowed/list/variant
  fields, and resource escape remain rejected. Pinned `wasm-tools 1.254.0`
  explicitly rejects a `borrow<ticket>` stream record during Component embed.
  See `doc/superpowers/plans/2026-08-03-g6-2-bounded-next-phase.md`.

- 2026-08-03 G6.2 five-level nested owned-resource record checkpoint: the
  private `do:record-resource-stream-nested-five-level@0.1.0` descriptor now
  admits one `inner -> deep -> deeper -> deepest -> ultra -> own<ticket>` path.
  Recursive manifest/WIT/Core decode-release, Component assembly, and
  Rust/Wasmtime pending/ready/error gates pass with two resource drops, one
  stream drop, one future drop, and an empty resource table. Sixth-level,
  multi-child, mixed scalar/nested, borrow/list/variant, and resource-escape
  shapes remain rejected. See
  `doc/superpowers/specs/2026-08-03-record-stream-nested-five-level-design.md`.

- 2026-08-03 G6.2 parameterized four-hop forwarding helper producer checkpoint:
  the private `do:stream-probe` producer now admits the exact chain
  `produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> finish_stream`.
  All four forwarders transfer `(writer, count, value)` unchanged and only
  await the next same-typed helper; the final helper retains the existing
  countdown, sink call, and `defer close(writer)` behavior. Component lowering
  and Rust/Wasmtime pending/ready/`Err(pipe)` gates pass for `count=0/1/3`,
  `value=90`, one host callback, and one stream drop. A fifth forwarding edge,
  general async calls, arbitrary producer expressions, and borrowed/nested/
  variant resource fields remain rejected. See
  `doc/superpowers/specs/2026-08-03-stream-writer-parameterized-four-hop-design.md`.

- 2026-08-03 G6.2 four-level nested owned-resource record checkpoint: the
  private `do:record-resource-stream-nested-four-level@0.1.0` descriptor now
  admits one `inner -> deep -> deeper -> deepest -> own<ticket>` path. The
  recursive manifest/WIT/Core decode-release path, Component assembly, and
  Rust/Wasmtime pending/ready/error gates pass with two resource drops, one
  stream drop, one future drop, and an empty resource table. Fifth-level,
  multi-child, mixed scalar/nested, borrow/list/variant, and resource-escape
  shapes remain rejected. See
  `doc/superpowers/specs/2026-08-03-record-stream-nested-four-level-design.md`.

- 2026-08-03 G6.2 parameterized three-hop forwarding helper producer checkpoint:
  the private `do:stream-probe` producer now admits the exact chain
  `produce -> entry_stream -> forward_stream -> middle_stream -> finish_stream`.
  All three forwarders transfer `(writer, count, value)` unchanged and only
  await the next same-typed helper; the final helper retains the existing
  countdown, sink call, and `defer close(writer)` behavior. Component lowering
  and Rust/Wasmtime pending/ready/`Err(pipe)` gates pass for `count=0/1/3`,
  `value=90`, one host callback, and one stream drop. A fourth forwarding edge,
  general async calls, arbitrary producer expressions, and borrowed/nested/
  variant resource fields remain rejected.

- 2026-08-03 G6.2 three-level nested owned-resource record checkpoint: the
  private `do:record-resource-stream-nested-three-level@0.1.0` descriptor now
  admits one `inner -> deep -> deeper -> own<ticket>` path. Recursive WIT
  declaration, Core decode/release, Component validation, and Rust/Wasmtime
  pending/ready/error gates pass with two resource drops, one stream drop, one
  future drop, and an empty resource table. Fourth-level, multi-child, mixed
  scalar/nested, borrow/list/variant, and resource-escape shapes remain
  rejected.

- 2026-08-03 G6.2 reordered parameterized helper checkpoint: the private
  `do:stream-probe` producer now accepts a helper declaration in any order of
  exactly one `StreamWriter<u8>`, one `u64`, and one `u8`, with calls mapped by
  typed formal position. Sema ownership transfer, Component lowering, and
  Rust/Wasmtime pending/ready/`Err(pipe)` gates pass for count `0/1/3`, value
  `90`, one host callback, and one stream drop. Literal, duplicate, missing,
  extra, crossed, third-hop, and arbitrary producer/resource shapes remain
  rejected.

- 2026-08-03 G6.2 multiple nested owned-resource path checkpoint: the private
  `do:record-resource-stream-multiple-nested@0.1.0` descriptor now admits two
  top-level nested `own<ticket>` paths with Core slots at offsets 0 and 4.
  Recursive WIT/decode/release emission deduplicates the shared resource/drop
  declarations. Component lowering and Rust/Wasmtime pending/ready/error gates
  pass with four resource drops, one stream drop, one future drop, and an empty
  resource table. Third-level, multi-child, mixed scalar/nested, borrow/list/
  variant, and resource-escape shapes remain rejected.

- 2026-08-03 G6.2 two-level nested owned-resource record checkpoint: the private
  `do:record-resource-stream-nested-two-level@0.1.0` descriptor now admits one
  bounded `inner-entry -> deep-entry -> own<ticket>` path. Recursive WIT
  declarations, Core decode, deduplicated drop imports, and frame-owned
  exactly-once release are covered by Component lowering plus Rust/Wasmtime
  pending/ready/error gates; a fourth level, multiple paths, borrowed/list/
  variant fields, and resource escape remain rejected.

- 2026-08-03 G6.2 nested-resource manifest boundary hardening: nested child
  metadata now validates recursive shape and rejects a fourth nested level,
  multiple children, or unsupported metadata instead of silently interpreting
  deeper resource shapes as a shallower record. Existing one-level
  Component/Rust/Wasmtime gates remain unchanged.

- 2026-08-03 G6.2 parameterized two-hop forwarding helper producer checkpoint:
  the private `do:stream-probe` producer now admits the exact chain
  `produce -> forward_stream -> middle_stream -> finish_stream`. Both
  forwarders transfer `(writer, count, value)` unchanged and only await the
  next helper; the final helper retains the existing countdown, sink call, and
  `defer close(writer)` behavior. Component plus Rust/Wasmtime
  pending/ready/`Err(pipe)` gates pass for `count=0/1/3`, `value=90`, one host
  callback, and one stream drop. A third forwarding edge, reordered/literal
  arguments, general async calls, and arbitrary resource shapes remain
  rejected.

- 2026-08-03 G6.2 nested owned-resource record checkpoint: the private
  `do:record-resource-stream-nested@0.1.0` descriptor admits one nested
  `inner-entry` containing one `own<ticket>` child. Component lowering and
  Rust/Wasmtime pending/ready/error gates observe two resource drops, one
  stream drop, one future drop, and an empty resource table. Borrowed, list,
  variant, deeper nested, and arbitrary producer/resource shapes remain outside
  the gate; pinned `wasm-tools 1.254.0` rejects a stream record containing
  `borrow<T>` during Component embed.

- 2026-08-03 G6.2 parameterized forwarding helper producer checkpoint: the
  registered `do:stream-probe` producer now admits one private forwarding
  helper that transfers `(writer, count, value)` unchanged to the existing
  parameterized countdown helper. Component lowering still emits one root
  export with frame offsets 52/60. Component plus Rust/Wasmtime
  pending/ready/`Err(pipe)` gates pass for `count=0/1/3`, `value=90`, one host
  callback, and one stream drop; a third hop and general async/resource shapes
  remain rejected.
- 2026-08-03 G6.2 parameterized helper producer checkpoint: the registered
  `do:stream-probe` guest producer may transfer its capacity-one
  `StreamWriter<u8>` lease to one private helper with `(writer, count, value)`
  parameters. The helper runs the existing zero-pre-guarded countdown using
  frame offsets 52/60, closes once, and calls the registered sink. Component
  lowering plus Rust/Wasmtime pending/ready/`Err(pipe)` gates pass for
  `count=0/1/3`, `value=90`, one host callback, and one stream drop. General
  async calls, extra helper hops, and arbitrary producer/resource shapes remain
  pending.
- 2026-08-03 G6.2 parameterized dynamic producer checkpoint: the registered
  `do:stream-probe` sink now admits `async produce(count u64, value u8)`, with
  a capacity-one countdown pump, `(i64, i32)` async entry, frame value slot at
  offset 60, and per-pump byte admission. Component plus Rust/Wasmtime
  pending/ready/`Err(pipe)` gates pass for `count=0/1/3`, `value=90`, with one
  host callback and one stream drop; general producer expressions and async
  calls remain outside the boundary.
- 2026-08-03 G6.2 bounded dynamic producer checkpoint: the registered `do:stream-probe` sink now admits the explicit `(count u64)` countdown producer shape. It uses a capacity-one `StreamWriter<u8>`, writes literal `65`, stores `remaining` as `i64`, starts the sink before pumping, and supports `count=0/1/3`. Component validation plus Rust/Wasmtime pending/ready/`Err(pipe)` gates pass with one host callback and one stream drop; general loops, dynamic values, and general async calls remain outside the boundary.
- 2026-08-03 G6.2 two-hop helper producer lease checkpoint: one private async forwarding helper may now transfer an open `StreamWriter<u8>` lease to the final same-typed helper, which performs the bounded `[65, 66]` sequence, registered sink call, and `defer close(writer)`. Component lowering and Rust/Wasmtime pending/ready/`Err(pipe)` gates pass; a third hop, general async calls, dynamic producers, and borrowed/nested/variant resource fields remain rejected.
- 2026-08-03 G6.2 helper-owned producer lease checkpoint: the one same-typed async helper may now perform the bounded `[65, 66]` `StreamWriter<u8>` sequence after receiving the lease, then call the registered sink and `defer close(writer)`. The plan still emits only the producer root; Component lowering and Rust/Wasmtime pending/ready/`Err(pipe)` gates pass. General async calls, multi-level helpers, dynamic producers, arbitrary payloads, and borrowed/nested/variant resource fields remain outside the gate.
- 2026-08-03 G6.2 helper-mediated producer lease checkpoint: a bounded `StreamWriter<u8>` producer may transfer its lease once to a same-typed async helper that directly calls the registered stream-writer descriptor and finalizes with `defer close(writer)`. The descriptor-specific Component emitter keeps only the producer root export; pending/ready/`Err(pipe)` Rust/Wasmtime gates observe `[65, 66]`, one host callback, and one stream drop. General async calls, dynamic producers, arbitrary payloads, and borrowed/nested/variant resource fields remain outside the gate.

- 2026-08-02 G6.2 producer-lease terminal-error evidence: the registered custom stream-writer `Err(pipe)` runtime gate now requires one host callback and `stream-dropped=true`, making terminal reader cleanup observable instead of checking callback count alone.

- 2026-08-02 G6.2 generic stream-writer producer checkpoint: the bounded guest `StreamWriter<u8>` pump now runs through the registered `do:stream-probe@0.1.0` sink, with descriptor-selected host instance/export wiring and pending/ready/error Rust/Wasmtime evidence. Capacity-one backpressure consumes `[65, 66]` and drops the stream exactly once; producer leases, borrowed/nested/variant resource fields, broader payload-bearing completion errors, and arbitrary filesystem async methods remain outside this slice.

- 2026-08-02 G6.2 multi-owned-resource record-stream checkpoint: the private descriptor-driven consumer now accepts two `own<ticket>` fields, deduplicates the WIT resource/drop import, and releases all frame-owned handles exactly once. Component lowering plus Rust/Wasmtime pending/ready/error probes observe four resource drops and an empty `ResourceTable`; borrowed/nested resources and producer leases remain pending.

- 2026-08-02 G6.2 generic record-stream consumer: descriptor-driven lowering now accepts the registered `do:record-stream-probe@0.1.0` record stream with dynamic `@next`/`await`, scalar/string record lifting, pending/ready/error completion, and exactly-once stream/future/resource cleanup. Rust/Wasmtime evidence covers two records, EOF, one pending wake, and an empty resource table. Producer leases, borrowed/nested/variant resource fields, broader payload-bearing completion errors, and arbitrary filesystem async methods remain outside this slice.

- 2026-08-02 host ABI and P3 runtime closure: concrete and nested generic host-export structs now use one shared named field-ABI collector for WAT and manifests; pinned HTTP body/empty-request probes and byte-admission checks remain verified. Evidence: `zig test main.zig` 188/188 and `./src/build/test/run_tests.sh` pass=1049 fail=0 skip=3.

- 2026-08-02 G6.2 bounded read-directory slice: the pinned `descriptor.read-directory` now has one-to-three-entry record-stream lowering, explicit EOF probing, pending/ready Rust/Wasmtime execution, independent completion await, exactly-once stream/future/resource cleanup, and `table-empty=true`. This fixed slice does not claim payload-bearing completion errors or arbitrary filesystem async methods.

- **Host import 统一为 `@host(locator, member, sig)`**: 删除 `@env` / `@wasi_func`（零兼容）。env 写作 `@host("env", "name", sig)`；WASI 写作 `@host("wasi:package/interface@version", "member", sig)`（迁移默认 pin `0.3.0`）。内部 target 仍为 `package/interface/member`。stdlib / fixtures / `grammar.peg` / `spec_rules` §21–23 / `wasi_p3_lowering` / 诊断文案同步。

- Docs: record Wasm ref / host syntax strategy (no implementation) — `externref`→future `@host_ref`; no public `anyref`; no first-class `funcref`; i32 memory pointers never do types. See `doc/design/wasm_ref_host_syntax.md`, `pending_blocked` D10, `wasi_p3_lowering` note, `spec_rules` §21.1 pointer.

- G6.3 edge + regression hygiene: collect imported/module-local **payload enums** in codegen (`collectImportedPayloadEnumDecls`) so `@lib` wrappers may use intermediate `total IpSocketAddress = V4(addr)` before host bind; fixture `compile_ok/295`; stdlib tcp/udp bind helpers use intermediate total. `run_tests.sh` falls back to **bun** when `node` is missing; docs: `start_here` plan no longer waits on G6.3.

- **G6.3 sockets scheme B** (create/bind/drop): dual `Ipv4`/`Ipv6` address + payload enum `IpSocketAddress`; resource shells `TcpSocket`/`UdpSocket`; coarse `TcpError`/`UdpError`; stdlib `lib/tcp.do`/`lib/udp.do`/`lib/net.do`; known-table + `wasiLowering` + guest address pack; fixtures `compile_ok/291`–`294`; manifest tool marks sockets create/bind lowerable. Design: `doc/superpowers/specs/2026-07-13-g6-3-sockets-scheme-b-design.md`. Docs: G6.3 closed in `pending_blocked` / start_here / roadmap / wasi_p3_lowering / spec_rules. Non-goals remain: listen/connect, true host smoke (D2), G6.2 async.

- Branch-completeness audit (full `src/**/*.zig`, 2199 fns): check depth-split extracts keep full decision matrices (null/false/true fallthrough, error arms, multi-result LHS). Campaign extracts path-equivalent; tri-state `!?bool` call sites use `|handled| return handled`. No incomplete-branch fix required. Empirical: `zig test codegen_api.zig` 69; suite `pass=933 fail=0 skip=3`.

- Structure flatten (AGENTS): early-return + straight trunk; extract only complete nameable units. Re-inlined peel-off `advanceTupleCtorBodyDepth`. Kept nameable mid-layer units (loop-label stack events, tuple-ctor segment check, WASI error-enum arms, unmanaged struct payload, multi-result LHS). Depth is not a hard quota — do not tear last-layer blocks just to lower nest. Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite `pass=933 fail=0 skip=3`. No intentional semantic change.

- Guard-style + mid-layer extract (`src/build`): whole semantic units over peel-off micro-helpers (loop-label two passes, `emitIntrinsicCall` / `emitCoreOpArgs`, param/struct collect). Re-inlined single-call peels that split coherent logic. Aligns with early-return / nameable-boundary rule, not a nest-number quota. Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite.

- Batch B (worth-splitting one-shot): `gen_collect` → facade + `gen_collect_{util,struct,func,type}`; `sema_util` → facade + `sema_scan`; `sema_func` → facade + `sema_func_{sig,call,lambda,shared}`; `runtime_arc_wat` SSOT for ARC WAT/layout types (`runtime_prelude_wat` re-exports). Mutual peer cycles: none. Deferred: further `gen_storage`/`gen_expr`/`parser`/`imports`/`test_runner` splits (hooks coupling / high risk). Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite `pass=933 fail=0 skip=3`. Docs: `AGENTS.md`, `doc/start_here.md`.

- Gen A3: extract `codegen_generics.zig` (~56 fns: generic instantiate/bind/prebind, template match, result ABI) from `codegen_pipeline.zig` (~2.7k → ~1.1k orchestration). `codegen_pipeline` re-exports for tests/call-sites; generic uses `gen_expr.collectBodyLocals` (no import of lower). Docs: `AGENTS.md`, `doc/start_here.md`.

- Gen A2: extract `gen_expr_collect.zig` (~36 fns: `collectBodyLocals*`, loop locals, multi-result/callback collect helpers) from `gen_expr.zig` (~4.1k → ~3.2k). `gen_expr` re-exports for call-site stability; collect does not import expr. Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite.

- Gen A1: extract `gen_tuple.zig` (~28 pack helpers: tuple local get/set, leaf load/store/inc/dec, pure-scalar struct pack) from `gen_storage.zig` (~4.5k → ~3.9k). `gen_storage` re-exports for call-site stability; `TupleElementInfo` SSOT in `gen_tuple`. No mutual import with storage. Docs: `AGENTS.md`, `doc/start_here.md`.

- Guard-style flatten (codegen_pipeline/storage): generic callback prebind/bind (`prebindGenericCallbackArg` / `bindGenericCallbackArg`), start-body collect, unmanaged struct result ABI, `callArgMatchesCallbackShape` — early returns + helpers; no semantic change.

- Guard-style flatten (AGENTS nest ≤3): rewrite deep optional-if pyramids in `gen_union_emit` (`emitUnionValue` / `emitUnionBinding` / payload-enum ctor), `gen_ctrl` (`emitDiscardAssignment`), `gen_struct` (unmanaged error-union return), `gen_expr` (`collectLoopBlockLocals` / tuple get). Early returns + small helpers; no semantic change.

- Gen emit cycle break + lower thin: extend `gen_hooks` for reverse peer edges (`collectBodyLocalsWithMode`, multi-result assign, bare user-func call, union-binding move, union struct payload); `gen_ctrl` / `gen_union_emit` / `gen_struct` no longer import `gen_expr` / each other for those paths. Drop ~473 unused `codegen_pipeline` pub re-exports (~3.0k → ~2.6k). Mutual peer imports among gen emit modules: none. Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite.

- Sema domain split: extract flat modules from `sema.zig` (~9.5k → ~80-line orchestrator). New: `sema_util` (token/name/scan), `sema_types` (shared shapes), `sema_func`, `sema_struct`, `sema_type`, `sema_import`, `sema_ctrl`. Public API unchanged (`checkProgram` / `takeLastErrorSite` / `ErrorSite` via `sema.zig`). One-way deps; no peer mutual imports. Docs: `AGENTS.md`, `doc/start_here.md`, status notes.

- Gen domain split complete (Tasks 1–6): vertical extract of `gen_storage` / `gen_struct` / `gen_union_emit` / `gen_expr` / `gen_ctrl` plus `gen_hooks` late-bound callbacks; leaf domains do not import `codegen_pipeline`. `codegen_pipeline` ~19.3k → ~3.0k (orchestration + generic collect + re-exports). Verify: `zig build` Debug OK; `zig test src/build/codegen_api.zig` 69 pass; `./src/build/test/run_tests.sh` pass=933 fail=0 skip=3.

- Gen domain split (Tasks 1–4 partial): `gen_collect` (decl/layout collect); `gen_wasi_emit` (WASI host emit + `EmitExprFn`); `codegen_ownership` (release plans); `codegen_pipeline` ~16.9k→~15.0k. Storage/struct/union/expr vertical splits deferred (import cycles with `emitExpr`); leaf domains do not import `codegen_pipeline`.

- Gen Task 1: extract `gen_collect.zig` (struct/enum/func/layout collect + pack leaf helpers); `codegen_pipeline` ~19.3k → ~16.9k

- Continue gen split: `codegen_host_imports` (`@host("env", ...)` imports); `codegen_imports` (module resolve / reach / string-data); pure helpers into `gen_util`; free helpers + `ExprCallHead` into `gen_types`; rename `gen_impl` → `codegen_pipeline`

- Gen module split: `codegen_api.zig` (entry) + `gen_types.zig` (types/LocalSet) + `codegen_pipeline.zig` (emit/collect); keep `gen_util`/`gen_wasi`/`gen_union`

- Continue gen split: `gen_union.zig` (layout types/helpers); extend `gen_wasi` (call-shape / lowerability) and `gen_util` (type separators)

- Split `codegen_api.zig`: extract `gen_util.zig` (token helpers) and `gen_wasi.zig` (WASI tables/parse)

- Rename codegen modules to `gen_*` prefix: `codegen_api.zig`, `gen_payload_wat.zig`, `gen_storage_wat.zig`

- Payload enum L1: `Message = Quit | Text([u8]) | Binary([u8])` declare/construct/`@is` narrow (tags by case name)
  - sema: `isPayloadEnumDeclStart` + branch validation; codegen: tag+max-payload layout, unit/payload ctors
  - fixtures: `compile_ok/289`–`290`, `compile_err/339`; docs: `syntax/enum.md`, `grammar.peg`

- WASI C+D: stream hosts use coarse `StreamError` Err arms; docs inventory aligns preopens/stream preferred do forms
  - `lib/io.stream.do`: `[u8] | StreamError`, `u64 | StreamError`, `StreamError | nil`
  - docs: `preopens` lowerable; preferred examples use DirError/FileError/StreamError and `[Tuple<Dir,text>]`


本文只记录**最近仍需可追溯**的已完成变更。实时停点见 `doc/start_here.md`; 总规划见 `doc/master_plan.md`。  
更早条目已从仓库移除, 需要时查 git 历史。

## 2026-07-12

- 文档: WASI host 签名优先 do 联合 `Ok | Err` / `T | nil`
  - 推荐: resource/record 名 + 排他联合；禁止多返回作为 WASI result 模型；无 `wasi_result`/`wasi_option`/`@wasi_tuple`
  - 过渡: 已知 target 仍接受源码 `result<>`；manifest 仍存 WIT
  - 更新: `spec_rules` §21.1/§23、`wasi_p3_lowering` Declarative host surface、`grammar.peg` `WasiHostResult`

- 声明式 WASI 宿主绑定（stdlib 对齐）
  - 新形式: `@host(wasi locator, member, sig)` / `@wasi_resource` / `@wasi_record`（`@wasi_enum` 语法预留；粗 `DirError`/`FileError` 仍手写）
  - 已移除旧的裸 WASI host 别名；codegen 对已知 target 把 do 侧糖（`i32`/`[u8]`）规范为 WIT 签名
  - stdlib: `lib/time.do`、`dir.do`、`file.do`、`random.do`、`io.stream.do` 迁移；host 行保持 import 前缀
  - fixtures: `compile_ok/276_wasi_func_do_sig_and_resource`；私有字段收集覆盖 wasi_resource 声明
  - 文档: `grammar.peg`、`spec_rules` §21.1、`wasi_p3_lowering` declarative surface

- WASI G6.1 方案 A: `filesystem/preopens/get-directories`
  - host: `() -> list<tuple<descriptor,text>>` → do `[Tuple<i32,text>]` (`$__wasi_list_preopen_to_storage`)
  - 公开: `preopen_directories() -> [Tuple<Dir, text>]` (`lib/dir.do`); 调用方 `close_dir` 各根
  - component plan / core import / WIT (`use types.{descriptor}`) 可 lower
  - fixtures: `compile_ok/274`–`275`; 更新 `124` companion expects
  - 文档: `pending_blocked` G6.1 关闭; `wasi_p3_lowering` / start_here 同步

- codegen: **P1** 含 managed 字段的 struct 作 Tuple storage 直接子槽 (永不拍平)
  - `items [Tuple<Cell, u8>]` 且 `Cell` 含 `text` → pack 为 **4B ARC 句柄叶子** + 标量槽; 类型仍是 `Cell`, 不展开字段
  - put/get/path owning load 与 storage pack clone/free 走 `is_storage_pack` managed offset 表
  - 顺带修: multi-leaf pack 共用 `__tuple_pack_spill_i32` 导致 `text+u8` / `Cell+u8` 叶子互相覆盖 → 按叶子索引用 `_1/_2/_3` spill
  - fixtures: `compile_ok/273`, `ok/193` (`compiled_must_pass`); 删除旧 `compile_err/339`
  - 文档: `pending_blocked` P1 关闭; README / start_here / master_plan 同步

- 文档: 新增 `doc/pending_blocked.md` — 阻断 (G6)、待处理 (P2 泛型左侧反推 / skip)、延期非目标与硬约束; `start_here` / `roadmap_status` / `master_plan` / README 指向该文件

- codegen: pure-scalar 具名 struct 作为 Tuple storage **嵌套子槽** (永不拍平)
  - `items [Tuple<Point, u8>]` / `@put` / `@get` / path `@get(items, i, 0)` → `Point`
  - 局部 `Tuple` 槽用位置名 `$pair.0.x` / `$pair.0.y` / `$pair.1` (不是假字段 `v0`)
  - fixtures: `compile_ok/272`, `ok/192` (`compiled_must_pass`)

- codegen: Tuple 局部/参数槽位命名 `vN` → 位置下标 `N` (`$pair.0` 而非 `$pair.v0`)

- 规格: Tuple **永不拍平** 硬约束 — 嵌套 Tuple / struct 直接元素保持嵌套类型与 `@get` 路径; 禁止与扁平 Tuple 等同或隐式 coerce (`spec_rules` / `syntax/type` / `memory` / `start_here`)

- 文档: 删除已 drain 的 `doc/todo_non_g6.md`; 后置/可选并入 `start_here` §5–§6 与 `roadmap_status`

- codegen: 修复纯标量 struct 在 field 反射循环内 `out = @field_set(...)` 写错 local
  - 根因: 循环 collect 把已有 `struct_locals` 的 reassignment 误收成 `__field_*_` shadow; 写 `$out.n` 而 return 读 shadow
  - 修: `collectBodyLocals` 对已登记 `struct_locals` 跳过 inferred struct rebinding
  - 正例: `ok/191_json_from_json_pure_scalar` (`compiled_must_pass`)

- JSON: struct 字段 `u8` stringify/from_json 重载 (`ok/190_json_struct_u8_field`; 混合 managed 字段路径)
- LSP: hover 对当前文件类型声明/引用返回类型名 head (`src/lsp/hover.zig`)
- 非 G6 todo 清单 drain: push-on-advance 协议 + §9 阻断登记; release smoke 绿- 非 G6 日路径: `UnsupportedTupleStorageLeaf` 专用诊断 + 文档漂移收口
  - 裸 struct 等非 packable 叶子 `[Tuple]` storage 从泛化 `UnsupportedLowering` 拆出独立 code/summary/hint
  - 历史反例 `compile_err/339` 已由 P1 收回 (现 `compile_ok/273` / `ok/193`)
  - 文档: README / start_here / master_plan / roadmap_status / spec_rules / syntax/type 对齐「managed 叶子与 path chain 已落地」

- I2 后置 lowering: managed/`text` 叶子 `[Tuple]` storage + `@get(storage,i,j)` path chaining
  - scheme A 扩展: managed payload 叶子 pack 为 4 字节 handle; 合成 `is_storage_pack` layout 负责 clone/free 叶子 ARC
  - path chain: storage 元素基址保留在 `$__tuple_pack_base_tmp`, 再按直接元素索引 load
  - 正例: `compile_ok/270`–`271`, `compiled_ok/75`–`77`

- 清理旧文档与占位; 目录重命名 `lib`/`src`; 架构扁平拆分; 文档规范化

### 验证

```text
cd src && zig test main.zig
  → All 119 tests passed.
./src/build/test/run_tests.sh
  → pass=915 fail=0 skip=3
./src/build/test/run_release_smoke.sh
  → release smoke passed
```
