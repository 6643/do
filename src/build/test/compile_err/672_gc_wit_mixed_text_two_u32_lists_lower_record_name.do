write = @host_func("demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0", "write", (OtherWriting) -> nil)

OtherWriting {
    code u32
    label text
    first [u32]
    second [u32]
}

start() {}
