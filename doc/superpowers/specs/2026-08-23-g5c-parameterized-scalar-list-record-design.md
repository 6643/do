# G5c 参数化 Scalar-List Record Lowering 设计

## 状态

设计已批准进入实现阶段（2026-08-23）。本设计是 C19 bounded
`record { scalar, list<scalar> }` lowering 之后的内部架构收敛，不扩大
当前 GC host/WIT ABI 的公开能力。

## 目标

把当前 `list<u8>` 与 `list<u32>` record lower 的重复实现归一为一条由已验证
测量事实驱动的 scalar-list route，同时保持现有 descriptor、canonical ABI、
长度上限、同步限制和 fail-closed 行为不变。

现有两个允许的 source shape 仍然是：

```text
Writing { code u32, payload [u8]  }
Writing { code u32, payload [u32] }
```

这不是一般的 `list<T>` 推断，也不是把所有记录自动升级为 GC lowering。

## 方案与边界

### 采用的方案：内部 ScalarListSpec

manifest 的外部 schema 继续使用已有的 `list`（u32）和 `byte_list`（u8）
标记，以避免无关的 descriptor 重写。build-side conversion 在这两个输入
分支之后归一为同一组内部事实：

```text
ScalarListSpec {
    field_index
    pointer_offset
    length_offset
    element_kind: byte | u32
    element_byte_size
    element_alignment
    element_stride
    capacity
}
```

`element_kind` 决定 GC array 类型、线性 load/store 指令和对齐参数：

| kind | GC array | load | store | stride |
| --- | --- | --- | --- | ---: |
| `byte` | `$do_bytes` | `array.get_s $do_bytes` | `i32.store8` | 1 |
| `u32` | `$do_u32` | `array.get $do_u32` | `i32.store` | 4 |

`capacity`、pointer/length offset 和 allocation/free 事实来自 manifest 的
测量验证；不再在 emitter 内按元素类型硬编码 `4` 或 `3`。当前 descriptors
的实际容量仍分别为 u8=4、u32=3。

只有以下 shape 会命中该 route：

1. 同步 `@host_func` lower；
2. 根记录恰好两个字段，字段 0 为 `u32`，字段 1 为单一 scalar list；
3. 根记录是 direct record，不含 indirect area；
4. list 容器为 8 bytes、4-byte 对齐，pointer/length 为 `0/4`；
5. 元素只允许 `u8` 或 `u32`，且 measured facts 与元素 ABI 完全一致；
6. allocation/free 均为 `cabi_realloc`，长度仍受已测量 capacity 约束。

任何多字段 list、嵌套 list、record 元素、text 元素、异步/resource/borrowed
形状以及未注册 descriptor 继续在 WAT 前拒绝或走原有 ARC fallback，不能由
结构相似性隐式晋级。

## 数据流与生命周期

```mermaid
flowchart LR
    A[Manifest list 或 byte_list] --> B[Measured-node conversion]
    B --> C[ScalarListSpec]
    C --> D[MemoryPlan]
    D --> E[单一 record-list WAT emitter]
    E --> F[cabi_realloc alloc]
    F --> G[按 spec 复制到线性内存]
    G --> H[canonical host call]
    H --> I[cabi_realloc free exactly once]
```

lower 的 observable 顺序保持为：读 GC record/list -> 校验长度和线性范围 ->
分配 `element_stride * length` -> 逐元素复制 -> canonical call -> 释放临时
span。host import 只接收 Core 数值，不携带 GC reference。释放仍发生在同步
host call 返回之后；本设计不引入取消、异步 drop 或失败补偿语义。

## 组件变更

### Manifest conversion

在 `src/build/codegen_component_descriptor_manifest.zig` 抽取一个 scalar-list
conversion helper。它保留外部 kind 的严格校验，但用同一逻辑生成内部 list
child 和 element facts。不会新增 manifest schema 字段。

### Typed plan / operation plan

在 `src/build/codegen_component_marshal_plan.zig` 的 `MeasuredFacts` 中保存
scalar-list emitter 所需的 element byte size、alignment 和 capacity。

在 `src/build/codegen_component_marshal_ops.zig`：

- 用 `ManagedScalarListField` 替代 byte/u32 两个重复结构；
- 用一个 root-shape validator 派生 `element_kind` 和 `ScalarListSpec`；
- 保留同一组 alloc/copy/call/free operations；
- 删除旧的双 flag/双 field 选择状态，避免两个 route 发生漂移。

### WAT emission and module support

在 `src/build/codegen_component_marshal_wat.zig` 抽取单一
`emit_record_lower_managed_scalar_list`，仅把 element kind 映射到表中的
GC array、load、store、stride。`src/build/codegen_component_marshal_module.zig`
改为消费一个 scalar-list flag/spec，并继续按 u32 元素需要输出 `$do_u32`。

## 错误与守卫

- capacity 为 0、stride/对齐/元素大小不匹配：`UnsupportedMarshalShape`；
- `length > capacity`：生成的 WAT trap，不能绕过检查；
- `stride * length` 溢出或 linear span 越界：生成的 WAT trap；
- allocation/free 非 `cabi_realloc`：descriptor conversion 或 plan binding
  拒绝；
- route 外的输入：保持现有 rejection/ARC fallback，不吞错、不静默降级。

## 测试与门禁

先写失败测试锁定以下行为，然后再实现：

1. u8 与 u32 descriptor 的 `MemoryPlan` 都得到同一个 scalar-list route，
   但各自保留正确的 kind/stride/capacity；
2. 两种 WAT 都只有一套 emitter 生成的 alloc/copy/call/free 顺序，分别
   出现正确的 `array.get_s`/`array.get` 和 `i32.store8`/`i32.store`；
3. 非法元素、字段顺序、容量、异步和额外字段仍在 WAT 前拒绝；
4. 现有 C19 host、ARC/GC equivalence、negative、default GC、G5c residual
   gate 结果不变。

最终验证命令：

```bash
cd src && zig test build/codegen_component_marshal_ops.zig
cd src && zig test build/codegen_component_manifest_route_test.zig
./src/build/test/run_tests.sh
cd src && zig build -Doptimize=ReleaseSmall
./src/build/test/run_release_smoke.sh
git diff --check
```

## 非目标与回滚

非目标包括：运行时任意长度、任意 `list<T>`、list lift 的新能力、多个 list
字段、async/resource lowering、own/borrow/ref、改变 canonical ABI、移除 ARC
fallback。

若任一门禁失败，只回退本设计新增的内部 spec/plan/emitter 重构和对应测试，
保留 C19 已验证 descriptor 及旧 route 的行为；不得重置工作区中其他未提交
修改。
