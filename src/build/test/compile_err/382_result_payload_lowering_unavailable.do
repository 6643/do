result_run = @host_async_func("do:result-probe@0.1.0", "run", (i32) -> Result<i32, i32>)

run(value i32) -> Result<i32, i32> {
    pending Future<Result<i32, i32>> = result_run(value)
    return @await(pending)
}

start() {}
