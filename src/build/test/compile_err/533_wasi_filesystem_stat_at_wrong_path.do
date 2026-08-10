stat_at_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.stat-at", (Dir, u32, u32) -> DescriptorStat | StatError)
Datetime = @wasi_record("clocks/wall-clock/datetime", { seconds i64, nanoseconds u32 })
DescriptorStat = @wasi_record("filesystem/types/descriptor-stat", { .type i32, link_count u64, size u64, data_access_timestamp option<Datetime>, data_modification_timestamp option<Datetime>, status_change_timestamp option<Datetime> })
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
StatError error = Io | NoEntry

run(file Dir, path_flags u32, path u32) -> DescriptorStat | StatError {
    pending Future<DescriptorStat | StatError> = stat_at_descriptor(file, path_flags, path)
    return @await(pending)
}

start() {}
