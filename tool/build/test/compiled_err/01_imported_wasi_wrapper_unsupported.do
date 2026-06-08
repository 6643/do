sync_descriptor = @lib("~/test.unsupported_wasi.do", sync_descriptor)

test "compiled imported wasi wrapper unsupported" {
    sync_descriptor()
    return
}
