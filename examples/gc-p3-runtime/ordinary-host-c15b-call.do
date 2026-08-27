write = @host_func("demo:marshal-record-managed-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
}

start() {
    value Writing = Writing{code = 7, label = "hello"}
    write(value)
}
