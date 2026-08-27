read = @host_func("demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0", "read", () -> Reading)

Reading {
    payload [u8]
    label text
    code u32
}

start() {}
