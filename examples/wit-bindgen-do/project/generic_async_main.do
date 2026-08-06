work = @lib("./wit/do_generic_async_runtime_probe__host__probe.do", work)

run() -> nil {
    ready Future<nil> = work()
    @await(ready)
    middle Future<nil> = work()
    @await(middle)
    pending Future<nil> = work()
    @cancel(pending)
}
