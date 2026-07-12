// Single-line @wasi_resource field body must collect `.id` (skeptic repro).
.host_now = @wasi_func("clocks/system-clock/now", () -> Datetime)
.host_drop = @wasi_func("filesystem/types/descriptor.drop", (i32) -> nil)

Datetime = @wasi_record("clocks/wall-clock/datetime", {
    seconds i64
    nanoseconds u32
})
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })

start() {
    t Datetime = host_now()
    d Dir = Dir{id = 0}
    host_drop(@as(i32, @get(d, .id)))
    _ = t
}
