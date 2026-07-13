// Net address smoke + G6.3 scheme B type imports (no true host I/O).
SocketAddr = @lib("net.do", SocketAddr)
socket_addr_v4 = @lib("net.do", socket_addr_v4)
port = @lib("net.do", port)
Ipv4SocketAddress = @lib("net.do", Ipv4SocketAddress)
ipv4_socket_address = @lib("net.do", ipv4_socket_address)
TcpSocket = @lib("tcp.do", TcpSocket)
UdpSocket = @lib("udp.do", UdpSocket)
TcpError = @lib("tcp.do", TcpError)
UdpError = @lib("udp.do", UdpError)

test "net socket smoke" {
    addr SocketAddr = socket_addr_v4(127, 0, 0, 1, 8080)
    p u16 = port(addr)
    if @eq(p, 8080) return
    a Ipv4SocketAddress = ipv4_socket_address(10, 0, 0, 1, 9)
    _ = a
}
