make_ticket = @host_func("do:g6-2-owned-record-triple-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_async_func("do:g6-2-owned-record-triple-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceTriple>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-owned-record-triple-producer/source/ticket", { .id i64 })
ResourceTriple {
    .left Ticket
    .middle Ticket
    .right Ticket
}
ProducerError error = Io | Pipe | InvalidMode

produce(mode u32, left_seed u32, middle_seed u32) -> Result<nil, ProducerError> {
    return Ok()
}

start() {}
