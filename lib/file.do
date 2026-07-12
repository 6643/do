// Declarative WASI: @wasi_func hosts first, then resource shell. Public wrappers unchanged.
// Hosts use Ok|Err / File params where Task 1–3 enable; read tuple-union not ready (multi-lhs).
.host_file_read = @wasi_func("filesystem/types/descriptor.read", (File, u64, u64) -> result<tuple<[u8],bool>,error-code>)
.host_file_sync = @wasi_func("filesystem/types/descriptor.sync", (File) -> nil | i32)
.host_file_write = @wasi_func("filesystem/types/descriptor.write", (File, [u8], u64) -> u64 | i32)
.host_file_link_at = @wasi_func("filesystem/types/descriptor.link-at", (File, i32, text, File, text) -> nil | i32)
.host_file_open_at = @wasi_func("filesystem/types/descriptor.open-at", (File, i32, text, i32, i32) -> File | i32)
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

// status from nil|i32 / u64|i32 err arm is error-code+1 (never 0); 1 => closed.
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
    s nil | i32 = host_file_sync(file)
    if @eq(s, nil) return nil
    return file_status_to_error(s, FileFlushFailed)
}

// Read still multi-lhs until Tuple-in-union lands.
read_file(file File, offset usize, size usize) -> [u8], bool, FileError | nil {
    data [u8] = .{}
    done bool = false
    status i32 = 0
    data, done, status = host_file_read(file, @as(u64, size), @as(u64, offset))
    return data, done, file_status_to_error(status, FileReadFailed)
}

write_file(file File, data [u8], offset usize) -> FileError | nil {
    n u64 | i32 = host_file_write(file, data, @as(u64, offset))
    if @is(n, u64) return nil
    return file_status_to_error(n, FileWriteFailed)
}

link_file(old_file File, old_path text, new_file File, new_path text) -> FileError | nil {
    s nil | i32 = host_file_link_at(old_file, 0, old_path, new_file, new_path)
    if @eq(s, nil) return nil
    return file_status_to_error(s, FileLinkFailed)
}

open_file_at(dir File, path text) -> File | FileError {
    r File | i32 = host_file_open_at(dir, 0, path, 0, 0)
    if @is(r, File) return r
    return FileOpenFailed
}

is_file_closed(err FileError) -> bool {
    return @eq(err, FileClosed)
}
