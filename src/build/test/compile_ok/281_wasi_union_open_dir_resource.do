// Prefer Dir|i32 open-at (skip ambiguous i32|i32 — @is cannot distinguish).
// Host first (import prefix); Dir resource after hosts.
.host_open = @wasi_func("filesystem/types/descriptor.open-at", (Dir, i32, text, i32, i32) -> Dir | i32)
Dir = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})
start() {
    p Dir = Dir{id = 1}
    r Dir | i32 = host_open(p, 0, "x", 2, 0)
    _ = r
    return
}
