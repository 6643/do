async produce() -> nil {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    close(writer)
    _ = reader
}

start() {}
