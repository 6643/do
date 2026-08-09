consume = @host_async_func("do:g6-2-scalar-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[u32]>) -> Result<nil, ProducerError>)
ProducerError error = Io | Pipe | InvalidMode

produce(count i64) -> Result<nil, ProducerError> {
    return Ok()
}

start() {}
