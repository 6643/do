consume = @host_async_func("do:g6-2-scalar-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[u32]>) -> Result<nil, ProducerError>)
ProducerError error = Io | Pipe | InvalidMode

produce(count u32) -> Result<nil, ProducerError> {
    value u32 = count
    return Ok()
}

start() {}
