.host_link = @host_func("wasi:filesystem/types@0.3.0", "descriptor.link-at", (File, i32, text, File, text) -> Result<nil, FileError>)
File = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
FileError error = FileLinkFailed | FileClosed

start() {
    file File = File{id = 1}
    linked Result<nil, FileError> = host_link(file, 0, "old", file, "new")
    if @is(linked, Ok) {
        return
    }
    failure FileError = linked
}
