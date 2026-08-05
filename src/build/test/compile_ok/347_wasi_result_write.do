.host_write = @host("wasi:filesystem/types@0.3.0", "descriptor.write", (File, [u8], u64) -> Result<u64, FileError>)
File = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
FileError error = FileWriteFailed | FileClosed

start() {
    file File = File{id = 1}
    data [u8] = .{1}
    wrote Result<u64, FileError> = host_write(file, data, 0)
    if @is(wrote, Ok) {
        count u64 = wrote
    } else {
        failure FileError = wrote
    }
}
