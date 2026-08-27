write = @host_func("demo:marshal-record-byte-list-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    payload [u8]
    extra bool
}

start() {}
