host_file_write = @wasi/filesystem/types/descriptor.write(descriptor, list<u8>, filesize) -> result<filesize, error-code>
host_file_read = @wasi/filesystem/types/descriptor.read(descriptor, filesize, filesize) -> result<tuple<list<u8>, bool>, error-code>
host_file_sync = @wasi/filesystem/types/descriptor.sync(descriptor) -> result<_, error-code>
host_file_link = @wasi/filesystem/types/descriptor.link-at(descriptor, path-flags, string, borrow<descriptor>, string) -> result<_, error-code>
now = @wasi/clocks/wall-clock/now() -> u64

test "wasi host import wit types" {
    return
}
