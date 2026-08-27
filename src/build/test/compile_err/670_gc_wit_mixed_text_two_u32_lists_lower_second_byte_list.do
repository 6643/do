write = @host_func("demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    first [u32]
    second [u8]
}

start() {}
