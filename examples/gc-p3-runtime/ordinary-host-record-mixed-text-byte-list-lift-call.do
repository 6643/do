read = @host_func("demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0", "read", () -> Reading)

Reading {
    code u32
    label text
    payload [u8]
}

start() {
    read()
}
