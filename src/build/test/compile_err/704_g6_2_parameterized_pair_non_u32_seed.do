make_ticket = @host_func("do:g6-2-owned-record-pair-parameterized-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_async_func("do:g6-2-owned-record-pair-parameterized-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourcePair>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-owned-record-pair-parameterized-producer/source/ticket", { .id i64 })
ResourcePair {
    .left Ticket
    .right Ticket
}
ProducerError error = Io | Pipe | InvalidMode

produce(mode u32, left_seed i32, right_seed u32) -> Result<nil, ProducerError> {
    return Ok()
}

start() {}
