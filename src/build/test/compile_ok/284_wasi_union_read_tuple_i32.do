// Prefer exclusive union for descriptor.read: ok = Tuple<[u8],bool>, err = status i32.
// Host first (import prefix); File resource after hosts. Host import is single-line (import prefix rule).
.host_file_read = @host("wasi:filesystem/types@0.3.0", "descriptor.read", (File, u64, u64) -> Tuple<[u8], bool> | i32)
File = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
start() {
    f File = File{id = 1}
    r Tuple<[u8], bool> | i32 = host_file_read(f, 0, 64)
    _ = r
    return
}
