host_file_sync = @host("wasi:filesystem/types@0.3.0", "descriptor.sync", (descriptor) -> Result<nil, FileError>)
host_stream_read = @host("wasi:io/streams@0.3.0", "input-stream.read", (input-stream, u64) -> Result<[u8], StreamError>)

FileError error = FileClosed
StreamError error = StreamClosed

start() {
    return
}
