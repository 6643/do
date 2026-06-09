.host_dir_create_at = @wasi("filesystem/types/descriptor.create-directory-at", (descriptor, text) -> result<_,error-code>)
.host_dir_open_at = @wasi("filesystem/types/descriptor.open-at", (descriptor, path-flags, text, open-flags, descriptor-flags) -> result<descriptor,error-code>)
.host_dir_remove_at = @wasi("filesystem/types/descriptor.remove-directory-at", (descriptor, text) -> result<_,error-code>)
.host_dir_drop = @wasi("filesystem/types/descriptor.drop", (descriptor) -> nil)

DirError error = DirOpenFailed | DirReadFailed | DirCreateFailed | DirRemoveFailed | DirClosed

Dir {
    .id i64
}

.dir_id(dir Dir) -> i64 {
    return @get(dir, .id)
}

.dir_status_to_error(code i32, fallback DirError) -> DirError | nil {
    if @eq(code, 0) return nil
    if @eq(code, 1) return DirClosed
    return fallback
}

.dir_status_to_open_result(descriptor i32, status i32) -> Dir | DirError {
    if @eq(status, 0) {
        dir Dir = Dir{id = @to_i64(descriptor)}
        return dir
    }
    return DirOpenFailed
}

close_dir(dir Dir) -> DirError | nil {
    host_dir_drop(@to_i32(dir_id(dir)))
    return nil
}

create_dir_at(parent Dir, path text) -> DirError | nil {
    status i32 = 0
    _, status = host_dir_create_at(@to_i32(dir_id(parent)), path)
    return dir_status_to_error(status, DirCreateFailed)
}

open_dir_at(parent Dir, path text) -> Dir | DirError {
    descriptor i32 = 0
    status i32 = 0
    descriptor, status = host_dir_open_at(@to_i32(dir_id(parent)), 0, path, 2, 0)
    return dir_status_to_open_result(descriptor, status)
}

remove_dir_at(parent Dir, path text) -> DirError | nil {
    status i32 = 0
    _, status = host_dir_remove_at(@to_i32(dir_id(parent)), path)
    return dir_status_to_error(status, DirRemoveFailed)
}

is_dir_closed(err DirError) -> bool {
    return @eq(err, DirClosed)
}
