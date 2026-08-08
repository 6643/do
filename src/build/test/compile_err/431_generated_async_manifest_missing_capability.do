work = @lib("./wit/missing/do_generic_async_runtime_probe__host__probe.do", work)

run() -> nil {
    first Future<nil> = work()
    @await(first)
    second Future<nil> = work()
    @await(second)
    third Future<nil> = work()
    @cancel(third)
}

start() {}
