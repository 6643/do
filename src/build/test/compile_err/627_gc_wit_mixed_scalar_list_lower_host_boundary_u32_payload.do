write = @host_func("demo:marshal-record-mixed-scalar-list-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    payload [u32]
}

start() {}
