// Declarative WASI: @wasi_func hosts first, then resource shell. Public wrappers unchanged.
// P4: host Err arms use coarse FileError where public API matches; read stays status i32 for multi-lhs.
.host_file_read = @wasi_func("filesystem/types/descriptor.read", (File, u64, u64) -> Tuple<[u8], bool> | i32)
.host_file_sync = @wasi_func("filesystem/types/descriptor.sync", (File) -> FileError | nil)
.host_file_write = @wasi_func("filesystem/types/descriptor.write", (File, [u8], u64) -> u64 | FileError)
.host_file_link_at = @wasi_func("filesystem/types/descriptor.link-at", (File, i32, text, File, text) -> FileError | nil)
.host_file_open_at = @wasi_func("filesystem/types/descriptor.open-at", (File, i32, text, i32, i32) -> File | FileError)
.host_file_drop = @wasi_func("filesystem/types/descriptor.drop", (File) -> nil)

File = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

FileError error = FileOpenFailed | FileClosed | FileReadFailed | FileWriteFailed | FileFlushFailed | FileLinkFailed

.file_from_id(id i64) -> File | FileError {
    if @lt(id, 0) return FileOpenFailed
    file File = File{id = id}
    return file
}

.file_id(file File) -> i64 {
    return @get(file, .id)
}

// status from multi-lhs read err arm is error-code+1 (never 0); 1 => closed.
.file_status_to_error(code i32, fallback FileError) -> FileError | nil {
    if @eq(code, 0) return nil
    if @eq(code, 1) return FileClosed
    return fallback
}

close_file(file File) -> nil {
    host_file_drop(file)
    return
}

flush_file(file File) -> FileError | nil {
    return host_file_sync(file)
}

// Host is Tuple<[u8],bool>|i32; multi-lhs still lowers via tuple result-area (stable ARC for return).
read_file(file File, offset usize, size usize) -> [u8], bool, FileError | nil {
    data [u8] = .{}
    done bool = false
    status i32 = 0
    data, done, status = host_file_read(file, @as(u64, size), @as(u64, offset))
    return data, done, file_status_to_error(status, FileReadFailed)
}

// Host returns u64 | FileError; public API is FileError | nil (discard written count on ok).
write_file(file File, data [u8], offset usize) -> FileError | nil {
    n u64 | FileError = host_file_write(file, data, @as(u64, offset))
    if @is(n, u64) return nil
    return n
}

link_file(old_file File, old_path text, new_file File, new_path text) -> FileError | nil {
    return host_file_link_at(old_file, 0, old_path, new_file, new_path)
}

open_file_at(dir File, path text) -> File | FileError {
    return host_file_open_at(dir, 0, path, 0, 0)
}

is_file_closed(err FileError) -> bool {
    return @eq(err, FileClosed)
}
