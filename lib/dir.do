// Declarative WASI: @wasi_func hosts first (import prefix), then resource shell.
// Coarse DirError stays a plain do error enum (status map in wrappers).
// Hosts use Ok|Err / resource params where Task 1–3 enable.
.host_dir_create_at = @wasi_func("filesystem/types/descriptor.create-directory-at", (Dir, text) -> nil | i32)
.host_dir_open_at = @wasi_func("filesystem/types/descriptor.open-at", (Dir, i32, text, i32, i32) -> Dir | i32)
.host_dir_remove_at = @wasi_func("filesystem/types/descriptor.remove-directory-at", (Dir, text) -> nil | i32)
.host_dir_drop = @wasi_func("filesystem/types/descriptor.drop", (Dir) -> nil)
// P3: host builds Dir shells in list-of-tuple pack (no guest i32 remap loop).
// Bracket sugar `[Tuple<Dir,text>]` is not yet valid in @wasi_func result; list form accepted.
.host_preopens = @wasi_func("filesystem/preopens/get-directories", () -> list<tuple<Dir, text>>)

Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

DirError error = DirOpenFailed | DirReadFailed | DirCreateFailed | DirRemoveFailed | DirClosed

.dir_id(dir Dir) -> i64 {
    return @get(dir, .id)
}

// status from nil|i32 err arm is error-code+1 (never 0); 1 => closed.
.dir_status_to_error(code i32, fallback DirError) -> DirError | nil {
    if @eq(code, 0) return nil
    if @eq(code, 1) return DirClosed
    return fallback
}

close_dir(dir Dir) -> nil {
    host_dir_drop(dir)
    return
}

create_dir_at(parent Dir, path text) -> DirError | nil {
    s nil | i32 = host_dir_create_at(parent, path)
    if @eq(s, nil) return nil
    return dir_status_to_error(s, DirCreateFailed)
}

open_dir_at(parent Dir, path text) -> Dir | DirError {
    r Dir | i32 = host_dir_open_at(parent, 0, path, 2, 0)
    if @is(r, Dir) return r
    return DirOpenFailed
}

remove_dir_at(parent Dir, path text) -> DirError | nil {
    s nil | i32 = host_dir_remove_at(parent, path)
    if @eq(s, nil) return nil
    return dir_status_to_error(s, DirRemoveFailed)
}

is_dir_closed(err DirError) -> bool {
    return @eq(err, DirClosed)
}

/// Preopens API — list of (Dir, guest path text).
/// Ownership: caller must `close_dir` each Dir; empty list is success (no preopens).
preopen_directories() -> [Tuple<Dir, text>] {
    return host_preopens()
}
