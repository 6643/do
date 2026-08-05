create = @host("do:resource-probe/ledger@0.1.0", "create", (u32) -> Ticket)
drop_ticket = @host("do:resource-probe/ledger@0.1.0", "drop", (Ticket) -> nil)

Ticket = @wasi_resource("do:resource-probe/ledger/ticket", { .id i64 })

start() {
    ticket Ticket = create(7)
    drop_ticket(ticket)
    drop_ticket(ticket)
}
