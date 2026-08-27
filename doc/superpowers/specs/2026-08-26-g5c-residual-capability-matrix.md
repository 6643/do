# G5c Residual Capability Matrix

Verification Status: verified

更新时间: 2026-08-26

## 状态与范围

这是 `G5c Residual Capability Gate` 的当前只读审查结果。它不关闭任何
inventory row，也不代表 full GC cutover。审查先读取 15-row inventory、
`doc/host_abi_blockers.md`、`doc/pending_blocked.md` 和现有 descriptor
registry，再结合当前 dirty checkout 中已存在的 bounded
`mixed-text + byte/u32-list lower` slice 的独立 gate 结果作出决定。

当前基线记录为：

- pinned Zig `0.16.0`、`wasm-tools 1.255.0`、Wasmtime `47.0.2`；
- focused marshal module/operation/WAT 为 `90/90`、`43/43`、`66/66`；
- `run_tests.sh` 为 `pass=1388 fail=0 skip=3`；
- `zig test main.zig` 为 `682/682`；
- default GC gate 覆盖 `86 fixtures`；residual、semantic-equivalence、
  ReleaseSmall 和 release smoke 通过；
- `bash src/build/test/check_gc_migration_inventory.sh` 输出
  `summary complete_rows=15 pending_rows=15`，退出码为 deliberate `1`。

inventory 脚本当前是 mode `100644`，所以直接执行会得到 shell 权限错误
`126`；使用 `bash` 调用得到上面的 inventory 结果。这个调用差异不改变
迁移状态，也不作为本阶段的 compiler 功能变更。

当前已完成的 mixed-text/two-`list<u32>` lower/lift descriptor 不作为新候选。
另一个 dirty slice
`demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower`
在本轮重新通过 host、equivalence 和 negative gate，因此作为“已具备证据、
尚待专门计划收口”的唯一候选记录；这不是在矩阵前预选。

## Admission contract

候选必须同时满足：

1. 同步、manifest/WIT 驱动，并固定 source/WIT hash；
2. canonical import 不携带 Wasm GC reference；
3. layout、span guard、allocation/free 顺序可测量；
4. 复用 `LoadedRequest`、descriptor registry 和 `SyncValuePlan`；
5. 可独立通过 Component、Rust/Wasmtime、negative 和 ARC/GC equivalence
   gate；
6. 不引入新的 `own<T>`、`borrow<T>`、`ref<T>`、async、resource、Option 或
   Result 语义。

inventory row 仍表示宽能力范围；只有表中明确写出的 exact descriptor 才能
进入下一步，不能把一个 private probe 推广为整行能力。

## 15-row capability matrix

| Row | 当前已验证能力 | 拒绝边界 / 第一缺失证据 | Canonical ABI 与 cleanup 风险 | `LoadedRequest` / `SyncValuePlan` | 新契约 | 决定 |
| --- | --- | --- | --- | --- | --- | --- |
| `text` | `text` identity、rename、branch 与 ARC/GC equivalence | 一般 producer expression、通用 host text boundary 未闭合 | 通用 pointer/length layout 与 span/free 顺序尚未固定 | 否 | 否 | `blocked` |
| `[u8]` | literal、fixed-index update、single-value `@put` 已有 G5a/G5b 证据 | dynamic、spread、多值 producer 与任意 list ABI 未测 | 任意 list capacity/stride 与失败清理未固定 | 否 | 否 | `blocked` |
| `other_lists` | 已注册 scalar list 的 storage/put 覆盖 | 通用 element metadata、host marshal element kind、producer 证据缺失 | 新 element layout 与每种 cleanup 顺序未固定 | 否 | 否 | `blocked` |
| `managed_struct_list_append` | `[Box]` 单值 `@put` 有 typed-GC/ARC 证据 | spread、多值、dynamic/general producer 未闭合 | producer 生命周期和多次 allocation cleanup 未固定 | 否 | 否 | `blocked` |
| `managed_structs` | direct local/field-get 与单值同步 producer 已覆盖 | multi-return、nested producer、resource-containing struct 未闭合 | 更广 record layout 与 producer 失败路径未固定 | 否 | 否 | `blocked` |
| `nested_structs` | 一至五层 scalar managed-field path 已验证 | 第六层、更深路径及一般 nested aggregate 未闭合 | 更深 layout、重建顺序和 payload 保活未测 | 否 | 否 | `blocked` |
| `tuple_storage` | `Tuple<text,[u8]>` direct get/rewrite 已验证 | local tuple binding、nested/general tuple storage 未闭合 | tuple 子槽 canonical layout 与 cleanup 未固定 | 否 | 否 | `blocked` |
| `unions` | bounded `Unit \| Bytes([u8])` carrier、direct tag comparison 已验证 | `@is` binding、通用 payload union narrowing 未闭合 | variant payload layout、drop 和 narrowing 生命周期未固定 | 否 | 否 | `blocked` |
| `generic_calls` | resolved generic managed identity 已验证 | generic layout instantiation、field update、unresolved binding 未闭合 | 实例化后的 layout/cleanup 不能由左侧类型静默推断 | 否 | 否 | `blocked` |
| `imports` | file-backed imported managed sync identity 已验证 | unsupported module graph、imported host/WIT shape 未闭合 | 跨模块 source provenance 与 canonical import 尚未固定 | 否 | 否 | `blocked` |
| `host_wit_marshalling` | C14-C20、mixed scalar/list、text/list、two-list fixed descriptors 已通过独立 gates；本轮的 `mixed-text + byte/u32-list lower` 也通过 host/equivalence/negative | 通用 aggregate/list、任意新 shape 仍需独立 hash/layout/cleanup gate | 当前 exact candidate 为七个 scalar words，无 GC reference；三 span guard 与 reverse cleanup 已测 | 是 | 否 | `candidate`：`demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower` |
| `host_wit_marshalling_managed_record_lower` | exact `{u32,text}`、`{u32,text,text}` lower 已进入普通 route | 通用 managed-record lower、多 managed list fields 未闭合 | 任意记录字段组合的 layout/cleanup 尚无统一证据 | 是（仅 exact descriptors） | 否 | `blocked` |
| `sync_control_flow` | scalar `if/else`、guard-return、bounded defer/call-graph 已验证 | loop 与其他一般 control-flow 仍 fail-closed | 多路径 producer/cleanup join 未形成 G5c contract | 否 | 否 | `blocked` |
| `future_stream_frames` | `--p3-wait-for-component` 两个 sequential Future frame 有 backend-neutral 证据 | generic async lowering、Stream、host-future cancellation 未闭合 | async frame ownership/cancel cleanup 不属于同步 route | 否 | 是 | `blocked` |
| `resource_terminal_cleanup` | bounded async resource Result terminal/cancel 有证据 | generic resource cancellation、borrowed/owned payload 未闭合 | resource table、drop、cancel 顺序需要独立契约 | 否 | 是 | `blocked` |

## Exact candidate evidence

本轮唯一满足 admission contract 的 exact descriptor 是：

```text
demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower
```

其既有 spec/plan 为：

```text
doc/superpowers/specs/2026-08-25-g5c-mixed-text-byte-u32-lists-lower-design.md
doc/superpowers/plans/2026-08-25-g5c-mixed-text-byte-u32-lists-lower.md
```

固定 Do/WIT shape 为：

```text
Writing { code: u32, label: text, bytes: [u8], values: [u32] }
```

manifest measured root 为 28 bytes、字段偏移 `0/4/12/20`；`bytes` capacity
为 `4`、stride `1`，`values` capacity 为 `3`、stride `4`；canonical lower
import 为七个 scalar words，未跨越 GC reference。

本轮现场 gate 结果：

- host：`code=7`、`label=hello`、`bytes=[10,20,5]`、`values=[3,4]`、
  `write-calls=1`、`allocations=3`、`frees=3`；
- ARC/GC equivalence：相同 payload，`allocations=3/3`、`frees=3/3`、
  `write-calls=1/1`；
- negative：async、member、field order、element substitution、extra field、
  record-name drift 全部在 WAT 前拒绝，并保留 unrelated host 的 ARC fallback。

该 descriptor 的实现和专用 gate 已存在于当前 dirty checkout；候选 plan 的
历史步骤与当前验证状态已在
`doc/superpowers/plans/2026-08-25-g5c-mixed-text-byte-u32-lists-lower.md`
中对齐。因此它是已验证的固定形状 promotion，不是重新设计一个更宽的
generic route。

## Gate conclusion

- 15 个 inventory row 的集合为 `15/15`，每行恰好出现一次；
- G5c 状态仍为 `complete_rows=15 pending_rows=15`，没有 row 被本矩阵关闭；
- 当前没有第二个满足全部 admission 条件的 exact unclosed descriptor；
- 上面的 mixed text + byte/u32 lists lower 已完成候选专用和全局验证，下一步
  是 release-candidate maintenance 与新的单候选审查；
- 若该候选的任一 focused/default/full gate 失败，应立即停止 promotion，记录
  失败证据并保持其 out-of-route，不转而扩大其他 row；
- 不启动通用 aggregate/list、任意 producer expression、async/resource、
  ownership/borrowed、公开 `Option`/`Result` 或 full GC cutover。

## Post-closeout handoff

Task 3 的候选设计复核和 Task 4 的默认 route/文档收口均已完成。当前没有
第二个满足 admission contract 的 exact descriptor，因此不启动新的 compiler
实现；下一阶段先做 release-candidate maintenance，再重新读取 inventory 与
`doc/host_abi_blockers.md`。只有发现新的同步、manifest-backed、可测量且
canonical ABI 无 GC reference 的 exact shape，才另立 spec/plan；inventory
仍保持 deliberate exit `1`。
