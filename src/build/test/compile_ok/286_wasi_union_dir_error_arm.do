// P4: host open-at Err arm as coarse DirError (not raw status i32).
// Hosts first (import prefix); resource + error enum after.
.host_open = @wasi_func("filesystem/types/descriptor.open-at", (Dir, i32, text, i32, i32) -> Dir | DirError)
Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
DirError error = DirOpenFailed | DirReadFailed | DirCreateFailed | DirRemoveFailed | DirClosed
start() {
    p Dir = Dir{id = 1}
    r Dir | DirError = host_open(p, 0, "x", 2, 0)
    _ = r
    return
}
