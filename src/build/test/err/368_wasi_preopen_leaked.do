.host_preopens = @host("wasi:filesystem/preopens@0.3.0", "get-directories", () -> [Tuple<Dir, text>])

Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

start() {
    roots [Tuple<Dir, text>] = host_preopens()
    dir Dir = @get(roots, 0, 0)
}
