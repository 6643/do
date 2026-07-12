// P3: preopens host returns list of (Dir shell, guest path) as [Tuple<Dir, text>].
// Host first (import prefix); Dir resource after hosts.
// Bracket sugar in @wasi_func result accepted (A+B).
.host_preopens = @wasi_func("filesystem/preopens/get-directories", () -> [Tuple<Dir, text>])
Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

start() {
    xs [Tuple<Dir, text>] = host_preopens()
    _ = xs
    return
}
