# 类型

## 基础类型

| 类型 | 含义 |
| --- | --- |
| `i8` | 8 位有符号整数 |
| `i16` | 16 位有符号整数 |
| `i32` | 32 位有符号整数 |
| `i64` | 64 位有符号整数 |
| `u8` | 8 位无符号整数 |
| `u16` | 16 位无符号整数 |
| `u32` | 32 位无符号整数 |
| `u64` | 64 位无符号整数 |
| `isize` | 指针宽度有符号整数 |
| `usize` | 指针宽度无符号整数 |
| `f32` | 32 位浮点数 |
| `f64` | 64 位浮点数 |
| `bool` | 布尔类型 |
| `text` | 文本类型 |

### `text` 与 `[u8]`

`text` 是源码文本类型, 内容必须是有效 UTF-8。`[u8]` 是原始字节连续存储, 不是 `text` 的 alias, 不保证 UTF-8。

```do
bytes_of = @lib("text.do", bytes_of)
text_from = @lib("text.do", text_from)
byte_len = @lib("text.do", byte_len)
char_len = @lib("text.do", char_len)

name text = "do"
raw [u8] = bytes_of(name)
size usize = byte_len(name)

decoded = text_from(raw)
if @is(decoded, text) {
    chars = char_len(decoded)
    if @is(chars, usize) {
        return
    }
}
```

规则:

1. `@len/@get/@set/@put/@load_*` 只面向 `[T]` 连续存储; `text` 不能直接当 `[u8]` 使用。
2. 需要字节视图时使用 `bytes_of(s text) -> [u8]`; 需要从字节构造文本时使用 `text_from(bytes [u8]) -> text | Utf8Error`。
3. 普通字符串和行字符串必须是有效 UTF-8; 非法原始字节写 `[u8]` 聚合, 例如 `bad [u8] = .{255}`。
4. UTF-16 只作为库级 `[u16]` 编解码能力存在; 它不是 `text` 的核心表示。

## nil

```do
done() -> nil {
    return
}

// 可空值绑定
value User | nil = nil
```

## 连续存储

```do
// 字节连续存储
[u8]

// i32 连续存储
[i32]

// 结构体连续存储
[User]

// 可空元素连续存储
[User | nil]

// 嵌套连续存储
[[u8]]
```

## 命名类型

```do
// 命名类型
User

// 单参数泛型类型
Box<i32>

// 多参数泛型类型
Entry<text, User>

// 泛型参数内使用连续存储
HashMap<text, [User]>
```

## `Tuple<...>` 内建类型

`Tuple<T0, T1, ...>` 是源码层大写内建泛型类型, 表示固定顺序的位置元组。它与 `@wasi_func` / WIT 签名里的小写 `tuple<...>` 分离, 后者不能出现在普通源码类型位。

```do
make_pair(flag bool, code u8) -> Tuple<bool, u8> {
    return Tuple<bool, u8>{flag, code}
}

test "tuple pair" {
    pair Tuple<bool, u8> = make_pair(true, 7)
    first bool = @get(pair, 0)
    second u8 = @get(pair, 1)
    if @and(@eq(first, true), @eq(second, 7)) return
}
```

规则:

1. arity 下限为 2, 当前不设上限; `Tuple<>` / `Tuple<T>` 非法。
2. 构造固定为位置构造器 `Tuple<T0, T1, ...>{v0, v1, ...}`, 实参数量必须与 arity 完全一致; 第一版不支持命名字段构造。
3. 读取固定为 `@get(tuple_value, <compile-time-int>)`, 索引必须是编译期整数字面量且落在 `0..arity-1`; 第一版不支持 `.v0/.v1` 字段段访问, 也不支持 `@set(tuple_value, <index>, value)` 数字索引写入。
4. 允许嵌套 `Tuple<Tuple<i32, bool>, u8>`, 以及作为局部绑定、参数、单返回、struct 字段和 scheme-A packable `[Tuple<...>]` storage 元素 (标量 + managed payload/`text` handle + **pure-scalar 具名 struct 嵌套子槽**)。
5. **永不拍平**: 嵌套 Tuple / pure-scalar struct 直接元素保持嵌套类型与嵌套 `@get` 路径; 不与扁平 `Tuple<…>` 等同。详见 `doc/spec_rules.md` Tuple 节。
6. 小写 `tuple<bool, u8>` 在普通 typed bind 左侧报 `InvalidTypeRef`。
7. `@get(storage, i, j)` path chaining 与 managed/`text` / pure-scalar struct 叶子 storage 已支持 (`compile_ok/272`, `ok/192`)。后置: 含 managed 字段的 struct 直接子槽仍 `UnsupportedTupleStorageLeaf` (`compile_err/339`)。

## 函数类型约束

```do
// 无参数 nil 返回函数类型约束
#F = () -> nil

// 单参数单返回函数类型约束
#G = (i32) -> i32

// 多参数单返回函数类型约束
#H = (i32, text) -> bool

// 单参数多返回函数类型约束
#P = (i32) -> i32, bool
```

规则: 源码没有顶层类型别名声明。需要组合类型时, 在返回位、字段、局部绑定、storage 元素或 type args 里直接写 `T | nil` / `A | B`; 需要强类型名时用单字段 struct 表达。
