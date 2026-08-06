completion = @lib("./wit/scalar/do_generic_async_scalar_probe__host__probe.do", completion)

run() -> nil {
    ready Future<u32> = completion()
    value u32 = @await(ready)
    pending Future<u32> = completion()
    @cancel(pending)
}

start() {}
