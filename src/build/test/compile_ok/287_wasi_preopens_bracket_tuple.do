// Bracket list sugar with nested Tuple in @wasi_func result (A+B closeout).
.host_preopens = @wasi_func("filesystem/preopens/get-directories", () -> [Tuple<Dir, text>])
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })

start() {
    xs [Tuple<Dir, text>] = host_preopens()
    _ = xs
    return
}
