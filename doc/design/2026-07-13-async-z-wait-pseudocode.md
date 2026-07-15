# 异步支持方案 Z：`Future` / `Stream` + `@wait`（伪代码）

**状态:** 设计草案 / **未实现** / **不授权 codegen**  
**日期:** 2026-07-13  
**关系:** G6.2（`descriptor.read-directory`）见 `doc/pending_blocked.md`；WASI 形态见 `doc/wit/wasi_p3_lowering.md`；值语义见 `doc/memory.md`。

**否决 / v1 非目标:**

- 语言关键字 `async` / `await`
- `do foo()` / `go` spawn
- **`@wait_any`（及任何多 Future 竞速语法）** — 过复杂，暂不支持
- `Channel` / `select`
- 冷门公开名：`Once` / `Watch` / `Seq` / `Flow` 等（见 §1.1）

本文固定 **路线 Z** 的最小面。实现须单独立项。

---

## 1. 定案摘要

| 项 | 决议 |
| --- | --- |
| 模型 | **Z**：普通函数 + 两个标准类型 + **`@wait`**（非 `async`/`await`） |
| 一次结果 | **`Future<T>`**（WIT `future<T>`；值壳） |
| 多项序列 | **`Stream<T>`**（WIT `stream<T>`；值壳；**≠** `InputStream`） |
| 取一次结果 | **`@wait(f)`** → `T` |
| 多项消费 | **`loop x = recv(s)`**；`recv` 源扩展为 `Stream<T>`（及现有 `[T]`） |
| 多路竞速 | **不做**（无 `@wait_any`） |
| 启动 | 无 `go`/`async`；调用返回 `Future`/`Stream` 的函数即得到源 |
| Core Wasm | 无 async opcode；挂起仅在 `@wait` / `recv(Stream)` 边界 |

### 1.1 命名：用标准名，不用「别名菜单」

此前讨论里出现的 `Once` / `Watch` / `Seq` / `Flow` **不是**现有类型的 typedef，也 **不是**推荐公开 API。  
它们只是头脑风暴时的起名候选；**容易显得怪，且无收益**。

| 公开类型（定案） | 标准对齐 | 用途 |
| --- | --- | --- |
| **`Future<T>`** | WIT / 业界通用 `future` | 至多一次的异步结果；**只**用 `@wait` 取 `T` |
| **`Stream<T>`** | WIT `stream<T>` | 零或多次异步序列；**只**用 `recv` 拉项 |

**为何不必另起别名：**

1. WASI / Component 文档已经叫 future / stream — 实现者与宿主对照成本最低。  
2. 业界（Rust `Future`、各语言 stream 概念）认知成本低。  
3. `Once`/`Watch`/`Flow`/`Seq` 反而要解释「是不是 Future/Stream 的马甲」。

**与现有 `InputStream` 的关系（同名「Stream」但不同概念）：**

| 类型 | 是什么 |
| --- | --- |
| `Stream<T>` | **新建**泛型异步序列源（G6.2 directory entries 等） |
| `InputStream` / `OutputStream` | **已有**字节 I/O **resource 壳**（`.id`），同步 wrapper 路径 |

二者 **不是** alias，也不互相 typedef。文档与诊断须写清：  
`Stream<T>` ≠ `InputStream`。若嫌撞名，**优先保留标准 `Stream<T>`**，在 `InputStream` 文档标注 “byte stream resource”，而不是把泛型流改成 `Seq`/`Flow`。

源码 **禁止** 写 WIT 字面类型 `future<…>` / `stream<…>`；只写 do 的 `Future` / `Stream`。

---

## 2. 类型（概念）

```do
// 语言内建（伪；非当前 grammar）
// Future<T>  — 至多产生一次 T；完成前不可读 payload
// Stream<T>  — 零或多次 T；正常结束以 recv 得 nil（对齐现有消费循环）

ready_u8() -> Future<u8> {
    // -> Future<T> 时，`return <T>` 糖包成「已完成 Future」
    return 123
}

ready_err() -> Future<u8 | IoError> {
    return IoTimeout
}

// 禁止：Future<Future<T>> 自动拍平（v1 非法）
// 禁止：Future{…} 用户字面构造；仅 return 糖 / host wrapper / std
```

**壳规则（对齐 resource）:**

- 可：绑定、传参、返回。  
- 不可：算术、与整数互转伪造、窥视内部 id。  
- `@wait` **消费** `Future`（move）；二次 `@wait` 非法。

---

## 3. 内建：仅 `@wait`

```do
// 特殊形式（非普通函数）
// @wait(f Future<T>) -> T
//
// - 已完成：立即返回 payload，不挂起
// - 未完成：挂起直到 host/runtime 推进完成
// - 错误在 T 内：常用 Future<T | E>，@wait 只返回一个值

demo_wait() -> u8 {
    f Future<u8> = ready_u8()
    return @wait(f)
}

demo_wait_err() -> u8 | IoError {
    f Future<u8 | IoError> = ready_err()
    return @wait(f)
}
```

### 3.1 明确不做（含曾草案）

| 形态 | 状态 |
| --- | --- |
| `@wait_any(...)` | **v1 不做**（复杂：同型/异型返回、下标、未入选 Future 生命周期） |
| `@wait_all` / `@cancel` / timeout | 后置 |
| `@wait(stream)` | 非法；多项只用 `recv` |
| `await` / `async` 关键字 | 否决 |
| `First T \| Second U` 等标签联合语法 | 否决（且非现有语法） |

需要「谁先完成」时：v1 用户 **顺序** `@wait`，或以后单独立项竞速 API — **不**挤进最小面。

---

## 4. `Stream` 与 `recv`

```do
// 既有：loop value = recv(ch) { … }
// 今日 ch 可为 [T]
// 扩展：ch 可为 Stream<T>

// 私有 host（已落地 @host 形）
// .host_read_directory = @host(
//     "wasi:filesystem/types@0.3.0",
//     "descriptor.read-directory",
//     (Dir) -> Tuple<Stream<DirEntry>, Future<nil | DirError>>,
// )

list_dir_names(dir Dir) -> [text] | DirError {
    // Tuple 读取固定为 @get(t, <编译期整数字面量>)；无 .0 / .1 字段段
    // 见 spec_rules Tuple 规则；也可在公开 API 侧直接多返回，避免 Tuple 拆包
    pair Tuple<Stream<DirEntry>, Future<nil | DirError>> = read_directory(dir)
    entries Stream<DirEntry> = @get(pair, 0)
    done Future<nil | DirError> = @get(pair, 1)

    names [text] = []
    loop e = recv(entries) {
        // 结构体字段同样是 @get(e, .name)，不是 e.name
        names = append_name(names, @get(e, .name))
    }

    end nil | DirError = @wait(done)
    if @is(end, DirError) {
        return end
    }
    return names
}

// 更贴 do 的公开包装：多返回，调用方不必先握 Tuple
// read_directory(dir Dir) -> Stream<DirEntry>, Future<nil | DirError>
list_dir_names_v2(dir Dir) -> [text] | DirError {
    entries Stream<DirEntry>, done Future<nil | DirError> = read_directory(dir)
    names [text] = []
    loop e = recv(entries) {
        names = append_name(names, @get(e, .name))
    }
    end nil | DirError = @wait(done)
    if @is(end, DirError) {
        return end
    }
    return names
}
```

| 源 | 合法消费 |
| --- | --- |
| `Future<T>` | **仅** `@wait` |
| `Stream<T>` | **仅** `recv`（通常在 `loop` 内） |
| `[T]` | 现有 storage `recv` |

交叉使用 → 类型错误。

---

## 5. 错误模型

```do
// 错误落在 payload，不引入 wait 第二通道
f Future<File | FileError> = open_async(path)
r File | FileError = @wait(f)

// Stream 项错误：对齐现有 recv 文档扩展
// recv(stream) -> T | StreamItemError | nil
//   nil = 正常结束，不进 body
```

（字节 `StreamError` 枚举名已占用；泛型流项错误用领域枚举或另名，避免与 `InputStream` 的 `StreamError` 混用语义。）

---

## 6. 所有权（v1 简化）

```do
take(f Future<u8>) -> u8 {
    return @wait(f)
}

// @wait 后 f 失效；二次 @wait 非法
// Stream 在 recv 结束后失效
```

---

## 7. 组合伪代码（无竞速）

```do
// 顺序 wait 即可
load_sum() -> u64 | IoError {
    fa Future<u64 | IoError> = fetch_a()
    fb Future<u64 | IoError> = fetch_b()
    a u64 | IoError = @wait(fa)
    if @is(a, IoError) { return a }
    b u64 | IoError = @wait(fb)
    if @is(b, IoError) { return b }
    return @add(a, b)
}

// 返回 Future：有色只在返回类型上，无 async 关键字
add_async(x u8, y u8) -> Future<u8> {
    return @add(x, y)
}

and_then_inc(f Future<u8>) -> Future<u8> {
    v u8 = @wait(f)
    return @add(v, 1)
}
```

同步 `@host` / `now()` 等 **不**强制改成 `Future`。

---

## 8. Host / WASI

```do
// codegen（实现阶段）:
// WIT future -> Future 壳
// WIT stream -> Stream 壳
// @wait / recv(Stream) -> 推进 host 句柄
```

字节 resource 路径不变：`InputStream` / `read_stream` 等。

---

## 9. Runtime 边界（v1 最小）

- 目标：正确 `@wait` / `recv` **host** 产生的 `Future`/`Stream`（够 G6.2）。  
- 非目标：用户 `go`、M:N 调度、Channel、多 Future 竞速。  
- 已完成 Future 的 `@wait`：无 host 往返。

---

## 10. 实现 checklist

1. 内建类型名：`Future`、`Stream`（保留字/内建泛型）。  
2. 特殊形式：`@wait` only。  
3. `-> Future<T>` 的 `return T` 完成糖。  
4. `recv` 源：`[T] | Stream<T>`。  
5. move 消费：`@wait` 后 Future 失效。  
6. 诊断：禁止 `@wait(stream)`、`recv(future)`、二次 wait；**无** `@wait_any` 语法。  
7. 文档区分 `Stream<T>` vs `InputStream`。  
8. 测试：完成态 wait、host wait、read-directory 包装、InputStream 回归隔离。

---

## 11. 完整小品

```do
IoError error = IoTimeout | IoCanceled | IoFailed

fetch_a() -> Future<u64 | IoError> {
    return 10
}

fetch_b() -> Future<u64 | IoError> {
    return 20
}

sum_seq() -> u64 | IoError {
    fa Future<u64 | IoError> = fetch_a()
    fb Future<u64 | IoError> = fetch_b()
    a u64 | IoError = @wait(fa)
    if @is(a, IoError) { return a }
    b u64 | IoError = @wait(fb)
    if @is(b, IoError) { return b }
    return @add(a, b)
}

start() {
    s u64 | IoError = sum_seq()
    if @is(s, IoError) {
        return
    }
}
```

---

## 12. 状态

- **已定:** 方案 Z；类型 **`Future` / `Stream`**；消费 **`@wait` + `recv`**；无 `async`/`await`；**无 `@wait_any`**。  
- **未授权:** 实现。  
- **G6.2:** 本设计立项为实现计划后再开 lowering。
