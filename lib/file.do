// Declarative WASI: @host wasi hosts first, then resource shell. Public wrappers unchanged.
// Host result arms use ordinary Do unions where the payload types differ.
.host_file_read = @host("wasi:filesystem/types@0.3.0", "descriptor.read", (File, u64, u64) -> Tuple<[u8], bool> | FileError)
.host_file_sync = @host("wasi:filesystem/types@0.3.0", "descriptor.sync", (File) -> nil | FileError)
.host_file_write = @host("wasi:filesystem/types@0.3.0", "descriptor.write", (File, [u8], u64) -> u64 | FileError)
.host_file_link_at = @host("wasi:filesystem/types@0.3.0", "descriptor.link-at", (File, i32, text, File, text) -> nil | FileError)
.host_file_open_at = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at", (File, i32, text, i32, i32) -> File | FileError)
.host_file_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (File) -> nil)

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

close_file(file File) -> nil {
    host_file_drop(file)
    return
}

flush_file(file File) -> FileError | nil {
    synced nil | FileError = host_file_sync(file)
    if @eq(synced, nil) return nil
    return synced
}

// Host result maps its error-code arm to FileError, then unwraps the successful tuple.
read_file(file File, offset usize, size usize) -> [u8], bool, FileError | nil {
    r Tuple<[u8], bool> | FileError = host_file_read(file, @as(u64, size), @as(u64, offset))
    if @is(r, FileError) {
        empty [u8] = .{}
        return empty, false, r
    }
    t Tuple<[u8], bool> = r
    return @get(t, 0), @get(t, 1), nil
}

// Host returns u64 | FileError; public API discards the successful count.
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
