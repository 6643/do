create = @host("do:resource-probe/ledger@0.1.0", "create", (u32) -> Ticket)

Ticket = @wasi_resource("do:resource-probe/ledger/ticket", {
    .id i64
})

start() {
    ticket Ticket = create(7)
}
