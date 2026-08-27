write = @host_func("demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0", "write", (OtherWriting) -> nil)

OtherWriting {
    code u32
    label text
    payload [u32]
}

start() {}
