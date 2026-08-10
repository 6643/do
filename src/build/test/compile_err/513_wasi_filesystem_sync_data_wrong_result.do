sync_data_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync-data", (Dir) -> WrongType | SyncDataError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
WrongType = Done | Other
SyncDataError error = Io | NoEntry

run(file Dir) -> WrongType | SyncDataError {
    pending Future<WrongType | SyncDataError> = sync_data_descriptor(file)
    result WrongType | SyncDataError = @await(pending)
}

start() {}
