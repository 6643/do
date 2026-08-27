write = @host_async_func(
    "demo:marshal-record-managed-lower/api@1.0.0",
    "write",
    (Writing) -> nil
)

Writing {
    code u32
    label text
}

start() {}
