# do v1 内存分页与布局已收敛决策

**状态**: 当前结论, 已与 `doc/memory_layout_structs.md` 对齐。
**目标**: 记录已经排除的旧方案、当前推荐和验证入口, 避免后续再次回到 16B 公共对象头、4KB subpage 或 slot free-list 旧设计。

---

## 1. Wasm page 与 allocator block

### 当前方案

Wasm memory grow 固定以 64KB page 为粒度。Do allocator 在 page 内切成 64 个固定 1KB block:

```text
--------------------------- 64KB wasm page ---------------------------+
| block0 1KB | block1 1KB | block2 1KB | ... | block63 1KB |
+---------------------------------------------------------------------+
```

### 不再采用

不再使用 4KB subpage 作为 v1 小对象管理单位。

### 理由

1. 1KB block 更贴近当前小对象规格脚本和 bitmap small block 结构。
2. 大对象可以占用连续多个 1KB block, 不需要独占 64KB page。
3. 空 block、small block 和 large span 都能在同一物理粒度下转换。

---

## 2. Block 形态判定

### 当前方案

每个 block 第 1 字节固定是 `cap`:

```text
cap == 0: FreeBlock span head
cap == 1: LargeBlock span head
cap > 1 : SmallBlock, cap 表示 slot 数量
```

### 反例

不允许用 `0` 表示链表 none:

```text
slot_class.head_block = 0
```

因为 block index `0` 是有效地址。所有 block 链表和 free span 链表统一使用 `0xffff_ffff` 作为 none sentinel。

### 理由

1. allocator 能先用公共 `Block` 视图读取 `cap`, 再分派到具体结构。
2. `cap == 1` 能区分 large object span head。
3. `cap > 1` 直接给出 small block 的 slot 数量。

---

## 3. SmallBlock 状态

### 当前方案

SmallBlock 使用 bitmap 作为权威 slot 状态:

```zig
const SmallBlock = extern struct {
    cap: u8,
    slot_units: u8, // slot_size = slot_units * 4
    flags: u8,
    _pad: u8,

    next_block: u32,

    bitmap: [0]u8,
};
```

```text
SmallBlock header: 8B
bitmap_bytes = ceil(cap / 8)
data_start = align_up(8 + bitmap_bytes, 4)
slot_size = slot_units * 4
```

### 不再采用

不再把 `used_count/free_hint/word_hint` 存进 release header。它们都可以从 bitmap 推导。

### 理由

1. bitmap 能检测 slot 是否已使用, double free 检查更直接。
2. 多线程阶段可以升级到 atomic bitset/CAS。
3. header 更小, 当前固定为 8B。

---

## 4. SlotClassState 外置

### 当前方案

同一 `slot_units` 的 block 链表头和分配游标放到外置状态:

```zig
const SlotClassState = u64;

// bits 63..32 = head_block
// bits 31..0  = cursor_block
slot_classes: [MAX_SLOT_UNITS + 1]AtomicU64;
```

### 正例

```text
slot_classes[8] = pack(head_block = block_a, cursor_block = block_c)

block_a -> block_b -> block_c -> 0xffff_ffff
```

### 反例

不在每个 `SmallBlock` 中保存全局 head/cursor:

```text
SmallBlock {
  head_block
  cursor_block
  ...
}
```

这会造成重复状态, 释放和新增 block 时更容易出现半更新。

### 理由

1. 每个 size class 一个全局状态即可。
2. `head_block/cursor_block` 可以用一个 `u64` 原子更新。
3. v1 单线程可普通写入, 未来 shared memory 再切到 `AtomicU64/CAS`。

---

## 5. Object 公共头

### 当前方案

公共对象头只保留 `rc + type_id`:

```zig
const Object = extern struct {
    rc: u32,
    type_id: u32,
    data: [0]u8,
};
```

### 不再采用

不再使用 16B 公共头:

```text
+0   rc           u32
+4   type_id      u32
+8   len          u32
+12  cap_or_size  u32
+16  payload
```

### 理由

1. `len/cap` 不是所有 managed object 都需要。
2. `text` 只需要 `len`。
3. `List<T>` 需要 `len/cap`。
4. 固定布局 managed struct 不需要 `len/cap`。
5. 8B 公共头节省小对象 slot 空间。

---

## 6. Payload 布局

### text

```text
Object
data:
  len u32
  utf8 bytes...
```

`text` 不追加 NUL。需要 C ABI NUL 字符串时, 由 wrapper 临时构造。

### List<T>

```text
Object
data:
  len u32
  cap u32
  element storage...
```

`cap` 是 runtime 预分配容量, 不是源码可见语义。

### managed struct

```do
User {
    id u64
    name text
}
```

```text
Object
data:
  id u64
  name_handle u32
```

固定布局 struct 的字段由 `type_id -> layout table` 解释。

---

## 7. Layout table 与释放

### 当前方案

`type_id` 查 layout table, layout table 决定:

1. object data kind: `string_data`、`list_data` 或 `struct_data`。
2. payload size 和 alignment。
3. managed field offsets。
4. list element storage size。
5. list element 是否含 managed 子值。

释放路径:

```text
dec(handle)
  rc -= 1
  if rc == 0:
      layout = layout_table[type_id]
      drop managed fields / managed elements
      allocator.free(object)
```

### 理由

只靠对象大小无法判断 managed 字段 offset。相同大小的 struct 可能有不同 managed 字段, 必须通过 `type_id` 找 layout。

---

## 8. 已验证原型

当前有四个 TypeScript 文档侧原型:

1. `doc/arc.ts`: 计算 1KB SmallBlock 的 4B 步进 slot class 和利用率。
2. `doc/arc_allocator.ts`: 验证 1KB block、bitmap small block、large span、free span 合并和 slot class state。
3. `doc/arc_object_runtime.ts`: 验证 `Object rc/type_id/data`、layout table、`inc/dec`、release worklist 和 managed child drop。
4. `doc/arc_cow_runtime.ts`: 验证 `[T]` 写入的 COW 值语义。

验证入口:

```bash
bun doc/arc.ts
bun doc/arc_allocator.test.ts
bun doc/arc_object_runtime.test.ts
bun doc/arc_cow_runtime.test.ts
tsc --noEmit --target ES2020 --module commonjs doc/arc.ts doc/arc_allocator.ts doc/arc_allocator.test.ts doc/arc_object_runtime.ts doc/arc_object_runtime.test.ts doc/arc_cow_runtime.ts doc/arc_cow_runtime.test.ts
```
