.host_open = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at", (Dir, i32, text, i32, i32) -> Result<Dir, DirError>)
.host_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (Dir) -> nil)
Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
DirError error = DirOpenFailed | DirReadFailed | DirCreateFailed | DirRemoveFailed | DirClosed

start() {
    parent Dir = Dir{id = 1}
    opened Result<Dir, DirError> = host_open(parent, 0, "x", 2, 0)
    if @is(opened, Ok) {
        child Dir = opened
        host_drop(child)
    } else {
        failure DirError = opened
    }
    host_drop(parent)
}
