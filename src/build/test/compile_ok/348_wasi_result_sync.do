.host_sync = @host_func("wasi:filesystem/types@0.3.0", "descriptor.sync", (File) -> Result<nil, FileError>)
File = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
FileError error = FileFlushFailed | FileClosed

start() {
    file File = File{id = 1}
    synced Result<nil, FileError> = host_sync(file)
    if @is(synced, Ok) {
        return
    }
    failure FileError = synced
}
