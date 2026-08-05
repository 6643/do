result_run = @host_func("do:result-probe@0.1.0", "run", (i32) -> Result<i32, i32>)

async cancel_result(value i32) -> nil {
    pending Future<Result<i32, i32>> = result_run(value)
    @cancel(pending)
}

start() {}
