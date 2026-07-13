# Design: G6.3 Sockets Scheme B

**Status:** Implemented (session 2026-07-13)  
**Scope:** WASI sockets `tcp/udp-socket.create` + `bind` mapping and lowering; stdlib net/tcp/udp surface.  
**Non-goals:** G6.2 read-directory/async; listen/connect/accept/stream I/O; true host smoke (D2); HTTP.

## Goal

Unblock G6.3 with **scheme B**: dual concrete address structs, ordinary **function overloads** for public API, **payload enum** as the named total address type for host, **resource shells** for sockets, coarse error enums, value semantics (no pointers/refs).

## Decisions

| Topic | Decision |
|-------|----------|
| Scheme | **B** (not A flat `SocketAddr` pack-only, not C create-only) |
| Resource | `TcpSocket` / `UdpSocket` = `@wasi_resource("sockets/types/tcp-socket" \| "…/udp-socket", { .id i64 })` |
| Address public | `Ipv4SocketAddress` / `Ipv6SocketAddress` structs (pure scalar fields) |
| Address total | Payload enum `IpSocketAddress = V4(Ipv4SocketAddress) \| V6(Ipv6SocketAddress)` |
| Public bind API | Overloads: `bind_tcp(sock, Ipv4…)` / `bind_tcp(sock, Ipv6…)` (+ optional total-type overload) |
| Public create API | `create_tcp_v4()` / `create_tcp_v6()` (or overload on family); wrappers call single host |
| Host import | **One** `@host` alias per target; **no** host overload |
| Host create | `(u8) -> TcpSocket \| TcpError` (family 4/6); codegen maps to WIT `ip-address-family` disc |
| Host bind | `(TcpSocket, IpSocketAddress) -> TcpError \| nil` |
| Errors | Coarse `TcpError` / `UdpError` (E1); status→`*HostFailure` / `*UnsupportedAddress` |
| Lifecycle | Explicit `close_tcp` / `close_udp` → resource-drop → `nil`; **not** ARC auto-close |
| Value semantics | Addresses and sockets are **values**; no out-params; bind does not mutate addr |
| Legacy `SocketAddr` | Keep in `lib/net.do` for smoke; add conversion helpers optional; new APIs prefer B types |

## Mapping (do → WIT)

| do | WIT |
|----|-----|
| `TcpSocket` / `.id` | `tcp-socket` resource handle |
| `UdpSocket` / `.id` | `udp-socket` resource handle |
| `u8` family `4` / `6` | `ip-address-family` disc `ipv4` / `ipv6` (0 / 1) |
| `IpSocketAddress` / `V4` / `V6` | `ip-socket-address` variant |
| `Ipv4SocketAddress` | `ipv4-socket-address` (port + 4×u8) |
| `Ipv6SocketAddress` | `ipv6-socket-address` (port + hi/lo as 16-byte addr; flow/scope = 0) |
| `TcpSocket \| TcpError` | `result<tcp-socket, error-code>` |
| `TcpError \| nil` | `result<_, error-code>` |

## Core ABI (cm32p2 plan)

Reuse existing strategies:

1. **create** — same result-area shape as `descriptor.open-at` (`result_descriptor_error` / sibling flag `result_socket_error`):  
   core params: `family:i32` + `result_area:i32`; ok stores handle, err stores error-code.
2. **bind** — same unit-error result-area as `descriptor.sync` (`result_unit_error`):  
   core params: `socket:i32` + packed address (see pack) + `result_area:i32`.
3. **drop** — `[resource-drop]tcp-socket` / `udp-socket`, param handle `i32`.

### Address pack (bind)

Guest packs into a fixed scratch at `$__wasi_result_area_base + SOCKET_ADDR_PACK_OFF` (or dedicated global scratch after result area):

```
// disc i32 @0: 0 = ipv4, 1 = ipv6
// ipv4 @4: port u16 LE, pad u16, a u8, b u8, c u8, d u8
// ipv6 @4: port u16 LE, flowinfo u32 (=0), addr[16] from hi/lo BE or LE (document one), scope u32 (=0)
```

Core bind import receives `socket_handle i32`, `addr_ptr i32`, `result_area i32` (3 i32 params + result area may share strategy with existing unit calls). Exact core param string locked in `wasiLowering` + validate shim tests.

**IPv6 field note:** public `Ipv6SocketAddress { .hi u64, .lo u64, .port u16 }` maps 16-byte address as `hi||lo` big-endian octets (document in lowering.md). flow-info/scope-id fixed 0 in v1.

## Stdlib shape

### `lib/net.do`

- Keep existing `SocketAddr` + helpers (compat).
- Add `Ipv4SocketAddress`, `Ipv6SocketAddress`, `IpSocketAddress` payload enum, constructors `ipv4_socket_address` / `ipv6_socket_address`.

### `lib/tcp.do`

```do
// hosts first
.host_tcp_create = @host("wasi:sockets/types@0.3.0", "tcp-socket.create", (u8) -> TcpSocket | TcpError)
.host_tcp_bind = @host("wasi:sockets/types@0.3.0", "tcp-socket.bind", (TcpSocket, IpSocketAddress) -> TcpError | nil)
.host_tcp_drop = @host("wasi:sockets/types@0.3.0", "tcp-socket.drop", (TcpSocket) -> nil)

TcpSocket = @wasi_resource("sockets/types/tcp-socket", { .id i64 })
TcpError error = TcpClosed | TcpUnsupportedAddress | TcpHostFailure

create_tcp_v4() -> TcpSocket | TcpError
create_tcp_v6() -> TcpSocket | TcpError
bind_tcp(sock TcpSocket, addr Ipv4SocketAddress) -> TcpError | nil
bind_tcp(sock TcpSocket, addr Ipv6SocketAddress) -> TcpError | nil
bind_tcp(sock TcpSocket, addr IpSocketAddress) -> TcpError | nil
close_tcp(sock TcpSocket) -> nil
```

### `lib/udp.do`

Symmetric to tcp with `Udp*` names and udp-socket targets.

## Compiler touch points

| Area | Change |
|------|--------|
| `sema_import.zig` known table | do_params/do_result for create/bind/drop + resource sugar |
| `component_metadata_wat.zig` `wasiLowering` | lowerable create/bind/drop entries |
| `gen_wasi_emit.zig` | create call + union value; bind pack + unit union; drop handle |
| `validate_wasi_bind_manifest.mjs` | shim plans for socket signatures |
| `test_wasi_bind_manifest_tool.mjs` | update sockets from unsupported → lowerable |
| docs | `wasi_p3_lowering.md`, `pending_blocked.md`, `start_here`, `roadmap_status` |

## Fixtures (TDD order)

1. `compile_ok/291_wasi_tcp_create_union.do` — host create + resource + union bind  
2. `compile_ok/292_wasi_tcp_bind_payload_addr.do` — bind with `V4(...)`  
3. `compile_ok/293_imported_tcp_create_bind_wrapper.do` — import public wrappers  
4. UDP twins or combined as needed  
5. Update manifest tool expectations for sockets lowerable  
6. `ok/` smoke for net constructors if public API changes

## Success criteria

- Registry targets create/bind/drop for tcp+udp mark **lowerable** (not unsupported).  
- Stdlib exposes B API; no raw WIT types public.  
- `./src/build/test/run_tests.sh` → `fail=0`.  
- G6.3 removed from **blocked** in `pending_blocked.md` (G6.2 remains).  
- No true host socket smoke required for closeout.

## Out of scope (explicit)

- listen / connect / accept / send / recv  
- Async / Future  
- Fine `@wasi_enum` error-code table  
- Replacing or deleting legacy `SocketAddr` in one step  
