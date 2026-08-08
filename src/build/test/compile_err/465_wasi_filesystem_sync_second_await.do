sync_descriptor = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync", (Dir) -> nil | SyncError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
SyncError error = Io | NoEntry

run(file Dir) -> nil {
    pending Future<nil | SyncError> = sync_descriptor(file)
    first nil | SyncError = @await(pending)
    second nil | SyncError = @await(pending)
}

start() {}
