work() -> i32 { return 1 }
run() -> nil {
    pending Future<i32> = @async(work())
    @await(pending)
    other Future<nil> = @async(work())
    @cancel(other)
}
start() {}
