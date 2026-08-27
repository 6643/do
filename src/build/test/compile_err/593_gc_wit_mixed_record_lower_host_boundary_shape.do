write = @host_func("demo:marshal-record-mixed-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    count u64
    status u32
}

start() {}
