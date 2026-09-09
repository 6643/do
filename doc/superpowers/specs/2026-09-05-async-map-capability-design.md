# G6.2 Async `map<u32, u32>` Capability Probe

日期: 2026-09-05
状态: 精确 capability 已实现; 专用与全量 gate 已验证; 通用 async map lowering 仍阻断

## 1. 目标

为 WIT async map 建立一个独立、可复现的 capability probe，确认当前
`wasm-tools 1.258.0`、Wasmtime `48.0.1` 和 Rust host API 能否在异步调用中安全
接收 `map<u32, u32>`，并在 `ready`、`pending`、`cancel`、`drop` 四种终态上
观察输入复制、result area 和 exactly-once cleanup。

这是一条 Component/WIT runtime evidence，不是 Do 语言的通用 map lowering，
也不改变现有同步 `map<u32, u32>` route 的 admission。

## 2. 精确形状与 ABI

WIT 接口固定为：

```wit
package demo:map-async-probe@0.1.0;

interface api {
  submit: async func(values: map<u32, u32>) -> u32;
}
```

Core import 是本 probe 的私有 canonical 观察形状：

```text
(i32 ptr, i32 len, i32 result_area) -> i32
```

`ptr,len` 指向当前调用的 pair-list，两个 entry 在 probe 中为
`[7,70]` 和 `[9,90]`；返回的 `i32` 是异步 subtask 编码。`result_area` 指向
当前 async frame 的结果槽，host completion 将 `u32(42)` 写回该槽。这个布局只
作为 pinned probe 的 ABI 证据，不向 compiler semantic code 暴露成通用 map 规则。

## 3. 生命周期契约

异步 host import 在 callback 返回 Future 前读取并复制 `Val::Map`。Future 可以
随后挂起，但不得保存 guest 的裸 `ptr,len`，也不得依赖调用返回后的线性内存。
Core WAT 在 host call 返回后覆盖原 pair-list，专门验证 host 已经完成复制。

async frame 独立持有 waitable、subtask 和 result area。终态处理固定如下：

| 终态 | 预期 |
| --- | --- |
| `ready` | host completion 一次，future drop 一次，pending drop 为零，结果 `42` |
| `pending` | 至少一次挂起后完成一次，future drop 一次，结果 `42` |
| `cancel` | subtask cancel/drop 各一次，completion 为零，pending future drop 一次 |
| `drop` | Store/根调用 drop 触发同样的未完成 future 清理，completion 为零 |

所有终态都必须满足：

1. host 观察到完整的两个 map entry，`input-mismatches=0`；
2. frame 只释放一次，`frame-frees=1`；
3. Component `ResourceTable` 为空；
4. 取消只清理尚存的 async state，不回滚已经发生的 host 操作；
5. cleanup 顺序为 subtask、waitable、context、frame，不能重复 drop。

## 4. 证据产物与 gate

固定产物：

- `examples/p3-runtime/wit/async-map-capability.wit`
- `examples/p3-runtime/async-map-capability-canonical.wat`
- `examples/p3-runtime/rust-host-runner/src/bin/async_map_capability.rs`
- `examples/p3-runtime/test_async_map_capability.sh`
- Zig harness 的 `map_async_component` case
- toolchain adapter 的 `component-async-map` profile

专用命令：

```bash
./examples/p3-runtime/test_async_map_capability.sh
```

该命令使用 current-only adapter 完成 Core parse、Component embed/new/validate，
再用 Wasmtime Rust runner 逐一运行四种终态。当前 gate 的稳定输出为：

```text
ready   entries=[7->70, 9->90] result=42 ... future-drops=1 pending-future-drops=0 frame-frees=1 table-empty=true
pending entries=[7->70, 9->90] result=42 ... future-drops=1 pending-future-drops=0 frame-frees=1 table-empty=true
cancel  entries=[7->70, 9->90] result=0  ... future-drops=1 pending-future-drops=1 frame-frees=1 table-empty=true
drop    entries=[7->70, 9->90] result=0  ... future-drops=1 pending-future-drops=1 frame-frees=1 table-empty=true
```

本轮全量验证还通过 `./src/build/test/run_tests.sh` 与其
`RUN_WASM=1 RUN_GC_CORE=1` 组合：两者均为 `14/14 steps succeeded; 53/53 tests
passed`；`zig test main.zig` 为 `792/792`，ReleaseSmall/release smoke 通过。

## 5. Admission 边界

本 probe 不产生 Do 源码绑定，不新增 `@host_async_func` 的通用 lowering，也不把
`component-async-map` 解释为 compiler admission。以下能力仍必须另立 design、
canonical probe、负例和 lifecycle gate：

- 任意 `map<K,V>` key/value 组合；
- 通用 async map 参数复制与跨 poll owned buffer；
- map 中的 text/list/resource/variant payload；
- Stream 排队和跨 poll 的 map buffer；
- 通用 cleanup authority、arbitrary producer expression；
- 公开 `own<T>`、`borrow<T>`、`ref<T>` 或生命周期语法。

因此 G5c inventory 不新增完成行，未支持 shape 继续返回
`UnsupportedWitMarshalShape` 并在 WAT 前 fail-closed。

## 6. 后续与回滚

这条 gate 只关闭“当前工具链能否承载该精确 async map capability”的证据缺口。
若以后推进通用 async map，必须先定义 task-owned copy、poll/取消/Store disposal
的所有权边界，再实现 compiler route；不能从本 probe 的两个 `u32` entry 推断
任意 map 或 Stream 语义。

若 gate 回归失败，回滚范围仅包括本 probe 的 WIT/WAT/Rust fixture、Zig case 和
`component-async-map` profile；现有同步 map route、其他 async/resource route 和
工具链锁定不应改变。
