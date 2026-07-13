// Declarative @host + @wasi_resource / @wasi_record (do-side host surface).
.host_now = @host("wasi:clocks/system-clock@0.3.0", "now", () -> Datetime)
.host_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (i32) -> nil)

Datetime = @wasi_record("clocks/wall-clock/datetime", {
    seconds i64
    nanoseconds u32
})

Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

start() {
    t Datetime = host_now()
    d Dir = Dir{id = 0}
    host_drop(@as(i32, @get(d, .id)))
    _ = t
}
