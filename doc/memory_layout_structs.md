# do v1 内存布局 Zig 结构伪代码

**状态**: v1 当前草案, 已与 `doc/memory.md` 对齐。
**目标**: 只描述 allocator block、managed object、layout table 和 ARC release/COW 原型的字段与作用。

---

## 1. 基础常量

```zig
const BLOCK_SIZE: usize = 1024; // allocator 内部固定 1KB block
```

Wasm memory grow 的页大小仍是 64KB。allocator 在 64KB page 内切成 64 个 1KB block。

字段排序原则:

1. `cap` 固定在每个 block 结构的 offset 0, 方便先用 `Block` 公共视图判断形态。
2. 需要 4B 访问的字段和 `bitmap` / `data` 起点保持 4B 对齐。
3. 小对象 slot 占用状态以 `bitmap` 为权威状态; `used_count/free_hint/word_hint` 都从 bitmap 推导, 不进入 v1 release header。
4. slot 规格按 4B 步进, block 内只保存 `slot_units`, `slot_size = slot_units * 4`。
5. 可推导的 `slot_size/used_count/bitmap_pad/data_start/block_bytes` 不作为显式结构字段。

---

## 2. SlotClassState

编译器/runtime 可以提前生成固定的小对象规格外置状态。每个 slot 规格用一个 `AtomicU64` 同时保存链表头和分配游标:

```zig
const SlotClassState = u64;

// bits 63..32 = head_block
// bits 31..0  = cursor_block
slot_classes: [MAX_SLOT_UNITS + 1]AtomicU64;
```

`slot_units` 是 4B 单位:

```text
slot_size = slot_units * 4
slot_class_state = slot_classes[slot_units]
```

说明:

1. `head_block` 是同 `slot_units` 的 `SmallBlock` 链表头, `0xffff_ffff` 表示没有。
2. `cursor_block` 是下次分配优先扫描的 block, `0xffff_ffff` 表示从 `head_block` 开始。
3. `head_block/cursor_block` 不进入每个 `SmallBlock`, 而是每个规格一个外置状态。
4. 分配时先按 object size 算出 `slot_units`, 再读取 `slot_classes[slot_units]`。
5. 找到可用 block 后, 用 CAS 把 `cursor_block` 更新成这个 block。
6. 释放 slot 时清对应 bitmap bit, 然后把 `cursor_block` 更新成刚释放出空位的 block。
7. 新增 `SmallBlock` 时, 用 CAS 同时更新 `head_block` 和 `cursor_block`, 避免两个字段出现半新半旧状态。
8. v1 单线程 runtime 可以退化为普通 `u64` 写入; shared memory/多线程阶段使用 `AtomicU64`。

示意:

```text
slot_classes[8] = pack(head_block = block_a, cursor_block = block_c)

block_a -> block_b -> block_c -> nil
```

注意: block index `0` 是有效 block, 不能作为空链表哨兵。slot class 链表和 free span 链表统一使用 `0xffff_ffff` 表示 none。

---

## 3. 公共 Block

```zig
const Block = extern struct {
    // 所有具体 block 结构的第 1 字节都必须是 cap。
    // allocator 可以先用 Block 视图读取这个字段, 再判断实际形态。
    //
    // cap == 0: free span head
    // cap == 1: large object span head
    // cap > 1: small object block, cap 就是 slot 数量
    cap: u8,
};
```

这个公共结构只用于先读 `cap` 并判断 block 形态。它不定义 `data` 起点; 具体 `data` 起点以 `FreeBlock` / `LargeBlock` / `SmallBlock` 的完整结构为准。

---

## 4. SmallBlock

```zig
const SmallBlock = extern struct {
    // cap > 1, 表示当前 block 有多少个 slot
    cap: u8,
    slot_units: u8, // slot_size = slot_units * 4
    flags: u8, // lock/state/reserved
    _pad: u8, // 对齐到 4B

    next_block: u32, // 同 slot_units 的下一个 SmallBlock, 0 表示没有

    bitmap: [0]u8, // 后面紧跟 bitmap, bitmap_pad 在 bitmap 后补齐到 data 对齐

    // bit = 0 表示 slot 空闲
    // bit = 1 表示 slot 已使用
    //
    // bitmap_pad 是推导出的对齐填充区, 不是固定字段。
    // data 是插槽数据起点:
    // slot = Object
};
```

推导字段:

```text
slot_size    = slot_units * 4
bitmap_bytes = ceil(cap / 8)
bitmap_pad    = align_up(offset_of(bitmap) + bitmap_bytes, 4) - (offset_of(bitmap) + bitmap_bytes)
data          = offset_of(bitmap) + bitmap_bytes + bitmap_pad
used_count    = popcount(bitmap)
```

小对象布局:

```text
SmallBlock
bitmap:
  bitset
bitmap_pad:
  alignment padding
data:
  slot0: Object
  slot1: Object
  slot2: Object
```

约束:

1. small block 必须满足 `cap > 1`。如果某个 slot class 在 1KB block 内只能放 1 个 slot, 就不能作为 small block, 必须走 large object。
2. `next_block` 串联同 `slot_units` 的所有 `SmallBlock`, 不要求链上的 block 一定有空位。
3. 分配时从 `slot_classes[slot_units].cursor_block` 开始扫描, cursor 为空时从 `head_block` 开始。
4. 如果整条链都满, 新建 `SmallBlock` 并挂到该 slot class 链。
5. allocator 扫描 bitmap, 找到第一个 0 bit 后置 1; 多线程阶段用 atomic bitset/CAS。
6. 释放 slot 时通过 object 地址反推所属 `SmallBlock`, 清 bitmap bit, 并把该规格的 `cursor_block` 更新为当前 block。
7. `used_count` 不存字段; 需要判断空/满时从 bitmap `popcount` 推导。
8. 当 `popcount(bitmap) == 0` 时, 这个 `SmallBlock` 从 slot class 链移除, 转回 `FreeBlock`, 之后可以重新分配成其他 `slot_units` 的 `SmallBlock` 或并入 free span。

---

## 5. LargeBlock

```zig
const LargeBlock = extern struct {
    // cap == 1
    cap: u8,
    _pad: [3]u8, // 对齐到 4B

    span_len: u32, // 这个大对象连续占用了多少个 1KB block

    data: [0]u8, // 后面紧跟一个 Object

    // continuation blocks 没有自己的 header。
};
```

推导字段:

```text
block_bytes = span_len * BLOCK_SIZE
```

大对象布局:

```text
LargeBlock
data:
  Object
  continuation blocks: Object.data continues, no header
```

`cap == 1` 只表示这个 span 只承载 1 个对象。释放时仍然必须读取 `span_len`, 才能知道要归还多少个 1KB block。

---

## 6. FreeBlock

```zig
const FreeBlock = extern struct {
    // cap == 0
    cap: u8,
    _pad: [3]u8, // 对齐到 4B

    span_len: u32,  // 连续空闲 block 数量
    next_free: u32, // 下一个 free span 的 block index, 0 表示没有

    data: [0]u8, // 空闲区域, allocator 不按 Object 解释
};
```

`FreeBlock` 只存在于连续空闲 span 的第一个 1KB block。后续 continuation block 不保存 `span_len` / `next_free`。

空闲状态下才使用 `next_free`。allocated large object 没有 `next_block` / `next_free`。

```text
FreeBlock{span_len = 3}
FreeCont
FreeCont
SmallBlock
FreeBlock{span_len = 4}
FreeCont
FreeCont
FreeCont
SmallBlock
```

物理 block 永远固定为 1KB。allocator 可以在这些 1KB block 之间做状态转换:

```text
一个 free span 拆成多个 SmallBlock:
  FreeBlock{span_len = 4}
  => SmallBlock + SmallBlock + SmallBlock + SmallBlock

多个相邻空 SmallBlock 合并成 free span:
  SmallBlock(popcount(bitmap) == 0) + SmallBlock(popcount(bitmap) == 0)
  => FreeBlock{span_len = 2}

一个 free span 分配成 LargeBlock:
  FreeBlock{span_len = 4}
  => LargeBlock{span_len = 4}

LargeBlock 释放后转回 free span:
  LargeBlock{span_len = 4}
  => FreeBlock{span_len = 4}
```

合并时只在新 free span head 写 `span_len`; continuation block 不重复记录递减长度。

---

## 7. Object

```zig
const Object = extern struct {
    rc: u32, // 引用计数

    type_id: u32, // layout table 索引, 用于释放 managed 字段 / 元素

    data: [0]u8, // tail bytes 标记, 不是源码里的 [u8] managed value
};
```

`Object.data` 是 runtime typed layout 的起点。`data: [0]u8` 只表示后面紧跟可变长度 tail bytes, 不是源码里的 `[u8]` managed value。

---

## 8. StorageKind

源码值进入 struct field、list element 或 object payload 时, 先归一成一种 storage representation:

```zig
const StorageKind = enum {
    scalar,       // u8/i8/u16/i16/u32/i32/u64/i64/f32/f64/bool/enum/error
    inline_bytes, // inline struct 或固定布局 bytes
    handle,       // text, List<T>, managed struct
};
```

说明:

1. `scalar` 直接存数值。
2. `enum` 和 `error` 按 carrier 数值存放。
3. `inline_bytes` 没有独立 reference count, 生命周期跟随外层 payload。
4. `handle` 是 `u32` managed handle, 指向另一个 `Object`。
5. `handle` 指向的对象有自己的 reference count; 外层对象只持有它的一份引用。

---

## 9. ObjectDataKind

`Object` 的 header 不随类型变化, 统一是 `rc + type_id + data`。变化的是 `data` 的解释方式:

```zig
const ObjectDataKind = enum {
    text_data, // text: len + UTF-8 bytes
    list_data,   // List<T>: len + cap + element storage
    struct_data, // managed struct: fixed fields
};
```

`ObjectDataKind` 不一定要作为独立字段存进 object。v1 草案中它可以由 `type_id -> layout table` 推导出来。

---

## 10. Payload layout

### text

```text
Object
data:
  len u32
  utf8 bytes...
```

`text` 是可变字节长度对象, 所以需要 `len` 表示 UTF-8 byte length。v1 字符串按不可变值处理, 不需要通用 `cap`。

### List<T>

```text
Object
data:
  len u32
  cap u32
  element storage...
```

`List<T>` 是可变元素数量对象:

1. `len` 表示当前有效元素数量, 用于 `@len`、循环和边界检查。
2. `cap` 表示 runtime 预分配容量, 用于 `put`/扩容/COW。
3. `cap` 不是源码可见语义; 源码只能观察 `len`。
4. allocator 实际分配空间可以大于 `cap` 对应的字节数, 这部分来自 slot/span padding, 不作为 list 容量暴露。

推导字段:

```text
element_start = align_up(offset_of(data) + sizeof(len) + sizeof(cap), element_align)
used_bytes    = element_start + cap * element_storage_size
```

`List<T>` 的 element storage 不是固定为 handle, 而是由 `T` 的 `StorageKind` 决定:

```text
List<u8>:
  u8, u8, u8...

List<Point> where Point is inline:
  Point bytes, Point bytes...

List<User> where User is managed:
  user_handle u32, user_handle u32...
```

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

固定布局的 managed struct 不需要 `len/cap`。它的 data layout 完全由 `type_id` 指向的 layout table 决定。

`name_handle` 指向独立的 text object。释放 `User` 时, layout table 指示 runtime 对 `name_handle` 执行 `dec`。

---

## 11. type_id 用途

`type_id` 只属于 managed object。inline struct 不带 `Object`, 因此也没有 `type_id`。

`type_id` 用来从 layout table 查释放规则:

```text
dec(handle)
  rc -= 1
  if rc == 0:
      layout = layout_table[type_id]
      drop managed fields / managed elements
      free object
```

只靠对象大小无法替代 `type_id`, 因为相同大小的 payload 可能有不同 managed 字段 offset。

---

## 12. release worklist

释放必须用显式 worklist, 不用递归释放深层对象:

```text
release(handle):
  worklist.push(handle)
  while worklist not empty:
      h = worklist.pop()
      object = object_from_handle(h)
      object.rc -= 1
      if object.rc > 0:
          continue
      layout = layout_table[object.type_id]
      for child in managed_children(object, layout):
          worklist.push(child)
      allocator.free(object)
```

说明:

1. `inc/dec` 是编译器插桩和 runtime 内部操作, 源码不可见。
2. `rc == 0` 后必须先通过 layout table 找 managed child, 再归还 allocator。
3. managed 字段只存 `u32 handle`; child object 的生命周期由自己的 `rc` 决定。
4. worklist 能避免 `List<List<...>>` 或嵌套 managed struct 释放时递归栈溢出。
5. double free / unknown handle 属于 runtime safety failure。

---

## 13. 关键约束

1. `Block.cap == 0` 表示 free span head。
2. `Block.cap == 1` 表示 large object span head。
3. `Block.cap > 1` 表示 small object block, 且 `cap` 就是 slot 数量。
4. 小对象 block 是 `SmallBlock`, 每个 slot 内各有自己的 `Object`。
5. 大对象 span 只有第一个 block 是 `LargeBlock`, 后续 continuation block 没有 header。
6. `next_block` 只属于 small block 链表, 链上可以包含满 block。
7. `next_free` 只属于 free span 状态。
8. allocated large object 没有 `next_block` / `next_free`。
9. inline 字段没有独立 reference count, 生命周期跟随外层 object 或外层 inline value。
10. managed 字段在外层 payload 里只存 `u32 handle`, 被 handle 指向的对象仍然有自己的 reference count。
11. `Object` v1 草案只保留 `rc + type_id + data`; `len/cap` 不属于通用 object 头。
12. 固定布局 struct 的 data 不需要 `len/cap`; `text` 需要 `len`; `List<T>` 需要 `len/cap`。
13. `ObjectDataKind` 不单独进入 `Object`; 由 `type_id` 查 layout table 得到。
14. `popcount(SmallBlock.bitmap) == 0` 时, block 不再保留原规格, 转回可复用空闲状态。
15. `slot_classes[slot_units]` 是全局 allocator 外置状态; v1 可以普通写入, shared memory 阶段使用 `AtomicU64`。

---

## 14. 原型与验证

当前草案有四个文档侧原型:

1. `doc/arc.ts`: 计算 1KB SmallBlock 的 4B 步进 slot class 和利用率。
2. `doc/arc_allocator.ts`: 验证 64KB page 切成 64 个 1KB block、bitmap small block、large span、free span 合并和 slot class state。
3. `doc/arc_object_runtime.ts`: 验证 `Object rc/type_id/data`、layout table、`inc/dec`、release worklist、managed child drop 和释放后 allocator slot 复用。
4. `doc/arc_cow_runtime.ts`: 验证 `[T]` 写入时的值语义 COW: `rc == 1` 且容量足够时复用, `rc > 1` 或容量不足时 clone/grow。

验证入口:

```bash
bun doc/arc.ts
bun doc/arc_allocator.test.ts
bun doc/arc_object_runtime.test.ts
bun doc/arc_cow_runtime.test.ts
tsc --noEmit --target ES2020 --module commonjs doc/arc.ts doc/arc_allocator.ts doc/arc_allocator.test.ts doc/arc_object_runtime.ts doc/arc_object_runtime.test.ts doc/arc_cow_runtime.ts doc/arc_cow_runtime.test.ts
```
