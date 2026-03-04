{
    key Text,
    WasiIovec{buf_ptr i32, buf_len i32},
    fd_write(i32, WasiIovec, i32, i32) => i32,
} := @("wasi_snapshot_preview1")

test "ffi import mixed items" {
    x = key
    if x return
}
