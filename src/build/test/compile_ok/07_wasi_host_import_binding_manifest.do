host_file_sync = @wasi_func("filesystem/types/descriptor.sync", (descriptor) -> result<_, error-code>)
host_stream_read = @wasi_func("io/streams/input-stream.read", (input-stream, u64) -> result<list<u8>, stream-error>)

start() {
    return
}
