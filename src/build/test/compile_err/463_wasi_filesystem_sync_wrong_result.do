sync_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync", (Dir) -> WrongType | SyncError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
WrongType = Done | Other
SyncError error = Io | NoEntry

run(file Dir) -> WrongType | SyncError {
    pending Future<WrongType | SyncError> = sync_descriptor(file)
    result WrongType | SyncError = @await(pending)
}

start() {}
