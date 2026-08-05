probe_read = @host_func("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)

ProbeError error = Io | IllegalByteSequence | Pipe

start() {}
