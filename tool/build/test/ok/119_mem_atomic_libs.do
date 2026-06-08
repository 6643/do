mem_len = @lib("mem.do", mem_len)
mem_can_access = @lib("mem.do", mem_can_access)
mem_read_u8 = @lib("mem.do", mem_read_u8)
mem_read_u16_le = @lib("mem.do", mem_read_u16_le)
mem_read_u32_be = @lib("mem.do", mem_read_u32_be)
mem_read_bytes_or = @lib("mem.do", mem_read_bytes_or)
mem_write_u8 = @lib("mem.do", mem_write_u8)
mem_write_u16_le = @lib("mem.do", mem_write_u16_le)
mem_write_u32_be = @lib("mem.do", mem_write_u32_be)
mem_write_bytes_or = @lib("mem.do", mem_write_bytes_or)
mem_fill = @lib("mem.do", mem_fill)
mem_copy = @lib("mem.do", mem_copy)

atomic_load_u32 = @lib("atomic.do", atomic_load_u32)
atomic_store_u32 = @lib("atomic.do", atomic_store_u32)
atomic_exchange_u32 = @lib("atomic.do", atomic_exchange_u32)
atomic_compare_exchange_u32 = @lib("atomic.do", atomic_compare_exchange_u32)
atomic_fetch_add_u32 = @lib("atomic.do", atomic_fetch_add_u32)
atomic_fetch_sub_u32 = @lib("atomic.do", atomic_fetch_sub_u32)
atomic_fetch_or_u32 = @lib("atomic.do", atomic_fetch_or_u32)
atomic_fetch_and_u32 = @lib("atomic.do", atomic_fetch_and_u32)
atomic_fetch_xor_u32 = @lib("atomic.do", atomic_fetch_xor_u32)

test "mem helpers read write copy fill" {
    data [u8] = .{0, 0, 0, 0, 0, 0, 0, 0}
    ok bool = true

    ok = @and(ok, @eq(mem_len(data), 8))
    ok = @and(ok, mem_can_access(data, 4, 4))
    ok = @and(ok, @not(mem_can_access(data, 5, 4)))

    data = mem_write_u8(data, 0, 17)
    data = mem_write_u16_le(data, 1, 258)
    data = mem_write_u32_be(data, 3, 16909060)

    ok = @and(ok, @eq(mem_read_u8(data, 0), 17))
    ok = @and(ok, @eq(mem_read_u16_le(data, 1), 258))
    ok = @and(ok, @eq(mem_read_u32_be(data, 3), 16909060))

    part [u8] = .{}
    part, part_ok = mem_read_bytes_or(data, 3, 4, part)
    ok = @and(ok, part_ok)
    ok = @and(ok, @eq(part, .{1, 2, 3, 4}))

    data, write_ok = mem_write_bytes_or(data, 0, .{9, 8, 7})
    ok = @and(ok, write_ok)
    ok = @and(ok, @eq(mem_read_u8(data, 0), 9))
    ok = @and(ok, @eq(mem_read_u8(data, 2), 7))

    data = mem_fill(data, 6, 2, 1)
    ok = @and(ok, @eq(mem_read_u8(data, 6), 1))
    ok = @and(ok, @eq(mem_read_u8(data, 7), 1))

    data = mem_copy(data, 3, 0, 3)
    copied [u8] = .{}
    copied, copied_ok = mem_read_bytes_or(data, 3, 3, copied)
    ok = @and(ok, copied_ok)
    ok = @and(ok, @eq(copied, .{9, 8, 7}))

    if ok return
}

test "atomic u32 helpers" {
    data [u8] = .{0, 0, 0, 0, 0, 0, 0, 0}
    ok bool = true

    data = atomic_store_u32(data, 0, 10)
    ok = @and(ok, @eq(atomic_load_u32(data, 0), 10))

    data, old_exchange = atomic_exchange_u32(data, 0, 20)
    ok = @and(ok, @eq(old_exchange, 10))
    ok = @and(ok, @eq(atomic_load_u32(data, 0), 20))

    data, seen_ok, swapped_ok = atomic_compare_exchange_u32(data, 0, 20, 30)
    ok = @and(ok, swapped_ok)
    ok = @and(ok, @eq(seen_ok, 20))
    ok = @and(ok, @eq(atomic_load_u32(data, 0), 30))

    data, seen_fail, swapped_fail = atomic_compare_exchange_u32(data, 0, 20, 40)
    ok = @and(ok, @not(swapped_fail))
    ok = @and(ok, @eq(seen_fail, 30))
    ok = @and(ok, @eq(atomic_load_u32(data, 0), 30))

    data, old_add = atomic_fetch_add_u32(data, 0, 5)
    ok = @and(ok, @eq(old_add, 30))
    ok = @and(ok, @eq(atomic_load_u32(data, 0), 35))

    data, old_sub = atomic_fetch_sub_u32(data, 0, 3)
    ok = @and(ok, @eq(old_sub, 35))
    ok = @and(ok, @eq(atomic_load_u32(data, 0), 32))

    data, old_or = atomic_fetch_or_u32(data, 0, 1)
    ok = @and(ok, @eq(old_or, 32))
    ok = @and(ok, @eq(atomic_load_u32(data, 0), 33))

    data, old_and = atomic_fetch_and_u32(data, 0, 31)
    ok = @and(ok, @eq(old_and, 33))
    ok = @and(ok, @eq(atomic_load_u32(data, 0), 1))

    data, old_xor = atomic_fetch_xor_u32(data, 0, 7)
    ok = @and(ok, @eq(old_xor, 1))
    ok = @and(ok, @eq(atomic_load_u32(data, 0), 6))

    if ok return
}
