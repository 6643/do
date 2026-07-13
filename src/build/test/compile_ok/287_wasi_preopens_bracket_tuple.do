// Bracket list sugar with nested Tuple in @host WASI result (A+B closeout).
.host_preopens = @host("wasi:filesystem/preopens@0.3.0", "get-directories", () -> [Tuple<Dir, text>])
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })

start() {
    xs [Tuple<Dir, text>] = host_preopens()
    _ = xs
    return
}
