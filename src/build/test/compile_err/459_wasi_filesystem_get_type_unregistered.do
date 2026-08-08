get_type = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.not-registered", (Dir) -> DescriptorType | FileError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
DescriptorType = Unknown | Directory | RegularFile
FileError error = Io | NoEntry

run(directory Dir) -> DescriptorType | FileError {
    pending Future<DescriptorType | FileError> = get_type(directory)
    return @await(pending)
}

start() {}
