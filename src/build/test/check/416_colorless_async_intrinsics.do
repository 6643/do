make() -> i32 {
    return 7
}

run() -> nil {
    ready Future<i32> = @async(make())
    value i32 = @await(ready)
    pending Future<i32> = @async(make())
    @cancel(pending)
    _ = value
}

start() {}
