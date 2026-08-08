make_ticket = @host_func("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_async_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
consume_again = @host_async_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
ResourceEntry {
    .ticket Ticket
}
ProducerError error = Io | Pipe | InvalidMode

produce(mode u32) -> Result<nil, ProducerError> {
    return Ok()
}

start() {}
