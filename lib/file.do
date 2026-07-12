// Declarative WASI: @wasi_func hosts first, then resource shell. Public wrappers unchanged.
.host_file_read = @wasi_func("filesystem/types/descriptor.read", (i32, u64, u64) -> result<tuple<[u8],bool>,error-code>)
.host_file_sync = @wasi_func("filesystem/types/descriptor.sync", (i32) -> result<_,error-code>)
.host_file_write = @wasi_func("filesystem/types/descriptor.write", (i32, [u8], u64) -> result<u64,error-code>)
.host_file_link_at = @wasi_func("filesystem/types/descriptor.link-at", (i32, i32, text, i32, text) -> result<_,error-code>)
.host_file_open_at = @wasi_func("filesystem/types/descriptor.open-at", (i32, i32, text, i32, i32) -> result<i32,error-code>)
.host_file_drop = @wasi_func("filesystem/types/descriptor.drop", (i32) -> nil)

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

.file_status_to_error(code i32, fallback FileError) -> FileError | nil {
    if @eq(code, 0) return nil
    if @eq(code, 1) return FileClosed
    return fallback
}

.file_status_to_open_result(descriptor i32, status i32) -> File | FileError {
    if @eq(status, 0) {
        file File = File{id = @as(i64, descriptor)}
        return file
    }
    return FileOpenFailed
}

close_file(file File) -> nil {
    host_file_drop(@as(i32, file_id(file)))
    return
}

flush_file(file File) -> FileError | nil {
    status i32 = 0
    _, status = host_file_sync(@as(i32, file_id(file)))
    return file_status_to_error(status, FileFlushFailed)
}

read_file(file File, offset usize, size usize) -> [u8], bool, FileError | nil {
    data [u8] = .{}
    done bool = false
    status i32 = 0
    data, done, status = host_file_read(@as(i32, file_id(file)), @as(u64, size), @as(u64, offset))
    return data, done, file_status_to_error(status, FileReadFailed)
}

write_file(file File, data [u8], offset usize) -> FileError | nil {
    written u64 = 0
    status i32 = 0
    written, status = host_file_write(@as(i32, file_id(file)), data, @as(u64, offset))
    return file_status_to_error(status, FileWriteFailed)
}

link_file(old_file File, old_path text, new_file File, new_path text) -> FileError | nil {
    path_flags i32 = 0
    status i32 = 0
    _, status = host_file_link_at(@as(i32, file_id(old_file)), path_flags, old_path, @as(i32, file_id(new_file)), new_path)
    return file_status_to_error(status, FileLinkFailed)
}

open_file_at(dir File, path text) -> File | FileError {
    path_flags i32 = 0
    open_flags i32 = 0
    descriptor_flags i32 = 0
    descriptor i32 = 0
    status i32 = 0
    descriptor, status = host_file_open_at(@as(i32, file_id(dir)), path_flags, path, open_flags, descriptor_flags)
    return file_status_to_open_result(descriptor, status)
}

is_file_closed(err FileError) -> bool {
    return @eq(err, FileClosed)
}
