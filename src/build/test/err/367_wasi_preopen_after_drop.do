.host_preopens = @host_func("wasi:filesystem/preopens@0.3.0", "get-directories", () -> [Tuple<Dir, text>])
.host_sync = @host_func("wasi:filesystem/types@0.3.0", "descriptor.sync", (Dir) -> Result<nil, FileError>)
.host_drop = @host_func("wasi:filesystem/types@0.3.0", "descriptor.drop", (Dir) -> nil)

Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

FileError error = FileFlushFailed

start() {
    roots [Tuple<Dir, text>] = host_preopens()
    dir Dir = @get(roots, 0, 0)
    host_drop(dir)
    host_sync(dir)
}
