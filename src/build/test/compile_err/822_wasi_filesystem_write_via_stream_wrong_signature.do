write_via_stream = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.write-via-stream", (File, StreamWriter<u32>, u64) -> Result<nil, FileError>)
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
FileError error = Io
