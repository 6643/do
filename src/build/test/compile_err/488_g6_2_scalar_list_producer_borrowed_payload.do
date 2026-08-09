consume = @host_async_func("do:g6-2-scalar-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[BorrowedEntry]>) -> Result<nil, ProducerError>)
BorrowedEntry {
    .value u32
}
ProducerError error = Io | Pipe | InvalidMode

produce(count u32) -> Result<nil, ProducerError> {
    return Ok()
}

start() {}
