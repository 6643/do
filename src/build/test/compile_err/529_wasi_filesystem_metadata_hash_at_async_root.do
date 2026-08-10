metadata_hash_at = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.metadata-hash-at", (Dir, u32, text) -> MetadataHash | HashError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
MetadataHash = @wasi_record("filesystem/types/metadata-hash-value", { lower u64, upper u64 })
HashError error = Io | NoEntry

async run(file Dir, path_flags u32, path text) -> MetadataHash | HashError {
    pending Future<MetadataHash | HashError> = metadata_hash_at(file, path_flags, path)
    return @await(pending)
}

start() {}
