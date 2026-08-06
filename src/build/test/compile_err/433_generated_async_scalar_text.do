completion = @host("do:generic-async-scalar-probe/host@0.1.0", "completion", () -> Future<text>)

run() -> nil {
    ready Future<text> = completion()
    value text = @await(ready)
    pending Future<text> = completion()
    @cancel(pending)
}

start() {}
