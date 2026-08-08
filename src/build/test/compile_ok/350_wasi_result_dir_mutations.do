.host_create = @host_func("wasi:filesystem/types@0.3.0", "descriptor.create-directory-at", (Dir, text) -> Result<nil, DirError>)
.host_remove = @host_func("wasi:filesystem/types@0.3.0", "descriptor.remove-directory-at", (Dir, text) -> Result<nil, DirError>)
Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
DirError error = DirCreateFailed | DirRemoveFailed | DirClosed

start() {
    dir Dir = Dir{id = 1}
    created Result<nil, DirError> = host_create(dir, "new")
    if @is(created, Err) {
        create_failure DirError = created
    }
    removed Result<nil, DirError> = host_remove(dir, "new")
    if @is(removed, Err) {
        remove_failure DirError = removed
    }
}
