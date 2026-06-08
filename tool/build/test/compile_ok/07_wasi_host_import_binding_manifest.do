host_file_sync = @wasi("filesystem/types/descriptor.sync", (descriptor) -> result<_, error-code>)
host_stream_read = @wasi("io/streams/input-stream.read", (input-stream, u64) -> result<list<u8>, stream-error>)

start() {
    return
}
