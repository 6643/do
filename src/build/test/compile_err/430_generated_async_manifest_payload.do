work = @lib("./wit/do_generic_async_runtime_probe__host__probe.do", work)

run() -> nil {
    first Future<u32> = work()
    @await(first)
    second Future<nil> = work()
    @await(second)
    third Future<nil> = work()
    @cancel(third)
}

start() {}
