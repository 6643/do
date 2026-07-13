# G6.3 Sockets Scheme B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lower WASI `tcp/udp-socket.create|bind|drop` with scheme B address types and stdlib wrappers; close G6.3 blocked item.

**Architecture:** Reuse open-at result-area for create (`TcpSocket|TcpError`) and unit-error for bind (`TcpError|nil`); pack payload-enum address in guest before bind; resource shells mirror File/Dir.

**Tech Stack:** Zig compiler (`src/build/*`), do stdlib (`lib/net.do`, `lib/tcp.do`, `lib/udp.do`), Node validate scripts, `run_tests.sh`.

## Global Constraints

- Value semantics only; no pointers/refs in source.
- Host imports: one alias, one signature; no host overload.
- Public API: overloads + payload enum; coarse TcpError/UdpError.
- No G6.2 / listen-connect / true host smoke.
- Spec: `docs/superpowers/specs/2026-07-13-g6-3-sockets-scheme-b-design.md`.

---

### Task 1: Known-table + wasiLowering for tcp create/bind/drop

**Files:**
- Modify: `src/build/sema_import.zig` (known WASI rows ~404–407)
- Modify: `src/build/component_metadata_wat.zig` (`WasiLowering`, `wasiLowering`)
- Modify: `doc/wit/wasi_registry.json` if drop missing
- Test: `src/build/test/compile_ok/291_wasi_tcp_create_union.do` (+ `.expect` if needed)

**Interfaces:**
- Produces: known do sugar for create/bind/drop; `wasiLowering` non-null for those targets with flags `result_descriptor_error` (create) / `result_unit_error` (bind) / `resource_drop` (drop).

- [ ] **Step 1: Write failing compile fixture (create only)**

```do
// compile_ok/291_wasi_tcp_create_union.do
.host_tcp_create = @wasi_func("sockets/types/tcp-socket.create", (u8) -> TcpSocket | TcpError)
TcpSocket = @wasi_resource("sockets/types/tcp-socket", {
    .id i64
})
TcpError error = TcpClosed | TcpUnsupportedAddress | TcpHostFailure

start() {
    r TcpSocket | TcpError = host_tcp_create(4)
    _ = r
    return
}
```

- [ ] **Step 2: Run build on fixture — expect fail (unknown do sig or no lowering)**

```bash
cd /home/_/._/do && ./bin/do build src/build/test/compile_ok/291_wasi_tcp_create_union.do -o /tmp/t.wat
```

Expected: error (signature / UnsupportedLowering / NoMatchingCall).

- [ ] **Step 3: Extend known table + wasiLowering**

`sema_import.zig` — replace bare socket rows with:

```zig
.{
    .target = "sockets/types/tcp-socket.create",
    .params = "ip-address-family",
    .result = "result<tcp-socket,error-code>",
    .do_params = "u8",
    .do_result = "TcpSocket|i32",
    .do_result_alt = "TcpSocket|TcpError",
},
.{
    .target = "sockets/types/tcp-socket.bind",
    .params = "tcp-socket,ip-socket-address",
    .result = "result<_,error-code>",
    .do_params = "TcpSocket,IpSocketAddress",
    .do_result = "nil|i32",
    .do_result_alt = "TcpError|nil",
    .do_result_alt2 = "nil|TcpError",
},
.{
    .target = "sockets/types/tcp-socket.drop",
    .params = "tcp-socket",
    .result = "nil",
    .do_params = "TcpSocket",
},
// mirror udp-socket.*
```

`component_metadata_wat.zig` — add before `return null`:

```zig
if (std.mem.eql(u8, import.target, "sockets/types/tcp-socket.create") and
    std.mem.eql(u8, import.params, "ip-address-family") and
    std.mem.eql(u8, import.result, "result<tcp-socket,error-code>"))
{
    return .{
        .module = "cm32p2|wasi:sockets/types",
        .name = "[constructor]tcp-socket", // or create member name per WASI 0.3
        .param = "i32 i32", // family + result area
        .result_descriptor_error = true,
    };
}
// bind: result_unit_error; drop: resource_drop
```

Lock exact `name` / `param` strings against existing cm32p2 conventions in open-at/sync.

- [ ] **Step 4: Emit create call path in `gen_wasi_emit.zig`**

Generalize `emitWasiResultDescriptorCall` (or add `emitWasiResultSocketCreateCall`) so target is create and single `u8`/`i32` family arg + result area; reuse `emitWasiDescriptorResultAsUnionValue`.

- [ ] **Step 5: Re-run fixture — expect pass**

```bash
./bin/do build src/build/test/compile_ok/291_wasi_tcp_create_union.do -o /tmp/t.wat
# WAT contains __wasi_import_sockets_types_tcp_socket_create and result-area loads
```

---

### Task 2: Bind path — payload enum address pack

**Files:**
- Modify: `src/build/gen_wasi_emit.zig`
- Test: `src/build/test/compile_ok/292_wasi_tcp_bind_payload_addr.do`

**Interfaces:**
- Consumes: Task 1 lowering flags for bind
- Produces: pack `IpSocketAddress` / `V4`/`V6` into scratch; call bind unit-error import; lower to `TcpError|nil`

- [ ] **Step 1: Failing fixture**

```do
.host_tcp_bind = @wasi_func("sockets/types/tcp-socket.bind", (TcpSocket, IpSocketAddress) -> TcpError | nil)
.host_tcp_drop = @wasi_func("sockets/types/tcp-socket.drop", (TcpSocket) -> nil)
TcpSocket = @wasi_resource("sockets/types/tcp-socket", { .id i64 })
TcpError error = TcpClosed | TcpUnsupportedAddress | TcpHostFailure
Ipv4SocketAddress {
    .a u8
    .b u8
    .c u8
    .d u8
    .port u16
}
IpSocketAddress = V4(Ipv4SocketAddress) | V6(Ipv6SocketAddress)
Ipv6SocketAddress {
    .hi u64
    .lo u64
    .port u16
}

start() {
    s TcpSocket = TcpSocket{id = 1}
    a Ipv4SocketAddress = Ipv4SocketAddress{a = 127, b = 0, c = 0, d = 1, port = 8080}
    e TcpError | nil = host_tcp_bind(s, V4(a))
    _ = e
    host_tcp_drop(s)
    return
}
```

- [ ] **Step 2: Implement pack + bind emit**

- Load socket `.id` via existing `emitWasiDescriptorHandleArg`
- Detect payload-enum local/ctor: tag disc 0/1; write fields to scratch
- Call unit-error import; reuse `emitWasiUnitResultAsUnionValue`

- [ ] **Step 3: Fixture passes; WAT shows pack stores + bind call**

---

### Task 3: Manifest validator + tool tests

**Files:**
- Modify: `src/build/test/validate_wasi_bind_manifest.mjs`
- Modify: `src/build/test/test_wasi_bind_manifest_tool.mjs`

- [ ] **Step 1: Run tool test — sockets still unsupported**

```bash
node src/build/test/test_wasi_bind_manifest_tool.mjs
```

- [ ] **Step 2: Add `isSocketCreate` / `isSocketBind` / drop helpers in `buildShimPlan`; return lowerable shim**
- [ ] **Step 3: Flip test expectations from unsupported to lowerable; plan build must not fail on socket binds**

---

### Task 4: Stdlib net/tcp/udp

**Files:**
- Modify: `lib/net.do`, `lib/tcp.do`, `lib/udp.do`
- Test: `src/build/test/compile_ok/293_imported_tcp_create_bind_wrapper.do`
- Optional: `src/build/test/ok/194_tcp_api_types.do` if `do test` can cover pure type/use without host

- [ ] **Step 1: Implement stdlib per design doc**
- [ ] **Step 2: Imported wrapper fixture compiles**
- [ ] **Step 3: Keep `07_net_socket_smoke` green (legacy SocketAddr)**

---

### Task 5: Docs closeout + full regression

**Files:**
- Modify: `doc/pending_blocked.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/wit/wasi_p3_lowering.md`, `README.md` (G6.3 status)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Move G6.3 to closed; leave G6.2 blocked**
- [ ] **Step 2: Run**

```bash
cd src && zig test main.zig
./src/build/test/run_tests.sh
```

Expected: unit pass; integration `fail=0` (skip may stay 3).

- [ ] **Step 3: Commit** (only if user requests)

---

## Self-review

| Spec item | Task |
|-----------|------|
| Resource shells | 1, 4 |
| create/bind/drop lower | 1–2 |
| Payload enum address | 2, 4 |
| Overloads public API | 4 |
| Manifest | 3 |
| Docs / unblock | 5 |
| No G6.2 | all non-goals |

No placeholders remaining for core path; IPv6 octet order fixed in design (hi||lo big-endian).
