.host_preopens = @host("wasi:filesystem/preopens@0.3.0", "get-directories", () -> [Tuple<Dir, text>])
.host_open = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at", (Dir, i32, text, i32, i32) -> Result<File, FileError>)
.host_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (File) -> nil)

Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

File = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

FileError error = FileOpenFailed | FileFlushFailed

start() {
    roots [Tuple<Dir, text>] = host_preopens()
    dir Dir = @get(roots, 0, 0)
    opened Result<File, FileError> = host_open(dir, 0, "probe", 0, 0)
    if @is(opened, Ok) {
        file File = opened
    }
    host_drop(dir)
}
