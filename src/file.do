.host_file_read = @wasi("filesystem/types/descriptor.read", (descriptor, filesize, filesize) -> result<tuple<list<u8>,bool>,error-code>)
.host_file_sync = @wasi("filesystem/types/descriptor.sync", (descriptor) -> result<_, error-code>)
.host_file_write = @wasi("filesystem/types/descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)
.host_file_link_at = @wasi("filesystem/types/descriptor.link-at", (descriptor, path-flags, text, borrow<descriptor>, text) -> result<_, error-code>)
.host_file_open_at = @wasi("filesystem/types/descriptor.open-at", (descriptor, path-flags, text, open-flags, descriptor-flags) -> result<descriptor,error-code>)
.host_file_drop = @wasi("filesystem/types/descriptor.drop", (descriptor) -> nil)

FileError error = FileOpenFailed | FileClosed | FileReadFailed | FileWriteFailed | FileFlushFailed | FileCloseFailed | FileLinkFailed

File {
    .id i64
}

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

close_file(file File) -> FileError | nil {
    host_file_drop(@as(i32, file_id(file)))
    return nil
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
    status i32 = 0
    _, status = host_file_link_at(@as(i32, file_id(old_file)), 0, old_path, @as(i32, file_id(new_file)), new_path)
    return file_status_to_error(status, FileLinkFailed)
}

open_file_at(dir File, path text) -> File | FileError {
    descriptor i32 = 0
    status i32 = 0
    descriptor, status = host_file_open_at(@as(i32, file_id(dir)), 0, path, 0, 0)
    return file_status_to_open_result(descriptor, status)
}

is_file_closed(err FileError) -> bool {
    return @eq(err, FileClosed)
}
