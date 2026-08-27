write = @host_func("demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    values [u32]
    bytes [u8]
}

start() {}
