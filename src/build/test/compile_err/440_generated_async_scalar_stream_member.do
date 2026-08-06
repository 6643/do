stream = @host("do:generic-async-scalar-probe/host@0.1.0", "stream", () -> Stream<u8>)

run() -> nil {
    reader Stream<u8> = stream()
    pending Future<u8> = @next(reader)
    value u8 = @await(pending)
}

start() {}
