// Declarative WASI: @wasi_func hosts first (import prefix), then resource shell.
// Coarse DirError stays a plain do error enum (status map in wrappers).
.host_dir_create_at = @wasi_func("filesystem/types/descriptor.create-directory-at", (i32, text) -> result<_,error-code>)
.host_dir_open_at = @wasi_func("filesystem/types/descriptor.open-at", (i32, i32, text, i32, i32) -> result<i32,error-code>)
.host_dir_remove_at = @wasi_func("filesystem/types/descriptor.remove-directory-at", (i32, text) -> result<_,error-code>)
.host_dir_drop = @wasi_func("filesystem/types/descriptor.drop", (i32) -> nil)
// G6.1 A: list-of-tuple resource; public wraps Dir.
.host_preopens = @wasi_func("filesystem/preopens/get-directories", () -> list<tuple<i32,text>>)

Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

DirError error = DirOpenFailed | DirReadFailed | DirCreateFailed | DirRemoveFailed | DirClosed

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
        dir Dir = Dir{id = @as(i64, descriptor)}
        return dir
    }
    return DirOpenFailed
}

close_dir(dir Dir) -> nil {
    host_dir_drop(@as(i32, dir_id(dir)))
    return
}

create_dir_at(parent Dir, path text) -> DirError | nil {
    status i32 = 0
    _, status = host_dir_create_at(@as(i32, dir_id(parent)), path)
    return dir_status_to_error(status, DirCreateFailed)
}

open_dir_at(parent Dir, path text) -> Dir | DirError {
    path_flags i32 = 0
    open_flags i32 = 2
    descriptor_flags i32 = 0
    descriptor i32 = 0
    status i32 = 0
    descriptor, status = host_dir_open_at(@as(i32, dir_id(parent)), path_flags, path, open_flags, descriptor_flags)
    return dir_status_to_open_result(descriptor, status)
}

remove_dir_at(parent Dir, path text) -> DirError | nil {
    status i32 = 0
    _, status = host_dir_remove_at(@as(i32, dir_id(parent)), path)
    return dir_status_to_error(status, DirRemoveFailed)
}

is_dir_closed(err DirError) -> bool {
    return @eq(err, DirClosed)
}

/// G6.1 A: public preopens API — list of (Dir, guest path text).
/// Ownership: caller must `close_dir` each Dir; empty list is success (no preopens).
preopen_directories() -> [Tuple<Dir, text>] {
    raw [Tuple<i32, text>] = host_preopens()
    out [Tuple<Dir, text>] = .{}
    i usize = 0
    loop {
        if @ge(i, @len(raw)) break
        pair Tuple<i32, text> = @get(raw, i)
        fd i32 = @get(pair, 0)
        path text = @get(pair, 1)
        dir Dir = Dir{id = @as(i64, fd)}
        item Tuple<Dir, text> = Tuple<Dir, text>{dir, path}
        out = @put(out, item)
        i = @add(i, 1)
    }
    return out
}
