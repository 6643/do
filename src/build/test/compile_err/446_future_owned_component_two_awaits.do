read = @host_func("do:future-owned-canonical/source@0.1.0", "read", () -> Future<Ticket>)
Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })

run(mode u32) -> nil {
    pending Future<Ticket> = read()
    ticket Ticket = @await(pending)
    second Future<Ticket> = read()
    second_ticket Ticket = @await(second)
}

start() {}
