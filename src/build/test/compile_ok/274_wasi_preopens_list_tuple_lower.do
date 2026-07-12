// G6.1 A: preopens get-directories lowers to [Tuple<i32,text>].
.host_preopens = @wasi_func("filesystem/preopens/get-directories", () -> list<tuple<descriptor,text>>)

start() {
    roots [Tuple<i32, text>] = host_preopens()
    _ = roots
}
