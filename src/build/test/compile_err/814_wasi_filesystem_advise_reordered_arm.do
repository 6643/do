advise_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.advise", (File, u64, u64, Advice) -> nil | AdviseError)
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
Advice u32 = Normal(0) | Random(2) | Sequential(1) | WillNeed(3) | DontNeed(4) | NoReuse(5)
AdviseError error = Io | Invalid | BadDescriptor
run(file File, offset u64, length u64, advice Advice) -> nil | AdviseError { pending Future<nil | AdviseError> = advise_descriptor(file, offset, length, advice) return @await(pending) }
start() {}

