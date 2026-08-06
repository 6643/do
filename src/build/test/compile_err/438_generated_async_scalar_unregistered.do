completion = @host("do:unregistered-async-scalar-probe/host@0.1.0", "completion", () -> Future<u32>)

run() -> nil {
    ready Future<u32> = completion()
    value u32 = @await(ready)
    pending Future<u32> = completion()
    @cancel(pending)
}

start() {}
