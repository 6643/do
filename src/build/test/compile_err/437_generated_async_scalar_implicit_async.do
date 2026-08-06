completion() -> u32 {
    return 1
}

run() -> nil {
    ready Future<u32> = @async(completion())
    value u32 = @await(ready)
    pending Future<u32> = @async(completion())
    @cancel(pending)
}

start() {}
