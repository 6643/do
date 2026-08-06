completion = @host("do:generic-async-scalar-probe/host@0.1.0", "completion", () -> Future<i64>)

run() -> nil {
    ready Future<i64> = completion()
    value i64 = @await(ready)
    pending Future<i64> = completion()
    @cancel(pending)
}

start() {}
