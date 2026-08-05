create = @host("do:resource-probe/ledger@0.1.0", "create", (u32) -> Ticket)
consume = @host("do:resource-probe/ledger@0.1.0", "consume", (Ticket) -> u32)

Ticket = @wasi_resource("do:resource-probe/ledger/ticket", {
    .id i64
})

start() {
    first Ticket = create(7)
    second Ticket = first
    consume(second)
}

test "resource assignment transfers owner" {}
