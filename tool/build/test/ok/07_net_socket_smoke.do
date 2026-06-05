SocketAddr = @net.do/SocketAddr
socket_addr_v4 = @net.do/socket_addr_v4
is_v4 = @net.do/is_v4
TcpListener = @tcp.do/TcpListener
UdpSocket = @udp.do/UdpSocket
TcpError = @tcp.do/TcpError
UdpError = @udp.do/UdpError

test "net socket smoke" {
    addr SocketAddr = socket_addr_v4(127, 0, 0, 1, 8080)
    if not(is_v4(addr)) return
}
