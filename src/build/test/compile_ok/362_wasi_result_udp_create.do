.host_udp_create = @host("wasi:sockets/types@0.3.0", "udp-socket.create", (u8) -> Result<UdpSocket, UdpError>)
UdpSocket = @wasi_resource("sockets/types/udp-socket", {
    .id i64
})
UdpError error = UdpClosed | UdpHostFailure

start() {
    created Result<UdpSocket, UdpError> = host_udp_create(4)
    if @is(created, Err) {
        failure UdpError = created
    }
}
