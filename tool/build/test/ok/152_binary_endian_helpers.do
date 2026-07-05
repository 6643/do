binary_read_u16_be = @lib("binary.do", read_u16_be)
binary_read_u16_le = @lib("binary.do", read_u16_le)
binary_read_u32_be = @lib("binary.do", read_u32_be)
binary_read_u32_le = @lib("binary.do", read_u32_le)
binary_read_u64_be = @lib("binary.do", read_u64_be)
binary_read_u64_le = @lib("binary.do", read_u64_le)
binary_write_u16_be = @lib("binary.do", write_u16_be)
binary_write_u16_le = @lib("binary.do", write_u16_le)
binary_write_u32_be = @lib("binary.do", write_u32_be)
binary_write_u32_le = @lib("binary.do", write_u32_le)
binary_write_u64_be = @lib("binary.do", write_u64_be)
binary_write_u64_le = @lib("binary.do", write_u64_le)

test "binary endian helpers" {
    data [u8] = .{1, 2, 3, 4, 5, 6, 7, 8}
    ok bool = true
    ok = @and(ok, @eq(binary_read_u16_be(data, 0), 258))
    ok = @and(ok, @eq(binary_read_u16_le(data, 0), 513))
    ok = @and(ok, @eq(binary_read_u32_be(data, 0), 16909060))
    ok = @and(ok, @eq(binary_read_u32_le(data, 0), 67305985))
    ok = @and(ok, @eq(binary_read_u64_be(data, 0), 72623859790382856))
    ok = @and(ok, @eq(binary_read_u64_le(data, 0), 578437695752307201))
    ok = @and(ok, @eq(binary_write_u16_be(258), .{1, 2}))
    ok = @and(ok, @eq(binary_write_u16_le(258), .{2, 1}))
    ok = @and(ok, @eq(binary_write_u32_be(16909060), .{1, 2, 3, 4}))
    ok = @and(ok, @eq(binary_write_u32_le(16909060), .{4, 3, 2, 1}))
    ok = @and(ok, @eq(binary_write_u64_be(72623859790382856), data))
    ok = @and(ok, @eq(binary_write_u64_le(72623859790382856), .{8, 7, 6, 5, 4, 3, 2, 1}))
    if ok return
}
