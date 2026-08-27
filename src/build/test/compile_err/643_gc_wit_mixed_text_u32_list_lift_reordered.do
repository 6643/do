read = @host_func("demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0", "read", () -> Reading)

Reading {
    payload [u32]
    label text
    code u32
}

start() {}
