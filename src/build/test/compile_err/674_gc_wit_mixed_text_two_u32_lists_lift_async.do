read = @host_async_func("demo:marshal-record-mixed-text-two-u32-lists-lift/api@1.0.0", "read", () -> Reading)

Reading {
    code u32
    label text
    first [u32]
    second [u32]
}

start() {}
