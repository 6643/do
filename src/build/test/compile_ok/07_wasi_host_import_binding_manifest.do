host_file_sync = @host("wasi:filesystem/types@0.3.0", "descriptor.sync", (descriptor) -> result<_, error-code>)
host_stream_read = @host("wasi:io/streams@0.3.0", "input-stream.read", (input-stream, u64) -> result<list<u8>, stream-error>)

start() {
    return
}
