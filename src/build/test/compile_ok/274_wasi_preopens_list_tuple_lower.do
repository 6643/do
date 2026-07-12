// G6.1 / P3: preopens get-directories lowers to [Tuple<Dir,text>] storage pack.
// Bracket sugar valid on @wasi_func result (A+B).
.host_preopens = @wasi_func("filesystem/preopens/get-directories", () -> [Tuple<Dir, text>])
Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

start() {
    roots [Tuple<Dir, text>] = host_preopens()
    _ = roots
}
