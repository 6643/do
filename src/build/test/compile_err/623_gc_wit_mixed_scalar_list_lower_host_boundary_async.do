write = @host_async_func("demo:marshal-record-mixed-scalar-list-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    payload [u8]
}

start() {}
