read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
DirectoryEntry = @wasi_record("filesystem/types/directory-entry", { .type i32, .name text })
DirectoryError error = Io | NoEntry | NotDirectory

run_bounded(dir Dir) -> nil {
    handles Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>> = read_directory(dir)
    reader Stream<DirectoryEntry> = @get(handles, 0)
    completion Future<Result<nil, DirectoryError>> = @get(handles, 1)
    pending_1 Future<Result<DirectoryEntry, nil>> = @next(reader)
    entry_1 Result<DirectoryEntry, nil> = @await(pending_1)
    _ = entry_1
    pending_2 Future<Result<DirectoryEntry, nil>> = @next(reader)
    entry_2 Result<DirectoryEntry, nil> = @await(pending_2)
    _ = entry_2
    pending_3 Future<Result<DirectoryEntry, nil>> = @next(reader)
    entry_3 Result<DirectoryEntry, nil> = @await(pending_3)
    _ = entry_3
    completed Result<nil, DirectoryError> = @await(completion)
    _ = completed
    return
}

start() {}
