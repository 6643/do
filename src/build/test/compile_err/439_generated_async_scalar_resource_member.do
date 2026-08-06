resource = @host("do:generic-async-scalar-probe/host@0.1.0", "resource", () -> Future<u32>)

run() -> nil {
    pending Future<u32> = resource()
    @cancel(pending)
}

start() {}
