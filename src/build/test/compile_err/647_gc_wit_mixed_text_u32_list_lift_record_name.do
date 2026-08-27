read = @host_func("demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0", "read", () -> OtherReading)

OtherReading {
    code u32
    label text
    payload [u32]
}

start() {}
