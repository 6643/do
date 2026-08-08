create = @host_func("do:resource-probe/ledger@0.1.0", "create", (u32) -> Ticket)
borrow_value = @host_func("do:resource-probe/ledger@0.1.0", "borrow-value", (Ticket) -> u32)
consume = @host_func("do:resource-probe/ledger@0.1.0", "consume", (Ticket) -> u32)

Ticket = @wasi_resource("do:resource-probe/ledger/ticket", {
    .id i64
})

start() {
    ticket Ticket = create(7)
    borrow_value(ticket)
    borrow_value(ticket)
    consume(ticket)
}

test "borrow preserves resource owner" {}
