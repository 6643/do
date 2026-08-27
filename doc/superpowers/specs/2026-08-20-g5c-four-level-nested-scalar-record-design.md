# G5c C14 四层嵌套标量 Record 设计

## 状态

- 状态: bounded private probe，非默认能力
- 日期: 2026-08-20
- 前置: C13 三层嵌套标量 record `lift/lower` 已通过 pinned manifest、Component host 与 ARC/GC equivalence gate
- 工具: `wasm-tools 1.255.0 (76e20611d 2026-07-30)`、Wasmtime `47.0.2`

## 目标与非目标

目标是验证现有递归 marshal emitter 对第四层纯标量嵌套 record 的 canonical flattening、GC record reconstruction、descriptor provenance 和 ARC/GC 等价性。

本设计不修改默认 `do build` host/WIT 路由，不开放任意深度，不引入 `own<T>`、`borrow<T>`、`ref<T>`、Option/Result 公共语法，不覆盖 async、stream、resource、text/list 字段或通用 aggregate lowering。

## 固定 WIT 形状

```wit
package demo:marshal-record-nested-lift-deeper@1.0.0;

interface api {
  record leaf {
    code: u32,
    count: u64,
  }

  record header {
    leaf: leaf,
    status: s64,
  }

  record detail {
    header: header,
    marker: s64,
  }

  record reading {
    detail: detail,
    tail: s64,
  }

  read: func() -> reading;
}
```

`lower` 使用同构的 `writing` 根类型和 `write: func(value: writing);`，单独使用 `demo:marshal-record-nested-lower-deeper@1.0.0` 包，避免 lift/lower descriptor 共享错误的 member/signature。

## 测量与 canonical ABI

WIT ABI layout 必须由当前 pinned `wit_abi_layout`/`wasm-tools` 实测并写入 descriptor/probe，而不是由源码字符串推断。预期布局为：

| record | size | alignment | nested field offset |
| --- | ---: | ---: | --- |
| `leaf` | 16 | 8 | `code@0`, `count@8` |
| `header` | 24 | 8 | `leaf@0`, `status@16` |
| `detail` | 32 | 8 | `header@0`, `marker@24` |
| `reading` | 40 | 8 | `detail@0`, `tail@32` |

Canonical result-area leaf offsets are `code@0`, `count@8`, `status@16`, `marker@24`, `tail@32`.

`lower` canonical import is expected to be `(i32, i64, i64, i64, i64) -> nil`; the `u32` leaf is represented as an `i32` word. `lift` canonical import is expected to be `(i32) -> nil`, where the sole `i32` parameter is the result-area pointer. These claims are gates, not substitutes for the current-tool measurement.

No canonical import may contain `(ref ...)`.

## Semantic fixture

Both GC and ARC paths use the leaf values `code=7`, `count=35`, `status=-5`, `marker=11`, `tail=-6`, whose checked sum is `42`. The host must observe exactly one callback per Component invocation. The lower path returns the unchanged guest result `42`; the lift path reconstructs the nested GC value and exports the checked sum.

## Provenance and fail-closed rules

Each descriptor pins source path, world source path, package, world, interface, member, direction, parameter/result type, canonical import identity, and concatenated source SHA-256. Before WAT emission, reject:

- source hash drift;
- descriptor/member/direction/signature drift;
- missing or extra nested record child;
- any measured size, alignment, offset, scalar core type, or depth mismatch;
- any non-record/non-scalar child;
- any canonical import containing a GC reference.

The descriptor remains private and is only reachable through the existing manifest route. Existing unsupported-shape behavior remains unchanged.

## Gate matrix

1. Focused Zig route tests: positive C14 lift/lower, descriptor identity, measured layout, and negative drift/depth cases.
2. Core WAT parse and Component embed/new/validate using pinned `wasm-tools`.
3. Rust/Wasmtime host gates: lift `sum=42`, lower `result=42`, one callback each, empty resource table where applicable.
4. ARC/GC equivalence gates: `42/42` and callback counts `1/1` for both directions.
5. `check_gc_g5c_residual_gate.sh` and migration inventory include all four scripts.
6. Full `run_tests.sh`, ReleaseSmall build, and `git diff --check`.

## 保留的边界

C14 只关闭这个精确四层纯标量 record 形状。任意深度、间接嵌套、text/list/variant/resource、默认 host/WIT compiler wiring、async/resource lowering 和 G5c full cutover 仍是 pending；不得从本 gate 推断通用能力。
