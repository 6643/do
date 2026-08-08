sync_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync", (Dir) -> borrow<Dir> | SyncError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
SyncError error = Io | NoEntry

run(file Dir) -> borrow<Dir> | SyncError {
    pending Future<borrow<Dir> | SyncError> = sync_descriptor(file)
    result borrow<Dir> | SyncError = @await(pending)
}

start() {}
