.host_open = @host("wasi:filesystem/types@0.3.0", "descriptor.open-at", (Dir, i32, text, i32, i32) -> Result<Dir, bool>)
Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
