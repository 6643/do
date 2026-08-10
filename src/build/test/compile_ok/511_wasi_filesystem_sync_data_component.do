sync_data_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync-data", (Dir) -> nil | SyncDataError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
SyncDataError error = Io | NoEntry

run(file Dir) -> nil {
    pending Future<nil | SyncDataError> = sync_data_descriptor(file)
    result nil | SyncDataError = @await(pending)
}

start() {}
