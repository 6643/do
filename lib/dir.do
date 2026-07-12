// Declarative WASI: @wasi_func hosts first (import prefix), then resource shell.
// P4: host Err arms use coarse DirError (status → *Failed / DirClosed in codegen).
// Hosts use Ok|Err / resource params; open/create/remove match public API for thin forward.
.host_dir_create_at = @wasi_func("filesystem/types/descriptor.create-directory-at", (Dir, text) -> DirError | nil)
.host_dir_open_at = @wasi_func("filesystem/types/descriptor.open-at", (Dir, i32, text, i32, i32) -> Dir | DirError)
.host_dir_remove_at = @wasi_func("filesystem/types/descriptor.remove-directory-at", (Dir, text) -> DirError | nil)
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

close_dir(dir Dir) -> nil {
    host_dir_drop(dir)
    return
}

create_dir_at(parent Dir, path text) -> DirError | nil {
    return host_dir_create_at(parent, path)
}

open_dir_at(parent Dir, path text) -> Dir | DirError {
    return host_dir_open_at(parent, 0, path, 2, 0)
}

remove_dir_at(parent Dir, path text) -> DirError | nil {
    return host_dir_remove_at(parent, path)
}

is_dir_closed(err DirError) -> bool {
    return @eq(err, DirClosed)
}

/// Preopens API — list of (Dir, guest path text).
/// Ownership: caller must `close_dir` each Dir; empty list is success (no preopens).
preopen_directories() -> [Tuple<Dir, text>] {
    return host_preopens()
}
