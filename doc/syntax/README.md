# do 语法设计

本目录按功能拆分, 只展示当前正确语法。详细词法/命名/保留名约束以 `doc/spec_rules.md` 第 2 章和 `doc/grammar.peg` 为准; 本页只保留导航与占位速查。

- [模块和值](./module.md)
- [类型](./type.md)
- [函数](./function.md)
- [泛型](./generic.md)
- [结构](./struct.md)
- [联合类型](./union.md)
- [错误](./error.md)
- [枚举](./enum.md)
- [控制](./control.md)
- [循环](./loop.md)
- [表达式](./expression.md)
- [内建调用](./builtin.md)
- [入口和测试](./entry-test.md)

## 速查

1. 注释只能独立成行; 行注释写 `// ...`, 块注释写单层 `/* ... */`, 两者都不能跟在已有 token 后面。
2. 约束、空行和注释行对语法的具体影响不在本页重复, 以 `doc/spec_rules.md` 和 `doc/grammar.peg` 为准。

## 占位约定

| 形态 | 含义 |
| --- | --- |
| `Name` | 类型名 |
| `name` | 值名或函数名 |
| `_name` | 只读值名 |
| `.Name` | 私有类型声明名 |
| `.name` | 私有值声明名或字段段 |
