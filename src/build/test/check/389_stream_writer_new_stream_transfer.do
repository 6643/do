produce() -> nil {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    next StreamWriter<u8> = writer
    defer close(next)
    _ = reader
}

start() {}
