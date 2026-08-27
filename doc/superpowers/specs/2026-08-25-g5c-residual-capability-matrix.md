# G5c Residual Capability Matrix

更新时间: 2026-08-25

## 状态与边界

这是 `G5c Next Phase` 的只读能力审查记录，不是实现授权，也不关闭任何
migration row。当前基线已重新验证，审查基于当前 inventory、
`LoadedRequest`/`SyncValuePlan` 路由、现有 host/equivalence/negative gates，以及：

- `./src/build/test/run_tests.sh`: `pass=1380 fail=0 skip=3`；
- `(cd src && zig test main.zig)`: `678/678`；
- default GC build gate: `85 fixtures`；
- residual G5c gate: 通过；
- ReleaseSmall/release smoke: 通过；
- `bash src/build/test/check_gc_migration_inventory.sh`:
  `complete_rows=15 pending_rows=15`，exit `1`。

本轮复核使用 `bash src/build/test/check_gc_migration_inventory.sh`，因为该脚本
当前没有 executable bit；直接执行的 exit `126` 仅表示 shell 权限错误，不表示
inventory 内容失败。脚本输出的 15 个 `path` 名称与下表 15 行逐项相同，集合为
`15/15`；所有 row 的 G5c 状态仍为 `pending`。`doc/host_abi_blockers.md` 的
现有记录继续作为 ABI/cleanup 风险输入，但不替代本轮已验证的 descriptor
host/equivalence/negative 结果，也不自动扩大 admission。

此前的双 `list<u32>` lower 与本轮 mixed text + 双 `list<u32>` lower 均作为固定
descriptor 完成验证；它们不再是下一阶段的待选候选，但对应 migration row 仍按
inventory 保持 pending。

## 判定规则

候选必须同时满足：

1. 同步、manifest/WIT 驱动，并有可固定的 source/WIT hash；
2. canonical import 不携带 Wasm GC reference；
3. layout、span guard、allocation/free 顺序可以测量；
4. 能复用 `LoadedRequest`、descriptor registry 和 `SyncValuePlan`；
5. 可以独立建立 Component、Rust/Wasmtime、negative 和 ARC/GC equivalence gate；
6. 不引入新的 `own<T>`、`borrow<T>`、`ref<T>`、async、resource、Option 或 Result 语义。

## 15-row capability matrix

| Row | 当前证据 | 缺失证据 / 风险 | `LoadedRequest` / `SyncValuePlan` | 新 ownership/async/resource 契约 | 本阶段判断 |
| --- | --- | --- | --- | --- | --- |
| `text` | 同步 text identity/branch 与 G5b 等价已覆盖 | 一般 producer、host text boundary 尚未统一；pointer/length cleanup 需要新边界 | 否 | 否 | 不选；不是 manifest-backed residual slice |
| `[u8]` | 固定索引、literal、single-value `@put` 与 G5a/G5b 已覆盖 | dynamic/spread/multi-value producer 未闭合；任意 list ABI 未测 | 否 | 否 | 不选；会扩大 producer 语义 |
| `other_lists` | scalar list types 的 G5a storage/put 已覆盖 | 通用 list element metadata、host marshal element kind 未闭合 | 否 | 否 | 不选；需要扩大 manifest/list shape |
| `managed_struct_list_append` | `[Box]` 单值 `@put` 已有 GC/ARC 等价 | spread、多值、dynamic/general producer 未闭合 | 否 | 否 | 不选；producer 生命周期边界尚未固定 |
| `managed_structs` | direct local/field-get 与单值同步 producer 已覆盖 | multi-return、nested producer、resource-containing struct 未闭合 | 否 | 否 | 不选；会扩大 producer/aggregate emitter |
| `nested_structs` | 一至五层 scalar field path 已覆盖 | 更深/一般 nested aggregate 的 layout 与 cleanup 未闭合 | 否 | 否 | 不选；不是最小 host/WIT slice |
| `tuple_storage` | direct `Tuple<text,[u8]>` rewrite 有证据 | local tuple binding、nested/general tuple storage 未闭合 | 否 | 否 | 不选；需要 tuple storage admission 扩展 |
| `unions` | bounded payload carrier 与 direct tag comparison 已覆盖 | `@is` binding、general payload union 的 narrowing/lifetime 未闭合 | 否 | 否 | 不选；需要 union control-flow 契约 |
| `generic_calls` | resolved generic managed identity 已覆盖 | generic layout instantiation、field update、unresolved binding 未闭合 | 否 | 否 | 不选；需要 generic aggregate analysis |
| `imports` | file-backed imported text identity 有证据 | unsupported module graph、host/WIT imported shape 未闭合 | 否 | 否 | 不选；跨模块 provenance 尚未固定 |
| `host_wit_marshalling` | C14-C20、mixed scalar/list、text/list、two-list fixed descriptors（含 mixed text + two `list<u32>`）已通过 host/equivalence/negative gates | 一般 aggregate/list 仍未准入；每个新 shape 都需独立 hash/layout/cleanup gate | 是 | 否（同步固定 shape） | **唯一可继续评估 row** |
| `host_wit_marshalling_managed_record_lower` | `{u32,text}` 与 `{u32,text,text}` 已进入普通 route | 通用 managed-record lower、多 managed list 字段未闭合 | 是 | 否（同步固定 shape） | 可作为后续候选，但范围大于推荐 slice |
| `sync_control_flow` | scalar `if/else`、`else-if`、guard-return 与 call-graph gate 已通过 | loop/defer/general call/control flow 仍 fail-closed | 否 | 否 | 本阶段 gate 已闭合；不再重复选作 host/WIT residual |
| `future_stream_frames` | bounded `--p3-wait-for-component` Future frame 有 backend-neutral 证据 | generic async、Stream、host-future cancellation 未闭合 | 否 | **是** | 明确排除；需 async contract |
| `resource_terminal_cleanup` | bounded async resource Result terminal/cancel 有证据 | generic resource cancellation、borrowed/owned payload 未闭合 | 否 | **是** | 明确排除；需 ownership/resource contract |

## 本轮审查结论

- inventory 脚本与本表的 row name 集合均为 `15/15`，没有遗漏或新增 row。
- 15 个 row 的 G5c 状态仍全部为 pending；这是迁移账本的设计，不表示本轮
  已有 bounded descriptor 失败。
- 只有 `host_wit_marshalling` 满足本阶段的同步、manifest-backed、可测量、
  无 GC-reference canonical boundary 和可独立验证条件；其余 row 要么扩大
  producer/aggregate 语义，要么依赖 async/resource/ownership 新契约。
- 已完成的双 `list<u32>` lower 是 `host_wit_marshalling` 内部的固定证据，不
  改变 row 状态，也不重复作为下一候选。

## 上一候选的完成状态

本矩阵上一轮唯一推荐的 fixed shape 已完成并独立验证：

```wit
record writing {
  code: u32,
  label: string,
  first: list<u32>,
  second: list<u32>,
}

write: func(value: writing);
```

descriptor 为
`demo:marshal-record-mixed-text-two-u32-lists-lower/api.write@1.0.0/lower`；root
为 28 bytes，字段偏移为 `0/4/12/20`，两个 list capacity 为 `3/2`、stride 为
`4`，canonical lower import 为七个 `i32` words 且无 GC reference。三条 span
在 copy 前做 guard，cleanup 顺序为 `second -> first -> label`。Host、negative、
Component/Rust/Wasmtime、ARC/GC equivalence、default route、residual、semantic
equivalence、ReleaseSmall 和 release smoke 均通过；inventory 仍保持
`complete_rows=15 pending_rows=15`、exit `1`。

## 下一道设计门（重新评估，不预选）

上一轮唯一推荐的 fixed shape 已完成并独立验证；本矩阵不自动指定下一实现
候选，也不把已完成 descriptor 重复计为新 row。下一轮必须重新读取 inventory 与
`doc/host_abi_blockers.md`，为剩余 `host_wit_marshalling` 能力逐项比较现有证据、
缺失 ABI/layout/cleanup 证据、是否能复用 `LoadedRequest`/`SyncValuePlan`，以及
是否引入新的 aggregate/list、async/resource 或 ownership 契约。只有满足同步、
manifest-backed、可测量、canonical ABI 无 GC reference 且可独立建立
Component/Rust/Wasmtime、negative、ARC/GC equivalence gate 的候选，才可另立
spec/plan；在候选获批前不改默认 route。

## 本轮设计门结果（2026-08-25）

本轮唯一 bounded candidate 已完成并独立验证：同步
`Reading { code: u32, label: text, first: [u32], second: [u32] }` lift。
descriptor 为
`demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift`；
result area 为 28 bytes，canonical ABI 为单个 `(i32)` result-area pointer，
三条 span 的 cleanup 顺序为 `second -> first -> label`。Host 结果为
`54/51/1`，allocation/free 为 `3/3`；ARC/GC equivalence 为
`54/54`、`51/51`、`1/1`，负例 `674–681` 均在 WAT 前拒绝，default route
与 residual gate 均通过。该 descriptor 与对应 lower 一样仍不改变
`host_wit_marshalling` migration row 的 pending 状态。

## 下一道设计门（2026-08-25）

下一轮不预选候选。必须重新读取 inventory 与 `doc/host_abi_blockers.md`，为
剩余 `host_wit_marshalling` 能力逐项比较现有证据、缺失 ABI/layout/cleanup
证据、是否能复用 `LoadedRequest`/`SyncValuePlan`，以及是否引入新的
aggregate/list、async/resource 或 ownership 契约。只有满足同步、manifest-backed、
可测量、canonical ABI 无 GC reference 且可独立建立 Component/Rust/Wasmtime、
negative、ARC/GC equivalence gate 的候选，才可另立 spec/plan；在候选获批前不改
默认 route。

## 非推荐方案与弃权理由

- **固定 scalar `i16` record**：实现风险更低，但只增加无 managed span 的标量
  admission，不能验证本阶段最关键的多 span cleanup；保留为 fallback probe，不作为主 slice。
- **已完成的双 `list<u32>` lower**：该精确 descriptor 已有 Component、host、
  equivalence、negative 和 default-route 证据，不能重复作为新的 residual slice。
- **扩大任意 list/producer/aggregate**：会把固定 descriptor 变成通用 shape，缺少
  element metadata、容量和 producer lifetime 契约，拒绝。
- **async/resource/borrowed payload**：现有 pinned toolchain 与 Component gate
  已证明需要独立 ownership/async/resource 设计，拒绝在 G5c 同步 route 中混入。
- **Option/Result/Variant 或公开 `own/borrow/ref`**：属于语言/ABI 语义变化，不是
  本阶段的 bounded GC migration slice，拒绝。
