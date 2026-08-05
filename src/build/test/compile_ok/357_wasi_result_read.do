.host_read = @host("wasi:filesystem/types@0.3.0", "descriptor.read", (File, u64, u64) -> Result<Tuple<[u8], bool>, FileError>)
File = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
FileError error = FileReadFailed | FileClosed

start() {
    file File = File{id = 1}
    read Result<Tuple<[u8], bool>, FileError> = host_read(file, 0, 16)
    if @is(read, Err) {
        failure FileError = read
    }
}
