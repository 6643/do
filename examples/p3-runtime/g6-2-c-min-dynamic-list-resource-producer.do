make_ticket = @host("do:g6-2-c-min-dynamic-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_func("do:g6-2-c-min-dynamic-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-c-min-dynamic-producer/source/ticket", { .id i64 })
ResourceEntry {
    .ticket Ticket
}
ProducerError error = Io | Pipe | InvalidMode

produce(count u32) -> Result<nil, ProducerError> {
    return Ok()
}

start() {}
