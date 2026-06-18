# do 语言规范入口 (spec v1)

本文是 `do` 语言规范入口, 不承载完整细则。完整规则、PEG、示例和运行时模型按职责拆到相邻扁平文档, 避免 `spec.md` 继续堆叠成单个不可读大文件。

## 0. 文档分工

1. `doc/spec.md`: 规范入口、阅读路径、核心边界和维护规则。
2. `doc/spec_rules.md`: 语义规则、静态约束、运行时边界、诊断和测试约定。
3. `doc/grammar.peg`: parser 可执行 PEG, 包括词法 token 形态和主文法。
4. `doc/spec_examples.md`: 正例、反例、推荐写法和回归提取素材。
5. `doc/syntax/`: 按功能拆分的语法速查, 只展示当前正确语法。
6. `doc/memory.md`: v1 可实现运行时内存模型。
7. `doc/memory_layout_structs.md`: allocator block、managed object 和 layout table 的结构布局伪代码。
8. `doc/arc.md`: 长期 ARC/Perceus/并发优化草案, 不作为 v1 直接实现规格。
9. `doc/wit/wasi_p3_lowering.md`: `@wasi` / WIT / component lowering 的 compiler-facing 合同和当前可验证产物。
10. `doc/wit/wasi_registry.json`: 当前已登记的 WIT target / record mirror registry, 供 manifest 校验和 component-plan 工具消费。
11. `doc/roadmap_status.md`: roadmap 项目的当前状态、证据、跳过原因和恢复条件。

## 1. 阅读路径

1. 查语法是否可解析: 先看 `doc/grammar.peg`, 再看 `doc/syntax/` 对应功能页。
2. 查语义是否允许: 看 `doc/spec_rules.md` 对应章节。
3. 查正反例: 看 `doc/spec_examples.md`。
4. 查运行时表示、ARC、storage 或 text lowering: 看 `doc/memory.md`; 查 allocator/block/object/layout 结构字段看 `doc/memory_layout_structs.md`。
5. 查 `@wasi` / WIT / component lowering 边界: 看 `doc/wit/wasi_p3_lowering.md`; 查当前已登记 target 和 record mirror 看 `doc/wit/wasi_registry.json`。
6. 查当前实现状态和暂跳过项: 看 `doc/roadmap_status.md`。
7. 改 parser 语法时, 同步 `doc/grammar.peg`、`doc/syntax/`、测试和必要的 `doc/spec_rules.md` 语义约束。
8. 改语义或静态约束时, 同步 `doc/spec_rules.md`、示例、测试和必要的 `doc/syntax/` 速查。

## 2. 规则索引

| 主题 | 详细规则 | 速查 / 示例 |
| --- | --- | --- |
| 分层模型 | `doc/spec_rules.md` 第 1 章 | `doc/grammar.peg`, `doc/memory.md`, `doc/memory_layout_structs.md` |
| 词法、命名、保留名 | `doc/spec_rules.md` 第 2 章 | `doc/grammar.peg`, `doc/syntax/README.md` |
| 模块、导入、可见性 | `doc/spec_rules.md` 第 3 章 | `doc/syntax/module.md` |
| Host ABI / `@wasi` / WIT lowering | `doc/spec_rules.md` 第 3, 13-14 章 | `doc/wit/wasi_p3_lowering.md`, `doc/wit/wasi_registry.json` |
| 类型、结构体、union、enum、error | `doc/spec_rules.md` 第 4 章 | `doc/syntax/type.md`, `doc/syntax/struct.md`, `doc/syntax/union.md`, `doc/syntax/enum.md`, `doc/syntax/error.md` |
| 表达式、字面量、定型 | `doc/spec_rules.md` 第 5 章 | `doc/syntax/expression.md`, `doc/spec_examples.md` |
| 绑定、赋值、作用域 | `doc/spec_rules.md` 第 6 章 | `doc/spec_examples.md` |
| 函数、调用、重载、返回 | `doc/spec_rules.md` 第 7 章 | `doc/syntax/function.md` |
| 泛型与接口约束 | `doc/spec_rules.md` 第 8 章 | `doc/syntax/generic.md` |
| 判断族、类型收窄、core 数值函数 | `doc/spec_rules.md` 第 9-10 章 | `doc/syntax/builtin.md` |
| `@get/@set` 路径 primitive | `doc/spec_rules.md` 第 11 章 | `doc/syntax/expression.md`, `doc/syntax/builtin.md` |
| 控制流、`defer`、loop | `doc/spec_rules.md` 第 12 章 | `doc/syntax/control.md`, `doc/syntax/loop.md` |
| 编译期、入口、运行时边界 | `doc/spec_rules.md` 第 13 章 | `doc/syntax/entry-test.md`, `doc/memory.md` |
| 标准库边界 | `doc/spec_rules.md` 第 14 章 | `src/*.do`, `doc/roadmap_status.md` |
| 测试声明模型 | `doc/spec_rules.md` 第 15 章 | `doc/syntax/entry-test.md`, `tool/build/test/README.md` |
| PEG 主文法说明 | `doc/spec_rules.md` 第 16 章 | `doc/grammar.peg` |
| 诊断与测试约定 | `doc/spec_rules.md` 第 17 章 | `tool/build/test/README.md` |
| 非目标 | `doc/spec_rules.md` 第 18 章 | `doc/roadmap_status.md` |

## 3. v1 核心边界摘要

1. `PEG` 只定义可解析结构; 静态约束只承载需要类型、作用域、可见性或数据流信息的判断。
2. 运行层按 `builtin -> core -> std` 分层; 依赖只能向下。
3. `doc/grammar.peg` 是 parser 可执行文法单一来源; `spec.md` 和 `spec_rules.md` 不再内嵌完整 PEG。
4. `builtin` special form、core 路径 primitive 和 core 固定函数名都必须通过保留形态调用, 不参与普通函数声明、重载、遮蔽或 import alias。
5. `[T]` 是 core 连续存储 primitive; `text` 是源码文本基础类型, 语义要求有效 UTF-8。二者边界必须显式转换。
6. `Error` 是编译器内部合成诊断/工具视图, 源码类型位不能直接写 `Error`。
7. union 只以内联平铺类型表达式出现; 源码没有顶层类型别名声明。返回位、字段、局部绑定、storage 元素、type args 和普通固定数据参数可写 union/nullable; 变参元素、函数类型和接口约束参数不接收 union/nullable。
8. 函数重载只按参数类型序列决议; 返回类型不参与重载身份。
9. `@get/@set` 只承载结构字段和 `[T]` storage 路径 primitive; `List/HashMap` 等高层集合由 `std` 或用户库提供普通函数。
10. `loop` 分为无限循环、集合循环、消费循环和字段反射循环; v1 不提供通用 iterator 协议。
11. `@wasi` 声明的是 WIT binding, 不是普通 core Wasm import; 当前只开放已登记的 scalar/record/list<u8> 与少量 result-area wrapper 子集进入 lowering, 完整 component/resource/future/variant 支持仍后置。
12. 顶层入口固定为 `start() { ... }`; 测试声明固定为 `test "name" { ... }`。
13. runtime trap / safety failure 与源码可见错误枚举分离; 越界、primitive safety failure 不通过 `Error` 或普通错误枚举返回。

## 4. 维护规则

1. 不在 `doc/spec.md` 继续堆叠详细规则; 新规则默认进入 `doc/spec_rules.md` 的对应章节。
2. 不在 `doc/spec_rules.md` 内嵌大段 parser PEG; parser 结构进入 `doc/grammar.peg`。
3. 不在 `doc/spec_rules.md` 内堆叠大量正反例; 示例和推荐写法进入 `doc/spec_examples.md`。
4. `doc/syntax/` 只放当前正确语法速查, 不放长篇设计争论。
5. 改语法、语义或实现时, 必须同步对应测试; parser/semantic/build 变更默认用 `./tool/build/test/run_tests.sh` 验证。
6. 文档引用章节号时优先引用 `doc/spec_rules.md`, 因为 `doc/spec.md` 只是入口。
