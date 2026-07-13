// link-at unit fallible: exclusive union nil|i32; multi-lhs status binding remains lowerable.
host_file_link_at = @host("wasi:filesystem/types@0.3.0", "descriptor.link-at", (i32, i32, text, i32, text) -> nil | i32)

start() {
    status i32 = 0
    _, status = host_file_link_at(1, 0, "old.txt", 2, "new.txt")
    return
}
