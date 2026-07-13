// Prefer exclusive union for stream read: ok = [u8] list, err = status i32.
// Host first (import prefix); InputStream resource after hosts.
.host_input_read = @host("wasi:io/streams@0.3.0", "input-stream.read", (InputStream, u64) -> [u8] | i32)
InputStream = @wasi_resource("io/streams/input-stream", {
    .id i64
})
start() {
    s InputStream = InputStream{id = 1}
    r [u8] | i32 = host_input_read(s, 64)
    _ = r
    return
}
