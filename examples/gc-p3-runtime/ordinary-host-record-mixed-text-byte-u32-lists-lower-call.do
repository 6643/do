write = @host_func("demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    bytes [u8]
    values [u32]
}

start() {
    value Writing = Writing{code = 7, label = "hello", bytes = .{10, 20, 5}, values = .{3, 4}}
    write(value)
}
