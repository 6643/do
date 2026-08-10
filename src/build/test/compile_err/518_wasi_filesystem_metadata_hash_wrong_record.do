metadata_hash = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.metadata-hash", (Dir) -> MetadataHash | HashError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
MetadataHash = @wasi_record("filesystem/types/metadata-hash-value", { upper u64, lower u64 })
HashError error = Io | NoEntry

run(file Dir) -> MetadataHash | HashError {
    pending Future<MetadataHash | HashError> = metadata_hash(file)
    return @await(pending)
}

start() {}
