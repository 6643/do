SocketAddr = @lib("net.do", SocketAddr)
socket_addr_v4 = @lib("net.do", socket_addr_v4)
is_v4 = @lib("net.do", is_v4)
TcpListener = @lib("tcp.do", TcpListener)
UdpSocket = @lib("udp.do", UdpSocket)
TcpError = @lib("tcp.do", TcpError)
UdpError = @lib("udp.do", UdpError)

test "net socket smoke" {
    addr SocketAddr = socket_addr_v4(127, 0, 0, 1, 8080)
    if is_v4(addr) return
}
