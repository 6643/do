create = @host_func("do:resource-probe/ledger@0.1.0", "create", (u32) -> Ticket)
borrow_value = @host_func("do:resource-probe/ledger@0.1.0", "borrow-value", (Ticket) -> u32)
consume = @host_func("do:resource-probe/ledger@0.1.0", "consume", (Ticket) -> u32)
drop_ticket = @host_func("do:resource-probe/ledger@0.1.0", "drop", (Ticket) -> nil)

Ticket = @wasi_resource("do:resource-probe/ledger/ticket", {
    .id i64
})

run(seed u32) -> u32 {
    first Ticket = create(seed)
    value u32 = borrow_value(first)
    consume(first)
    second Ticket = create(seed)
    borrow_value(second)
    drop_ticket(second)
    return value
}

start() {}
