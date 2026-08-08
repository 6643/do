cli_run = @host_async_func("wasi:cli@0.3.0", "run.run", () -> Result<nil, nil>)

run() -> Result<nil, nil> {
    pending Future<Result<nil, nil>> = cli_run()
    replied Result<nil, nil> = @await(pending)
    if @is(replied, Ok) {
        return Err()
    }
    return Ok()
}

start() {}
