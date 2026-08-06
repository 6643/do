completion = @lib("./wit/do_generic_async_scalar_i64_probe__host__probe.do", completion)

run() -> nil {
    ready Future<i64> = completion()
    value i64 = @await(ready)
    pending Future<i64> = completion()
    @cancel(pending)
}

start() {}
