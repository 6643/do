work() -> nil { return }
run() -> nil {
    stream Stream<u8> = @async(work())
    @await(stream)
    pending Future<nil> = @async(work())
    @cancel(pending)
}
start() {}
