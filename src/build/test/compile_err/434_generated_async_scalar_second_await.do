completion = @host_func("do:generic-async-scalar-probe/host@0.1.0", "completion", () -> Future<u32>)

run() -> nil {
    first Future<u32> = completion()
    first_value u32 = @await(first)
    second Future<u32> = completion()
    second_value u32 = @await(second)
    pending Future<u32> = completion()
    @cancel(pending)
}

start() {}
