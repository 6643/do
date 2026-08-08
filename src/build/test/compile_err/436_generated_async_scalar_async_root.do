completion = @host_func("do:generic-async-scalar-probe/host@0.1.0", "completion", () -> Future<u32>)

async run() -> nil {
    ready Future<u32> = completion()
    value u32 = @await(ready)
    pending Future<u32> = completion()
    @cancel(pending)
}

start() {}
