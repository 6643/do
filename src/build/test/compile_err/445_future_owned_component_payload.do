read = @host("do:future-owned-canonical/source@0.1.0", "read", () -> Future<i32>)
Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })

run(mode u32) -> nil {
    pending Future<i32> = read()
    value i32 = @await(pending)
}

start() {}
