sync_descriptor = @lib("~/test.unsupported_wasi.do", sync_descriptor)

start() {
    sync_descriptor()
    return
}
