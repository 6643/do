const std = @import("std");
const process = @import("process.zig");
const test_cases = @import("test_cases.zig");
const structural_checks = @import("structural_checks.zig");

const map_source =
    \\package demo:maps@1.0.0;
    \\
    \\interface api {
    \\  lookup: func(values: map<string, u32>) -> map<u32, string>;
    \\}
    \\
    \\world probe { import api; }
;

const WitOutputKind = enum { sidecar, package };

const OrderedMarkerPair = struct {
    first: []const u8,
    second: []const u8,
};

const GcCoreOracleCase = struct {
    fixture: []const u8,
    mode: ?[]const u8,
};

const gc_core_oracle_cases = [_]GcCoreOracleCase{
    .{ .fixture = "text-identity.do", .mode = "identity" },
    .{ .fixture = "text-identity-renamed.do", .mode = "relay" },
    .{ .fixture = "list-set.do", .mode = "update" },
    .{ .fixture = "list-put.do", .mode = "append_byte" },
    .{ .fixture = "parameterized-list-set.do", .mode = "set_at" },
    .{ .fixture = "parameterized-list-set-renamed.do", .mode = "replace" },
    .{ .fixture = "managed-struct-set.do", .mode = null },
    .{ .fixture = "managed-struct-renamed.do", .mode = null },
    .{ .fixture = "managed-struct-preserve-field.do", .mode = null },
    .{ .fixture = "managed-struct-payload.do", .mode = "update" },
    .{ .fixture = "managed-struct-payload-renamed.do", .mode = "rewrite" },
    .{ .fixture = "nested-managed-struct.do", .mode = "replace" },
    .{ .fixture = "managed-tuple-text-bytes.do", .mode = "rewrite" },
};

const PureLoweringCase = struct {
    name: []const u8,
    source: []const u8,
    build_flag: []const u8,
    world: []const u8,
    wit_snapshot: ?[]const u8,
    wit_output_kind: WitOutputKind = .sidecar,
    package_wit_markers: []const []const u8 = &.{},
    package_type_markers: []const []const u8 = &.{},
    package_world_suffix: ?[]const u8 = null,
    wit_markers: []const []const u8 = &.{},
    markers: []const []const u8,
    forbidden_markers: []const []const u8,
    count_marker: ?[]const u8 = null,
    expected_count: usize = 0,
    validate_core: bool = false,
    ordinary_build_error: ?[]const u8 = null,
    ordered_markers: ?OrderedMarkerPair = null,
    wat_snapshot: ?[]const u8 = null,
    wit_sha256: ?[]const u8 = null,
};

const ComponentTemplateCase = struct {
    wit: []const u8,
    world: []const u8,
    markers: []const []const u8,
};

const component_template_cases = [_]ComponentTemplateCase{
    .{
        .wit = "examples/p3-runtime/wit/async-template.wit",
        .world = "probe",
        .markers = &.{
            "[async-lower]wait-for",
            "[async-lift]run",
            "[callback][async-lift]run",
            "[task-return]run",
        },
    },
    .{
        .wit = "examples/p3-runtime/wit/cli-stream-stdin.wit",
        .world = "stream-stdin-probe",
        .markers = &.{
            "wasi:cli/stdin@0.3.0-rc-2025-09-16\" \"read-via-stream",
            "(param i32)",
            "\"$root\" \"[waitable-set-new]\"",
            "\"[export]$root\" \"[task-return]run\"",
        },
    },
    .{
        .wit = "examples/p3-runtime/wit/cli-stream-stdout.wit",
        .world = "stream-stdout-probe",
        .markers = &.{
            "wasi:cli/stdout@0.3.0-rc-2025-09-16\" \"[async-lower]write-via-stream",
            "[async-lower]write-via-stream",
            "[stream-new-0]write-via-stream",
            "[stream-drop-writable-0]write-via-stream",
        },
    },
    .{
        .wit = "src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16",
        .world = "wasi:filesystem/imports",
        .markers = &.{
            "wasi:filesystem/types@0.3.0-rc-2025-09-16\" \"[async-lower][method]descriptor.read-directory",
            "[stream-new-0][method]descriptor.read-directory",
            "[async-lower][stream-read-0][method]descriptor.read-directory",
            "[future-new-1][method]descriptor.read-directory",
            "[async-lower][future-read-1][method]descriptor.read-directory",
            "[future-drop-readable-1][method]descriptor.read-directory",
        },
    },
};

const pure_lowering_cases = [_]PureLoweringCase{
    .{
        .name = "async-call component lowering",
        .source = "examples/p3-runtime/async-call-component.do",
        .build_flag = "--p3-async-call-component",
        .world = "probe",
        .wit_snapshot = "examples/p3-runtime/async-call-component.wit",
        .markers = &.{
            "[guest-inline-helper]",
            "[guest-inline-resume]",
            "[guest-async-child]",
            "[guest-async-parent-resume]",
            "[guest-async-child-drop]",
            "[guest-async-root-terminal]",
        },
        .forbidden_markers = &.{ "[task-return]helper", "[async-lift]helper" },
        .count_marker = "call $host-work",
        .expected_count = 2,
    },
    .{
        .name = "inline scalar async-call lowering",
        .source = "examples/p3-runtime/async-call-inline-scalar-argument.do",
        .build_flag = "--p3-async-call-component",
        .world = "probe",
        .wit_snapshot = "examples/p3-runtime/async-call-component.wit",
        .markers = &.{
            "[guest-inline-helper]",
            "[guest-inline-arg-store]",
            "[guest-inline-arg-load]",
            "[guest-inline-resume]",
            "[guest-async-child]",
            "[guest-async-arg-store]",
            "[guest-async-arg-load]",
            "[guest-async-parent-resume]",
            "[guest-async-child-drop]",
            "[guest-async-root-terminal]",
            "i32.const 7",
            "i32.const 20",
        },
        .forbidden_markers = &.{ "[task-return]helper", "[async-lift]helper" },
        .count_marker = "call $host-work",
        .expected_count = 2,
    },
    .{
        .name = "scalar async-call lowering",
        .source = "examples/p3-runtime/async-call-scalar-argument.do",
        .build_flag = "--p3-async-call-component",
        .world = "probe",
        .wit_snapshot = "examples/p3-runtime/async-call-component.wit",
        .markers = &.{
            "[guest-async-child]",
            "[guest-async-arg-store]",
            "[guest-async-arg-load]",
            "[guest-async-parent-resume]",
            "[guest-async-child-drop]",
            "[guest-async-root-terminal]",
            "i32.const 7",
            "i32.const 20",
        },
        .forbidden_markers = &.{ "[task-return]helper", "[async-lift]helper" },
    },
    .{
        .name = "CLI stdin stream lowering",
        .source = "examples/p3-runtime/cli-stream-stdin-component.do",
        .build_flag = "--p3-async-component",
        .world = "stream-stdin-probe",
        .wit_snapshot = null,
        .wit_markers = &.{ "export run: async func()" },
        .markers = &.{
            "[stream-acquire]read-via-stream",
            "stream.read",
            "[stream-eof]Err(nil)",
            "[stream-drop-readable]",
            "future-drop-readable",
        },
        .forbidden_markers = &.{ "[async-lower][future-read-1]read-via-stream", "__stream_completion_global" },
    },
    .{
        .name = "CLI stdin bounded stream lowering",
        .source = "examples/p3-runtime/cli-stream-stdin-one-read.do",
        .build_flag = "--p3-async-component",
        .world = "stream-stdin-probe",
        .wit_snapshot = null,
        .wit_markers = &.{ "export read-once: async func()" },
        .markers = &.{
            "(export \"[async-lift]read-once\"",
            "(export \"[callback][async-lift]read-once\"",
            "i32.const 1",
        },
        .forbidden_markers = &.{ "[stream-read-count]" },
    },
    .{
        .name = "CLI stdout stream lowering",
        .source = "examples/p3-runtime/cli-stream-stdout-component.do",
        .build_flag = "--p3-async-component",
        .world = "stream-stdout-probe",
        .wit_snapshot = null,
        .wit_markers = &.{ "write-via-stream: async func", "export write: async func" },
        .markers = &.{
            "[async-lower]write-via-stream",
            "[stream-new-0]write-via-stream",
            "[async-lower][stream-write-0]write-via-stream",
            "[stream-drop-writable-0]write-via-stream",
            "(export \"[async-lift]write\"",
        },
        .forbidden_markers = &.{},
    },
    .{
        .name = "HTTP empty request lowering",
        .source = "examples/p3-runtime/http-request-empty.do",
        .build_flag = "--p3-async-component",
        .world = "http-request-probe",
        .wit_snapshot = null,
        .wit_markers = &.{ "package wasi:http@", "request-new-payload: func", "world http-request-probe" },
        .markers = &.{
            "wasi:http/types@0.3.0-rc-2025-09-16\" \"[constructor]fields",
            "wasi:http/types@0.3.0-rc-2025-09-16\" \"[static]request.new",
            "wasi:http/types@0.3.0-rc-2025-09-16\" \"[future-new-1]request-new-payload",
            "wasi:http/types@0.3.0-rc-2025-09-16\" \"[future-write-1]request-new-payload",
            "wasi:http/types@0.3.0-rc-2025-09-16\" \"[future-drop-writable-1]request-new-payload",
            "wasi:http/types@0.3.0-rc-2025-09-16\" \"[future-drop-readable-2]request-new-payload",
            "wasi:http/types@0.3.0-rc-2025-09-16\" \"[resource-drop]request",
        },
        .forbidden_markers = &.{},
    },
    .{
        .name = "HTTP request body package lowering",
        .source = "examples/p3-runtime/http-request-body.do",
        .build_flag = "--p3-async-component",
        .world = "http-request-body-probe",
        .wit_snapshot = null,
        .wit_output_kind = .package,
        .package_wit_markers = &.{
            "package wasi:http@0.3.0-rc-2025-09-16",
            "world http-request-body-probe",
            "import wasi:cli/stdin@0.3.0-rc-2025-09-16",
        },
        .package_type_markers = &.{
            "consume-body-payload: func(",
            "request-new-payload: func(",
        },
        .package_world_suffix =
            \\
            \\interface probe {
            \\  use types.{response, error-code};
            \\  run: async func() -> result<response, error-code>;
            \\}
            \\
            \\world http-request-body-probe {
            \\  import types;
            \\  import client;
            \\  import wasi:cli/stdin@0.3.0-rc-2025-09-16;
            \\  export probe;
            \\}
            \\
        ,
        .markers = &.{
            "wasi:cli/stdin@0.3.0-rc-2025-09-16\" \"read-via-stream\"",
            "wasi:http/types@0.3.0-rc-2025-09-16\" \"[static]request.new\"",
            "wasi:http/client@0.3.0-rc-2025-09-16\" \"[async-lower]send\"",
            "wasi:cli/stdin@0.3.0-rc-2025-09-16\" \"[future-drop-readable-1]read-via-stream\"",
            "call $body-acquire",
            "call $construct-request",
            "call $drop-body-completion",
            "i32.const 1",
        },
        .forbidden_markers = &.{ "async-lower][request.new" },
    },
    .{
        .name = "HTTP request body completion-await package lowering",
        .source = "examples/p3-runtime/http-request-body-await-completion.do",
        .build_flag = "--p3-async-component",
        .world = "http-request-body-probe",
        .wit_snapshot = null,
        .wit_output_kind = .package,
        .package_wit_markers = &.{ "package wasi:http@0.3.0-rc-2025-09-16", "world http-request-body-probe" },
        .package_type_markers = &.{ "consume-body-payload: func(", "request-new-payload: func(" },
        .package_world_suffix =
            \\
            \\interface probe {
            \\  use types.{response, error-code};
            \\  run: async func() -> result<response, error-code>;
            \\}
            \\
            \\world http-request-body-probe {
            \\  import types;
            \\  import client;
            \\  import wasi:cli/stdin@0.3.0-rc-2025-09-16;
            \\  export probe;
            \\}
            \\
        ,
        .markers = &.{
            "wasi:cli/stdin@0.3.0-rc-2025-09-16\" \"[async-lower][future-read-1]read-via-stream\"",
            "call $start-body-request",
            "call $start-body-completion",
            "call $accept-body-completion",
            "struct.set $async-frame $slot-body-completion-result",
            "struct.set $async-frame $slot-body-request",
            "i32.const 48",
            "call $acquire-body",
            "call $construct-request",
        },
        .forbidden_markers = &.{},
        .ordinary_build_error = "AsyncLoweringUnavailable",
    },
    .{
        .name = "HTTP request body producer package lowering",
        .source = "examples/p3-runtime/http-request-body-producer-send-first.do",
        .build_flag = "--p3-async-component",
        .world = "http-request-body-producer-probe",
        .wit_snapshot = null,
        .wit_output_kind = .package,
        .package_wit_markers = &.{ "package wasi:http@0.3.0-rc-2025-09-16", "world http-request-body-producer-probe" },
        .package_type_markers = &.{ "consume-body-payload: func(", "request-new-payload: func(" },
        .package_world_suffix =
            \\
            \\interface probe {
            \\  use types.{response, error-code};
            \\  run: async func() -> result<response, error-code>;
            \\}
            \\
            \\world http-request-body-producer-probe {
            \\  import types;
            \\  import client;
            \\  import wasi:cli/stdout@0.3.0-rc-2025-09-16;
            \\  export probe;
            \\}
            \\
        ,
        .markers = &.{
            "wasi:cli/stdout@0.3.0-rc-2025-09-16\" \"[stream-new-0]write-via-stream\"",
            "wasi:cli/stdout@0.3.0-rc-2025-09-16\" \"[async-lower][stream-write-0]write-via-stream\"",
            "wasi:cli/stdout@0.3.0-rc-2025-09-16\" \"[stream-drop-writable-0]write-via-stream\"",
            "wasi:http/types@0.3.0-rc-2025-09-16\" \"[static]request.new\"",
            "wasi:http/client@0.3.0-rc-2025-09-16\" \"[async-lower]send\"",
            "call $start-producer",
            "call $construct-producer-request",
            "call $start-producer-send",
            "[future-drop-readable-2]request-new-payload",
            "(export \"[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run\")",
        },
        .forbidden_markers = &.{},
        .ordered_markers = .{ .first = "call $producer-request-new", .second = "call $producer-stream-drop-writable" },
    },
    .{
        .name = "HTTP response consume-body package assembly",
        .source = "examples/p3-runtime/http-response-consume-body.do",
        .build_flag = "--p3-async-component",
        .world = "http-response-body-probe",
        .wit_snapshot = null,
        .wit_output_kind = .package,
        .package_wit_markers = &.{ "package wasi:http@0.3.0-rc-2025-09-16", "world http-response-body-probe" },
        .package_type_markers = &.{ "consume-body-payload: func(", "request-new-payload: func(" },
        .package_world_suffix =
            \\
            \\interface probe {
            \\  use types.{response};
            \\  run: async func(response: response);
            \\}
            \\
            \\world http-response-body-probe {
            \\  import types;
            \\  export probe;
            \\}
            \\
        ,
        .markers = &.{ "call $consume-body" },
        .forbidden_markers = &.{},
    },
    .{
        .name = "variant resource stream lowering",
        .source = "examples/p3-runtime/variant-resource-stream.do",
        .build_flag = "--p3-async-component",
        .world = "variant-resource-stream-canonical",
        .wit_snapshot = "examples/p3-runtime/wit/variant-resource-stream-canonical.wit",
        .markers = &.{ "[event-tag-offset]", "[event-payload-offset]", "[resource-drop]ticket" },
        .forbidden_markers = &.{},
    },
    .{
        .name = "G6.2 owned-record nested producer and canonical validation",
        .source = "examples/p3-runtime/g6-2-owned-record-nested-producer.do",
        .build_flag = "--p3-async-component",
        .world = "owned-record-nested-producer",
        .wit_snapshot = "examples/p3-runtime/wit/g6-2-owned-record-nested-producer.wit",
        .markers = &.{
            ";; [producer-record-byte-size] 4",
            ";; [producer-record-alignment] 4",
            ";; [producer-nested-ticket-offset] 0",
            ";; [producer-nested-path] inner.ticket",
            ";; [producer-stream-capacity] 1",
            ";; [producer-source-signature] (i32) -> (i32)",
            ";; [producer-input-mode]",
            ";; [producer-ownership-mask] guest=1 transferred=2",
            ";; [producer-record-transfer]",
            ";; [producer-resource-drop-exactly-once]",
            ";; [producer-child-before-parent-cleanup]",
            "(func (export \"[async-lift]produce\")",
        },
        .forbidden_markers = &.{ "__arc_", "ref.null", "struct.new", "array.new" },
        .wat_snapshot = "examples/p3-runtime/g6-2-owned-record-nested-producer-canonical.wat",
        .wit_sha256 = "9662440709b01044544d4c4350f3e6f783a8f06aaa5c884a96a1e43a935a7543",
    },
    .{
        .name = "async resource Result lowering",
        .source = "examples/p3-runtime/async-resource-result-component.do",
        .build_flag = "--p3-async-component",
        .world = "async-resource-probe",
        .wit_snapshot = "src/build/p3_async_resource_probe.wit",
        .markers = &.{
            "[async-lower]send",
            "[resource-drop]request",
            "[resource-drop]response",
            "[task-return]run",
            "(type $async-frame (struct",
            "(field $slot-result-ptr (mut i32))",
            "(table $async-frames 0 (ref null $async-frame))",
            "$result-buffer-for-handle",
            "[resource-result-error-terminal]",
            "i32.const 0",
        },
        .forbidden_markers = &.{ "global $frame-next" },
    },
    .{
        .name = "owned-error resource Result lowering",
        .source = "examples/p3-runtime/owned-error-resource-probe.do",
        .build_flag = "--p3-async-component",
        .world = "owned-error-result-probe",
        .wit_snapshot = "src/build/p3_async_resource_owned_error_probe.wit",
        .markers = &.{
            "[async-lower]send",
            "[resource-drop]request",
            "[resource-drop]response",
            "[resource-drop]error-resource",
            ";; [resource-owned-error-result]",
        },
        .forbidden_markers = &.{},
    },
    .{
        .name = "owned-error resource cancellation lowering",
        .source = "examples/p3-runtime/owned-error-resource-cancel-component.do",
        .build_flag = "--p3-async-component",
        .world = "owned-error-resource-cancel-probe",
        .wit_snapshot = "src/build/p3_async_resource_owned_error_cancel_probe.wit",
        .markers = &.{
            "do:resource-probe-owned-error/http@0.1.0\" \"[async-lower]send",
            "[resource-drop]error-resource",
            "[resource-result-cancel]",
        },
        .forbidden_markers = &.{ "do:resource-probe/http@0.1.0" },
    },
    .{
        .name = "resource probe lowering",
        .source = "examples/p3-runtime/resource-probe.do",
        .build_flag = "--p3-resource-probe-component",
        .world = "probe",
        .wit_snapshot = "examples/p3-runtime/wit/resource-probe.wit",
        .markers = &.{},
        .forbidden_markers = &.{},
    },
    .{
        .name = "D2 TCP socket create-bind-drop lowering",
        .source = "examples/p3-runtime/wasi-sockets-create-bind-drop-component.do",
        .build_flag = "--p3-wasi-sockets-create-bind-drop-component",
        .world = "socket-probe",
        .wit_snapshot = null,
        .wit_markers = &.{
            "package wasi:sockets@0.3.0;",
            "resource tcp-socket {",
            "world socket-probe {",
        },
        .markers = &.{
            ";; socket-target protocol=tcp",
            "[static]tcp-socket.create",
            "[method]tcp-socket.bind",
            "[resource-drop]tcp-socket",
        },
        .forbidden_markers = &.{
            "[static]udp-socket.create",
            "[method]udp-socket.bind",
            "[resource-drop]udp-socket",
        },
    },
    .{
        .name = "D2 UDP socket create-bind-drop lowering",
        .source = "examples/p3-runtime/wasi-udp-sockets-create-bind-drop-component.do",
        .build_flag = "--p3-wasi-sockets-create-bind-drop-component",
        .world = "socket-probe",
        .wit_snapshot = null,
        .wit_markers = &.{
            "package wasi:sockets@0.3.0;",
            "resource udp-socket {",
            "world socket-probe {",
        },
        .markers = &.{
            ";; socket-target protocol=udp",
            "[static]udp-socket.create",
            "[method]udp-socket.bind",
            "[resource-drop]udp-socket",
        },
        .forbidden_markers = &.{
            "[static]tcp-socket.create",
            "[method]tcp-socket.bind",
            "[resource-drop]tcp-socket",
        },
    },
    .{
        .name = "generic record stream lowering",
        .source = "examples/p3-runtime/record-stream-probe-component.do",
        .build_flag = "--p3-async-component",
        .world = "record-stream-probe",
        .wit_snapshot = "examples/p3-runtime/wit/record-stream-probe.wit",
        .markers = &.{
            "[record-stream-plan]",
            "[record-loop-state]",
            "[record-read-index]",
            "[record-field-id-offset]",
            "[record-field-label-ptr-offset]",
            "[record-field-label-len-offset]",
            "call $cleanup",
            "do:record-stream-probe/source@0.1.0\" \"read-via-stream\"",
            "[async-lower][stream-read-0]read-via-stream",
            "[async-lower][future-read-1]read-via-stream",
        },
        .forbidden_markers = &.{ "directory-entry" },
    },
    .{
        .name = "WASI filesystem preopen lowering",
        .source = "examples/p3-runtime/wasi-filesystem-preopen.do",
        .build_flag = "--p3-wasi-filesystem-preopen-component",
        .world = "preopen-probe",
        .wit_snapshot = "examples/p3-runtime/wit/wasi-filesystem-preopen.wit",
        .wit_markers = &.{
            "get-directories: func() -> list<tuple<own<descriptor>, string>>",
            "open-at: func(path-flags: u32, path: string, open-flags: u32, descriptor-flags: u32) -> result<own<descriptor>, error-code>",
            "sync: func() -> result<_, error-code>",
        },
        .markers = &.{ "[method]descriptor.open-at", "[resource-drop]descriptor" },
        .forbidden_markers = &.{},
    },
    .{
        .name = "WASI filesystem read-directory lowering",
        .source = "examples/p3-runtime/wasi-filesystem-read-directory.do",
        .build_flag = "--p3-async-component",
        .world = "read-directory-probe",
        .wit_snapshot = null,
        .wit_markers = &.{
            "record directory-entry {",
            "read-directory: async func() -> tuple<stream<directory-entry>, future<result<_, error-code>>>",
        },
        .markers = &.{
            "[async-lower][method]descriptor.read-directory",
            "[async-lower][stream-read-0][method]descriptor.read-directory",
            "[async-lower][future-read-1][method]descriptor.read-directory",
            "call $future-drop-readable",
            "call $stream-drop-readable",
            "call $descriptor-drop",
        },
        .forbidden_markers = &.{},
    },
    .{
        .name = "StreamMirror lowering",
        .source = "examples/p3-runtime/stream-probe-stream-mirror.do",
        .build_flag = "--p3-async-component",
        .world = "stream-mirror-probe",
        .wit_snapshot = "examples/p3-runtime/wit/stream-probe-stream-mirror.wit",
        .markers = &.{
            "[stream-mirror-source-read]",
            "[stream-mirror-writer-write]",
            "[stream-mirror-sink-result]",
            "[stream-mirror-cancel]",
            "[stream-mirror-source-cancel] future-drop-readable",
            "[stream-mirror-frame-size] 96",
            "do:stream-probe/source@0.1.0",
            "[future-drop-readable-1]read-via-stream",
            "(export \"[async-lift]produce\")",
        },
        .forbidden_markers = &.{ "[async-lift]write-via-stream" },
        .validate_core = true,
    },
    .{
        .name = "descriptor-owned stream reader lowering",
        .source = "examples/p3-runtime/stream-probe-component.do",
        .build_flag = "--p3-async-component",
        .world = "stream-probe",
        .wit_snapshot = null,
        .wit_markers = &.{ "package do:stream-probe@0.1.0", "world stream-probe" },
        .markers = &.{
            "do:stream-probe/source@0.1.0",
            "[async-lower][stream-read-0]read-via-stream",
            "[future-drop-readable-1]read-via-stream",
        },
        .forbidden_markers = &.{ "wasi:cli/stdin" },
    },
    .{
        .name = "descriptor-owned stream writer lowering",
        .source = "examples/p3-runtime/stream-probe-writer-component.do",
        .build_flag = "--p3-async-component",
        .world = "stream-writer-probe",
        .wit_snapshot = null,
        .wit_markers = &.{ "package do:stream-probe@0.1.0", "interface sink", "world stream-writer-probe" },
        .markers = &.{ "do:stream-probe/sink@0.1.0" },
        .forbidden_markers = &.{},
    },
    .{
        .name = "WASI filesystem bounded read-directory lowering",
        .source = "examples/p3-runtime/wasi-filesystem-read-directory-bounded.do",
        .build_flag = "--p3-async-component",
        .world = "read-directory-probe",
        .wit_snapshot = null,
        .wit_markers = &.{ "record directory-entry {", "run-bounded: async func" },
        .markers = &.{ "bounded remaining reads are stored at frame+16", "i32.const 3", "i32.sub", "call $stream-read" },
        .forbidden_markers = &.{},
        .count_marker = "call $stream-read",
        .expected_count = 1,
    },
    .{
        .name = "G6.2 C-min list producer lowering",
        .source = "examples/p3-runtime/g6-2-c-min-list-resource-producer.do",
        .build_flag = "--p3-async-component",
        .world = "c-min-producer",
        .wit_snapshot = null,
        .wit_markers = &.{ "package do:g6-2-c-min-producer@0.1.0", "world c-min-producer", "data: stream<list<resource-entry>>" },
        .markers = &.{
            "[producer-list-pointer]",
            "[producer-list-length]",
            "[producer-list-element-stride]",
            "[producer-list-ticket-offset]",
            "[producer-stream-capacity]",
            "[producer-list-transfer]",
            "[producer-child-before-parent-cleanup]",
        },
        .forbidden_markers = &.{},
    },
    .{
        .name = "G6.2 C-min dynamic list producer lowering",
        .source = "examples/p3-runtime/g6-2-c-min-dynamic-list-resource-producer.do",
        .build_flag = "--p3-async-component",
        .world = "dynamic-list-producer",
        .wit_snapshot = null,
        .wit_markers = &.{ "export produce: async func(count: u32)", "world dynamic-list-producer" },
        .markers = &.{
            "[producer-list-pointer]",
            "[producer-list-length]",
            "[producer-list-element-stride]",
            "[producer-list-ticket-offset]",
            "[producer-stream-capacity]",
            "[producer-list-transfer]",
            "[producer-child-before-parent-cleanup]",
            "i32.const 3",
        },
        .forbidden_markers = &.{},
    },
    .{
        .name = "G6.2 batched list producer lowering",
        .source = "examples/p3-runtime/g6-2-batched-list-resource-producer.do",
        .build_flag = "--p3-async-component",
        .world = "batched-list-producer",
        .wit_snapshot = null,
        .wit_markers = &.{
            "package do:g6-2-batched-list-producer@0.1.0",
            "data: stream<list<resource-entry>>",
            "world batched-list-producer",
            "export produce: async func(mode: u32)",
        },
        .markers = &.{
            "producer-list-pointer",
            "producer-list-length",
            "producer-list-pointer-batch-1",
            "producer-list-length-batch-1",
            "producer-list-element-stride",
            "producer-list-ticket-offset",
            "producer-stream-capacity",
            "producer-batch-transfer-0",
            "producer-batch-transfer-1",
            "producer-batch-child-before-parent-cleanup",
            "producer-batch-list-release",
            "i32.const 111",
            "i32.const 222",
            "i32.const 333",
            "[producer-batched-list-transfer]",
        },
        .forbidden_markers = &.{ "do:g6-2-c-min", "dynamic-list-producer", "c-min-producer" },
    },
    .{
        .name = "G6.2 scalar list producer lowering",
        .source = "examples/p3-runtime/g6-2-scalar-list-producer.do",
        .build_flag = "--p3-async-component",
        .world = "scalar-list-producer",
        .wit_snapshot = "examples/p3-runtime/wit/g6-2-scalar-list-producer.wit",
        .wit_markers = &.{
            "consume-via-stream: async func(data: stream<list<u32>>) -> result<_, error-code>;",
            "export produce: async func(count: u32) -> result<_, error-code>;",
            "world scalar-list-producer",
        },
        .markers = &.{
            "[producer-list-pointer]",
            "[producer-list-length]",
            "[producer-list-element-stride]",
            "[producer-list-capacity]",
            "[producer-stream-item-slot]",
            "[producer-list-transfer]",
            "[producer-list-release-exactly-once]",
            "[producer-cancel-before-transfer]",
        },
        .forbidden_markers = &.{ "[resource-drop]" },
    },
    .{
        .name = "async host scalar argument lowering",
        .source = "examples/p3-runtime/async-host-scalar-argument.do",
        .build_flag = "--p3-async-host-arg-component",
        .world = "probe",
        .wit_snapshot = "examples/p3-runtime/wit/async-call-arg-probe.wit",
        .markers = &.{
            "[async-lower]work",
            "[guest-async-arg-store]",
            "[guest-async-arg-load]",
            "[guest-async-child-drop]",
            "[guest-async-waitable-drop]",
            "[guest-async-context-clear]",
            "[guest-async-frame-free]",
            "[task-cancel]",
            "i32.const 20",
            "i32.const 12",
            "[export]$root\" \"[task-return]run",
        },
        .forbidden_markers = &.{ "[task-return]helper", "[async-lift]helper" },
    },
};

const RustRuntimeExpectation = struct {
    mode: []const u8,
    markers: []const []const u8,
};

const RustRuntimeCase = struct {
    name: []const u8,
    source: []const u8,
    build_flag: []const u8,
    world: []const u8,
    wit_snapshot: []const u8,
    runner_bin: []const u8,
    expectations: []const RustRuntimeExpectation,
};

const rust_runtime_cases = [_]RustRuntimeCase{
    .{
        .name = "async-call component runtime",
        .source = "examples/p3-runtime/async-call-component.do",
        .build_flag = "--p3-async-call-component",
        .world = "probe",
        .wit_snapshot = "examples/p3-runtime/async-call-component.wit",
        .runner_bin = "do-p3-async-call-component-host-runner",
        .expectations = &.{
            .{
                .mode = "ready",
                .markers = &.{
                    "mode=ready child-completions=2 child-drops=2 host-future-drops=2 table-empty=true",
                    "async-call root-terminal=1 duplicate-drop=0",
                },
            },
            .{
                .mode = "pending",
                .markers = &.{
                    "mode=pending child-completions=2 child-drops=2 host-future-drops=2 table-empty=true",
                    "async-call root-terminal=1 duplicate-drop=0",
                },
            },
            .{
                .mode = "cancel-inline",
                .markers = &.{
                    "mode=cancel-inline child-cancellations=1 child-drops=1 host-future-drops=1 table-empty=true",
                },
            },
            .{
                .mode = "cancel-child",
                .markers = &.{
                    "mode=cancel-child child-cancellations=1 child-drops=2 host-future-drops=2 table-empty=true",
                },
            },
        },
    },
};

const MapSyncComponentCase = struct {
    name: []const u8,
    source: []const u8,
    descriptor: []const u8,
    wit: []const u8,
    canonical_type: []const u8,
    wit_marker: []const u8,
    mode: []const u8,
    runtime_marker: []const u8,
};

const map_sync_component_cases = [_]MapSyncComponentCase{
    .{
        .name = "map<u32,u32> synchronous lower Component host gate",
        .source = "examples/gc-p3-runtime/map-u32-u32-lower.do",
        .descriptor = "demo:marshal-map-u32-u32/api.write@1.0.0/lower",
        .wit = "examples/gc-p3-runtime/marshal-map-u32-u32-lower-assembly.wit",
        .canonical_type = "(type $canonical_lower (func (param i32 i32)))",
        .wit_marker = "write: func(value: map<u32, u32>)",
        .mode = "lower",
        .runtime_marker = "GC map<u32,u32> lower host adapter passed entries=[7->70, 9->90] result=42 stats=17 write-calls=1 allocations=1 frees=1",
    },
    .{
        .name = "map<u32,u32> synchronous lift Component host gate",
        .source = "examples/gc-p3-runtime/map-u32-u32-lift.do",
        .descriptor = "demo:marshal-map-u32-u32/api.read@1.0.0/lift",
        .wit = "examples/gc-p3-runtime/marshal-map-u32-u32-lift-assembly.wit",
        .canonical_type = "(type $canonical_lift (func (param i32)))",
        .wit_marker = "read: func() -> map<u32, u32>",
        .mode = "lift",
        .runtime_marker = "GC map<u32,u32> lift host adapter passed entries=[7->70, 9->90] result=176 stats=17 read-calls=1 allocations=1 frees=1",
    },
};

const ComponentFixture = struct {
    wat: []u8,
    wit: []u8,
    core: []u8,
    embedded: []u8,
    component: []u8,

    fn deinit(self: *ComponentFixture, allocator: std.mem.Allocator) void {
        allocator.free(self.wat);
        allocator.free(self.wit);
        allocator.free(self.core);
        allocator.free(self.embedded);
        allocator.free(self.component);
        self.* = undefined;
    }
};

pub fn main(init: std.process.Init) !void {
    try run_all(init);
}

fn run_all(init: std.process.Init) !void {
    const repo_root = init.environ_map.get("DO_HARNESS_REPO_ROOT") orelse
        return error.MissingHarnessEnvironment;
    const do_bin = init.environ_map.get("DO_HARNESS_DO_BIN") orelse
        return error.MissingHarnessEnvironment;
    const toolchain_bin = init.environ_map.get("DO_HARNESS_TOOLCHAIN_BIN") orelse
        return error.MissingHarnessEnvironment;

    var temp = try process.make_temp_dir(init.gpa, init.io);
    var cleanup = process.defer_cleanup(&temp);
    defer cleanup.deinit();

    var component: ?ComponentFixture = null;
    defer if (component) |*fixture| fixture.deinit(init.gpa);

    for (test_cases.cases) |case| {
        switch (case.kind) {
            .compiler_smoke => try run_compiler_smoke(init, repo_root, do_bin, temp.path),
            .wit_map => try run_wit_map(init, do_bin, temp.path),
            .component_assembly => {
                if (component == null) component = try assemble_component(init, repo_root, do_bin, toolchain_bin, temp.path);
                try assert_component_fixture(init, component.?);
            },
            .assembly_validation => {
                if (component == null) component = try assemble_component(init, repo_root, do_bin, toolchain_bin, temp.path);
                try run_assembly_validation(init, repo_root, toolchain_bin, temp.path, component.?);
            },
            .wit_snapshot_validation => try run_wit_snapshot_validation(init, repo_root, toolchain_bin),
            .p3_pure_lowering_matrix => try run_p3_pure_lowering_matrix(init, repo_root, do_bin, toolchain_bin, temp.path),
            .rust_async_runner => {
                if (component == null) component = try assemble_component(init, repo_root, do_bin, toolchain_bin, temp.path);
                try run_rust_async_runner(init, repo_root, component.?.component);
                try run_rust_runtime_matrix(init, repo_root, do_bin, toolchain_bin, temp.path);
            },
            .compiler_fixture_matrix => try run_compiler_fixture_matrix(init, repo_root, do_bin, temp.path),
            .compiler_compiled_fixture_matrix => try run_compiler_compiled_fixture_matrix(init, repo_root, do_bin, toolchain_bin, temp.path),
            .compiler_auxiliary_matrix => try run_compiler_auxiliary_matrix(init, repo_root, do_bin, temp.path),
            .compiler_compiled_trap_matrix => if (std.mem.eql(u8, init.environ_map.get("RUN_WASM") orelse "0", "1"))
                try run_compiled_trap_matrix(init, repo_root, do_bin, toolchain_bin, temp.path),
            .wasm_smoke_matrix => if (std.mem.eql(u8, init.environ_map.get("RUN_WASM") orelse "0", "1"))
                try run_wasm_smoke_matrix(init, repo_root, do_bin, toolchain_bin, temp.path),
            .gc_default_matrix => try run_gc_default_matrix(init, repo_root, do_bin, toolchain_bin, temp.path),
            .component_template_validation => try run_component_template_validation(init, repo_root, toolchain_bin),
            .tool_matrix => try run_tool_matrix(init, repo_root, do_bin, temp.path),
            .external_dependency_negative_matrix => try run_external_dependency_negative_matrix(init, repo_root, do_bin, temp.path),
            .socket_abi_matrix => try run_socket_abi_matrix(init, repo_root, do_bin, temp.path),
            .structural_gate => try run_structural_gate(init, repo_root),
            .gc_core_oracle => if (std.mem.eql(u8, init.environ_map.get("RUN_GC_CORE") orelse "0", "1"))
                try run_gc_core_oracle(init, repo_root, temp.path),
            .map_core_probe => try run_map_core_probe(init, repo_root, toolchain_bin, temp.path),
            .map_sync_component => try run_map_sync_component(init, repo_root, do_bin, toolchain_bin, temp.path),
        }
        try print_case_passed(init.io, case.name);
    }
}

fn run_compiler_fixture_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    temp_path: []const u8,
) !void {
    const test_root = try join(init.gpa, repo_root, "src/build/test");
    defer init.gpa.free(test_root);
    const fixture_lib_root = try join(init.gpa, test_root, "lib");
    defer init.gpa.free(fixture_lib_root);
    const stdlib_root = try join(init.gpa, repo_root, "lib");
    defer init.gpa.free(stdlib_root);

    try run_do_test_directory(init, do_bin, test_root, "ok", temp_path, fixture_lib_root, stdlib_root, .ok);
    try run_do_test_directory(init, do_bin, test_root, "err", temp_path, fixture_lib_root, stdlib_root, .err);
    try run_do_test_directory(init, do_bin, test_root, "compile_ok", temp_path, fixture_lib_root, stdlib_root, .compile_ok);
    try run_do_test_directory(init, do_bin, test_root, "compile_err", temp_path, fixture_lib_root, stdlib_root, .compile_err);
    try run_std_library_matrix(init, do_bin, stdlib_root);
}

fn run_compiler_compiled_fixture_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
) !void {
    const test_root = try join(init.gpa, repo_root, "src/build/test");
    defer init.gpa.free(test_root);
    const lib_root = try join(init.gpa, test_root, "lib");
    defer init.gpa.free(lib_root);

    for ([_][]const u8{ "compiled_ok", "compiled_err" }) |directory_name| {
        const directory = try join(init.gpa, test_root, directory_name);
        defer init.gpa.free(directory);
        const names = try collect_files(init.gpa, init.io, directory, ".do");
        defer free_names(init.gpa, names);
        for (names) |name| {
            if (std.mem.startsWith(u8, name, "fixture.")) continue;
            const fixture = try join(init.gpa, directory, name);
            defer init.gpa.free(fixture);
            if (std.mem.eql(u8, directory_name, "compiled_ok")) {
                try run_compiled_ok_fixture(init, repo_root, do_bin, toolchain_bin, fixture, temp_path, lib_root);
                try report_fixture(init, "compiled_ok", fixture, .pass);
            } else {
                try run_compiled_err_fixture(init, do_bin, fixture, temp_path, lib_root);
                try report_fixture(init, "compiled_err", fixture, .pass);
            }
        }
    }
}

fn run_compiled_ok_fixture(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    toolchain_bin: []const u8,
    fixture: []const u8,
    temp_path: []const u8,
    lib_root: []const u8,
) !void {
    const wat = try fixture_output_path(init.gpa, temp_path, fixture, ".compiled.wat");
    defer init.gpa.free(wat);
    const expect = try replace_extension(init.gpa, fixture, ".expect");
    defer init.gpa.free(expect);
    const args = [_][]const u8{ "test", fixture, "--compiled", "-o", wat };
    var generated = try run_do_args(init, do_bin, &args, lib_root, null, 120_000);
    defer generated.deinit(init.gpa);
    try expect_success(init, &generated);
    try process.assert_stdout_contains(generated, "ok:");
    try expect_file(init.io, wat);
    if (try file_exists(init.io, expect)) {
        const source = try read_file(init, wat);
        defer init.gpa.free(source);
        try assert_expected_lines(init, expect, source);
    }

    if (!std.mem.eql(u8, init.environ_map.get("RUN_WASM") orelse "0", "1")) return;
    const node = try find_node_runtime(init);
    defer init.gpa.free(node);
    const runner = try join(init.gpa, repo_root, "src/build/test/run_compiled_test_case.mjs");
    defer init.gpa.free(runner);
    const wasm = try fixture_output_path(init.gpa, temp_path, fixture, ".compiled.wasm");
    defer init.gpa.free(wasm);
    try run_adapter_success(init, toolchain_bin, &.{ "parse-core", wat, "-o", wasm });
    var executed = try process.run_checked(init.gpa, init.io, .{
        .argv = &.{ node, runner, wasm, wat },
        .environ = init.environ_map,
        .cwd = repo_root,
        .timeout_ms = 120_000,
    });
    defer executed.deinit(init.gpa);
    try expect_success(init, &executed);
    try process.assert_stdout_contains(executed, "test \"");
    try process.assert_stdout_contains(executed, " ... ok");
    try process.assert_stdout_contains(executed, "ok:");
}

fn run_compiled_err_fixture(
    init: std.process.Init,
    do_bin: []const u8,
    fixture: []const u8,
    temp_path: []const u8,
    lib_root: []const u8,
) !void {
    const expect = try replace_extension(init.gpa, fixture, ".expect");
    defer init.gpa.free(expect);
    if (!try file_exists(init.io, expect)) return error.MissingFixtureExpectation;
    const wat = try fixture_output_path(init.gpa, temp_path, fixture, ".compiled-err.wat");
    defer init.gpa.free(wat);
    const args = [_][]const u8{ "test", fixture, "--compiled", "-o", wat };
    var generated = try run_do_args(init, do_bin, &args, lib_root, null, 120_000);
    defer generated.deinit(init.gpa);
    if (generated.exit_code() == 0) return error.FixtureExpectedFailure;
    try assert_expected_lines(init, expect, generated.stderr);
}

fn run_compiler_auxiliary_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    temp_path: []const u8,
) !void {
    const test_root = try join(init.gpa, repo_root, "src/build/test");
    defer init.gpa.free(test_root);
    const fixture_lib_root = try join(init.gpa, test_root, "lib");
    defer init.gpa.free(fixture_lib_root);

    try run_do_run_matrix(init, repo_root, do_bin, test_root, fixture_lib_root);
    try run_format_matrix(init, do_bin, test_root, fixture_lib_root, temp_path);
    try run_check_matrix(init, do_bin, test_root, fixture_lib_root, temp_path);
    try run_lsp_matrix(init, repo_root, do_bin, test_root);
}

fn run_do_run_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    test_root: []const u8,
    lib_root: []const u8,
) !void {
    const directory = try join(init.gpa, test_root, "run");
    defer init.gpa.free(directory);
    const names = try collect_files(init.gpa, init.io, directory, ".do");
    defer free_names(init.gpa, names);

    for (names) |name| {
        const fixture = try join(init.gpa, directory, name);
        defer init.gpa.free(fixture);
        const expect = try replace_extension(init.gpa, fixture, ".stdout.expect");
        defer init.gpa.free(expect);
        const args = [_][]const u8{ "run", fixture };
        var output = try run_do_args(init, do_bin, &args, lib_root, repo_root, 120_000);
        defer output.deinit(init.gpa);
        try expect_success(init, &output);
        if (output.stderr.len != 0) return error.UnexpectedCommandStderr;

        if (try file_exists(init.io, expect)) {
            try assert_file_equals(init, expect, output.stdout);
        } else if (output.stdout.len != 0) {
            return error.UnexpectedCommandStdout;
        }
        try report_fixture(init, "run", fixture, .pass);
    }
}

fn run_format_matrix(
    init: std.process.Init,
    do_bin: []const u8,
    test_root: []const u8,
    lib_root: []const u8,
    temp_path: []const u8,
) !void {
    const directory = try join(init.gpa, test_root, "fmt");
    defer init.gpa.free(directory);
    const names = try collect_files(init.gpa, init.io, directory, ".do");
    defer free_names(init.gpa, names);

    for (names) |name| {
        const fixture = try join(init.gpa, directory, name);
        defer init.gpa.free(fixture);
        const expect = try replace_extension(init.gpa, fixture, ".expect");
        defer init.gpa.free(expect);
        if (!try file_exists(init.io, expect)) return error.MissingFixtureExpectation;

        const format_args = [_][]const u8{ "fmt", fixture };
        var formatted = try run_do_args(init, do_bin, &format_args, lib_root, null, 120_000);
        defer formatted.deinit(init.gpa);
        try expect_success(init, &formatted);
        if (formatted.stderr.len != 0) return error.UnexpectedCommandStderr;
        try assert_file_equals(init, expect, formatted.stdout);

        const basename = std.fs.path.basename(fixture);
        const formatted_path = try std.fmt.allocPrint(init.gpa, "{s}/{s}.formatted.do", .{ temp_path, basename });
        defer init.gpa.free(formatted_path);
        try write_file(init, formatted_path, formatted.stdout);

        const second_args = [_][]const u8{ "fmt", formatted_path };
        var second = try run_do_args(init, do_bin, &second_args, lib_root, null, 120_000);
        defer second.deinit(init.gpa);
        try expect_success(init, &second);
        if (second.stderr.len != 0) return error.UnexpectedCommandStderr;
        try assert_file_equals(init, expect, second.stdout);

        var check_formatted = try run_fmt_flag(init, do_bin, "--check", formatted_path, lib_root);
        defer check_formatted.deinit(init.gpa);
        try expect_success(init, &check_formatted);
        if (check_formatted.stdout.len != 0 or check_formatted.stderr.len != 0) return error.UnexpectedCommandOutput;

        const original = try read_file(init, fixture);
        defer init.gpa.free(original);
        const write_path = try std.fmt.allocPrint(init.gpa, "{s}/{s}.write.do", .{ temp_path, basename });
        defer init.gpa.free(write_path);
        try write_file(init, write_path, original);
        var written = try run_fmt_flag(init, do_bin, "--write", write_path, lib_root);
        defer written.deinit(init.gpa);
        try expect_success(init, &written);
        if (written.stdout.len != 0 or written.stderr.len != 0) return error.UnexpectedCommandOutput;
        try assert_file_contents_path(init, write_path, formatted.stdout);

        var write_again = try run_fmt_flag(init, do_bin, "--write", write_path, lib_root);
        defer write_again.deinit(init.gpa);
        try expect_success(init, &write_again);
        if (write_again.stdout.len != 0 or write_again.stderr.len != 0) return error.UnexpectedCommandOutput;
        try assert_file_contents_path(init, write_path, formatted.stdout);

        if (std.mem.eql(u8, original, formatted.stdout)) {
            try report_fixture(init, "fmt", fixture, .pass);
            continue;
        }
        var check_original = try run_fmt_flag(init, do_bin, "--check", fixture, lib_root);
        defer check_original.deinit(init.gpa);
        if (check_original.exit_code() == 0) return error.UnexpectedFormatAcceptance;
        try process.assert_stderr_contains(check_original, "error[FormatMismatch]");
        if (check_original.stdout.len != 0) return error.UnexpectedCommandStdout;
        try report_fixture(init, "fmt", fixture, .pass);
    }
}

fn run_check_matrix(
    init: std.process.Init,
    do_bin: []const u8,
    test_root: []const u8,
    lib_root: []const u8,
    temp_path: []const u8,
) !void {
    const directory = try join(init.gpa, test_root, "check");
    defer init.gpa.free(directory);
    const names = try collect_files(init.gpa, init.io, directory, ".do");
    defer free_names(init.gpa, names);

    for (names) |name| {
        const fixture = try join(init.gpa, directory, name);
        defer init.gpa.free(fixture);
        const expect = try replace_extension(init.gpa, fixture, ".expect");
        defer init.gpa.free(expect);
        const args = [_][]const u8{ "check", fixture };
        var output = try run_do_args(init, do_bin, &args, lib_root, null, 120_000);
        defer output.deinit(init.gpa);
        if (try file_exists(init.io, expect)) {
            if (output.exit_code() == 0) return error.ExpectedCheckFailure;
            try assert_expected_lines(init, expect, output.stderr);
            if (output.stdout.len != 0) return error.UnexpectedCommandStdout;
        } else {
            try expect_success(init, &output);
            if (output.stdout.len != 0 or output.stderr.len != 0) return error.UnexpectedCommandOutput;
        }
        try report_fixture(init, "check", fixture, .pass);
    }

    const valid = try join(init.gpa, directory, "01_valid.do");
    defer init.gpa.free(valid);
    const invalid = try join(init.gpa, directory, "02_syntax_error.do");
    defer init.gpa.free(invalid);
    const bad_first = try std.fmt.allocPrint(init.gpa, "{s}/check_multi_bad_first.do", .{temp_path});
    defer init.gpa.free(bad_first);
    const bad_second = try std.fmt.allocPrint(init.gpa, "{s}/check_multi_bad_second.do", .{temp_path});
    defer init.gpa.free(bad_second);
    const invalid_source = try read_file(init, invalid);
    defer init.gpa.free(invalid_source);
    try write_file(init, bad_first, invalid_source);
    try write_file(init, bad_second, invalid_source);

    const valid_args = [_][]const u8{ "check", valid, valid };
    var valid_output = try run_do_args(init, do_bin, &valid_args, lib_root, null, 120_000);
    defer valid_output.deinit(init.gpa);
    try expect_success(init, &valid_output);
    if (valid_output.stdout.len != 0 or valid_output.stderr.len != 0) return error.UnexpectedCommandOutput;

    const second_invalid_args = [_][]const u8{ "check", valid, invalid };
    var second_invalid = try run_do_args(init, do_bin, &second_invalid_args, lib_root, null, 120_000);
    defer second_invalid.deinit(init.gpa);
    if (second_invalid.exit_code() == 0) return error.ExpectedCheckFailure;
    try process.assert_stderr_contains(second_invalid, invalid);
    if (second_invalid.stdout.len != 0) return error.UnexpectedCommandStdout;

    const multiple_invalid_args = [_][]const u8{ "check", bad_first, valid, bad_second };
    var multiple_invalid = try run_do_args(init, do_bin, &multiple_invalid_args, lib_root, null, 120_000);
    defer multiple_invalid.deinit(init.gpa);
    if (multiple_invalid.exit_code() == 0) return error.ExpectedCheckFailure;
    try process.assert_stderr_contains(multiple_invalid, bad_first);
    try process.assert_stderr_contains(multiple_invalid, bad_second);
    if (multiple_invalid.stdout.len != 0) return error.UnexpectedCommandStdout;
    try report_fixture(init, "check", "multi", .pass);
}

fn run_lsp_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    test_root: []const u8,
) !void {
    const directory = try join(init.gpa, test_root, "lsp");
    defer init.gpa.free(directory);
    const runner = try join(init.gpa, test_root, "run_lsp_case.mjs");
    defer init.gpa.free(runner);
    const names = try collect_files(init.gpa, init.io, directory, ".json");
    defer free_names(init.gpa, names);
    const node = init.environ_map.get("NODE_BIN") orelse "node";

    for (names) |name| {
        const fixture = try join(init.gpa, directory, name);
        defer init.gpa.free(fixture);
        const args = [_][]const u8{ node, runner, do_bin, fixture };
        var output = try process.run_checked(init.gpa, init.io, .{
            .argv = &args,
            .environ = init.environ_map,
            .cwd = repo_root,
            .timeout_ms = 120_000,
        });
        defer output.deinit(init.gpa);
        try expect_success(init, &output);
        try process.assert_stdout_contains(output, "ok: lsp ");
        if (output.stderr.len != 0) return error.UnexpectedCommandStderr;
        try report_fixture(init, "lsp", fixture, .pass);
    }
}

fn run_compiled_trap_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
) !void {
    const test_root = try join(init.gpa, repo_root, "src/build/test");
    defer init.gpa.free(test_root);
    const directory = try join(init.gpa, test_root, "compiled_trap");
    defer init.gpa.free(directory);
    const lib_root = try join(init.gpa, test_root, "lib");
    defer init.gpa.free(lib_root);
    const runner = try join(init.gpa, test_root, "run_compiled_test_case.mjs");
    defer init.gpa.free(runner);
    const names = try collect_files(init.gpa, init.io, directory, ".do");
    defer free_names(init.gpa, names);
    const node = init.environ_map.get("NODE_BIN") orelse "node";

    for (names) |name| {
        const fixture = try join(init.gpa, directory, name);
        defer init.gpa.free(fixture);
        const wat = try fixture_output_path(init.gpa, temp_path, fixture, ".trap.wat");
        defer init.gpa.free(wat);
        const wasm = try fixture_output_path(init.gpa, temp_path, fixture, ".trap.wasm");
        defer init.gpa.free(wasm);

        const build_args = [_][]const u8{ "test", fixture, "--compiled", "-o", wat };
        var generated = try run_do_args(init, do_bin, &build_args, lib_root, null, 120_000);
        defer generated.deinit(init.gpa);
        try expect_success(init, &generated);
        try expect_file(init.io, wat);

        const parse_args = [_][]const u8{ toolchain_bin, "parse-core", wat, "-o", wasm };
        var parsed = try process.run_checked(init.gpa, init.io, .{ .argv = &parse_args, .environ = init.environ_map });
        defer parsed.deinit(init.gpa);
        try expect_success(init, &parsed);
        try expect_file(init.io, wasm);

        const execute_args = [_][]const u8{ node, runner, wasm, wat };
        var executed = try process.run_checked(init.gpa, init.io, .{
            .argv = &execute_args,
            .environ = init.environ_map,
            .cwd = repo_root,
            .timeout_ms = 120_000,
        });
        defer executed.deinit(init.gpa);
        if (executed.exit_code() == 0) return error.ExpectedCompiledTrap;
        try report_fixture(init, "compiled_trap", fixture, .pass);
    }
}

fn run_wasm_smoke_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
) !void {
    const test_root = try join(init.gpa, repo_root, "src/build/test");
    defer init.gpa.free(test_root);
    const directory = try join(init.gpa, test_root, "run");
    defer init.gpa.free(directory);
    const lib_root = try join(init.gpa, test_root, "lib");
    defer init.gpa.free(lib_root);
    const runner = try join(init.gpa, test_root, "run_wasm_case.mjs");
    defer init.gpa.free(runner);
    const names = try collect_files(init.gpa, init.io, directory, ".do");
    defer free_names(init.gpa, names);
    const node = try find_node_runtime(init);
    defer init.gpa.free(node);

    for (names) |name| {
        const fixture = try join(init.gpa, directory, name);
        defer init.gpa.free(fixture);
        const wat = try fixture_output_path(init.gpa, temp_path, fixture, ".wasm-smoke.wat");
        defer init.gpa.free(wat);
        const wasm = try fixture_output_path(init.gpa, temp_path, fixture, ".wasm-smoke.wasm");
        defer init.gpa.free(wasm);
        const build_args = [_][]const u8{ "build", fixture, "-o", wat };
        var built = try run_do_args(init, do_bin, &build_args, lib_root, null, 120_000);
        defer built.deinit(init.gpa);
        try expect_success(init, &built);
        const parse_args = [_][]const u8{ "parse-core", wat, "-o", wasm };
        try run_adapter_success(init, toolchain_bin, &parse_args);
        const execute_args = [_][]const u8{ node, runner, wasm };
        var executed = try process.run_checked(init.gpa, init.io, .{
            .argv = &execute_args,
            .environ = init.environ_map,
            .cwd = repo_root,
            .timeout_ms = 120_000,
        });
        defer executed.deinit(init.gpa);
        try expect_success(init, &executed);

        const expect = try replace_extension(init.gpa, fixture, ".stdout.expect");
        defer init.gpa.free(expect);
        if (try file_exists(init.io, expect)) {
            try assert_file_equals(init, expect, executed.stdout);
        } else if (executed.stdout.len != 0) {
            return error.UnexpectedWasmSmokeStdout;
        }
        try report_fixture(init, "wasm_run", fixture, .pass);
    }
}

const FixtureMode = enum { ok, err, compile_ok, compile_err };
const FixtureStatus = enum { pass, skip };

fn format_fixture_report(
    allocator: std.mem.Allocator,
    category: []const u8,
    fixture: []const u8,
    status: FixtureStatus,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "fixture-result category={s} name={s} status={s}\n", .{
        category,
        std.fs.path.basename(fixture),
        @tagName(status),
    });
}

fn report_fixture(init: std.process.Init, category: []const u8, fixture: []const u8, status: FixtureStatus) !void {
    if (!std.mem.eql(u8, init.environ_map.get("DO_HARNESS_FIXTURE_REPORT") orelse "0", "1")) return;
    const line = try format_fixture_report(init.gpa, category, fixture, status);
    defer init.gpa.free(line);
    try std.Io.File.stdout().writeStreamingAll(init.io, line);
}

const CompileExpectationKind = enum {
    wasi_bind,
    component_plan,
    wit,
    wit_dir,
    core_imports,
    core_shims,
    component_input,
    component_core,
};

fn classify_compile_expectation(path: []const u8) ?CompileExpectationKind {
    const entries = .{
        .{ .suffix = ".wasi_bind.expect", .kind = CompileExpectationKind.wasi_bind },
        .{ .suffix = ".component_plan.expect", .kind = CompileExpectationKind.component_plan },
        .{ .suffix = ".wit.expect", .kind = CompileExpectationKind.wit },
        .{ .suffix = ".wit_dir.expect", .kind = CompileExpectationKind.wit_dir },
        .{ .suffix = ".core_imports.expect", .kind = CompileExpectationKind.core_imports },
        .{ .suffix = ".core_shims.expect", .kind = CompileExpectationKind.core_shims },
        .{ .suffix = ".component_input.expect", .kind = CompileExpectationKind.component_input },
        .{ .suffix = ".component_core.expect", .kind = CompileExpectationKind.component_core },
    };
    inline for (entries) |entry| {
        if (std.mem.endsWith(u8, path, entry.suffix)) return entry.kind;
    }
    return null;
}

fn run_do_test_directory(
    init: std.process.Init,
    do_bin: []const u8,
    test_root: []const u8,
    directory_name: []const u8,
    temp_path: []const u8,
    lib_root: []const u8,
    stdlib_root: []const u8,
    mode: FixtureMode,
) !void {
    const directory = try join(init.gpa, test_root, directory_name);
    defer init.gpa.free(directory);
    const names = try collect_files(init.gpa, init.io, directory, ".do");
    defer free_names(init.gpa, names);

    for (names) |name| {
        if (std.mem.startsWith(u8, name, "fixture.")) continue;
        const fixture = try join(init.gpa, directory, name);
        defer init.gpa.free(fixture);
        const category = @tagName(mode);
        const status = switch (mode) {
            .ok => try run_ok_fixture(init, do_bin, fixture, temp_path, lib_root, stdlib_root),
            .err => blk: {
                try run_err_fixture(init, do_bin, fixture, lib_root);
                break :blk .pass;
            },
            .compile_ok => blk: {
                try run_compile_fixture(init, do_bin, fixture, temp_path, lib_root, true);
                break :blk .pass;
            },
            .compile_err => blk: {
                try run_compile_fixture(init, do_bin, fixture, temp_path, lib_root, false);
                break :blk .pass;
            },
        };
        try report_fixture(init, category, fixture, status);
    }
}

fn run_ok_fixture(
    init: std.process.Init,
    do_bin: []const u8,
    fixture: []const u8,
    temp_path: []const u8,
    lib_root: []const u8,
    stdlib_root: []const u8,
) !FixtureStatus {
    const output = try run_do_command(init, do_bin, "test", fixture, null, lib_root, null);
    defer init.gpa.free(output.stdout);
    defer init.gpa.free(output.stderr);
    defer init.gpa.free(output.command);
    if (output.exit_code() != 0) {
        try report_case_failure(init, output);
        unreachable;
    }

    const has_report = std.mem.indexOf(u8, output.stdout, "test \"") != null and
        std.mem.indexOf(u8, output.stdout, "ok:") != null;
    const skipped = std.mem.indexOf(u8, output.stdout, " ... skipped") != null;
    const passed = std.mem.indexOf(u8, output.stdout, " ... ok") != null;
    if (!has_report or (!passed and !skipped)) return error.FixtureContractMismatch;
    if (skipped) {
        const must_pass = try replace_extension(init.gpa, fixture, ".must_pass");
        defer init.gpa.free(must_pass);
        if (try file_exists(init.io, must_pass)) return error.FixtureUnexpectedSkip;
        const compiled_must_pass = try replace_extension(init.gpa, fixture, ".compiled_must_pass");
        defer init.gpa.free(compiled_must_pass);
        if (try file_exists(init.io, compiled_must_pass)) {
            const repo_root = init.environ_map.get("DO_HARNESS_REPO_ROOT") orelse
                return error.MissingHarnessEnvironment;
            try run_compiled_must_pass(init, repo_root, fixture, temp_path, stdlib_root);
            return status_after_compiled_must_pass();
        }
        return .skip;
    }
    return .pass;
}

fn status_after_compiled_must_pass() FixtureStatus {
    return .pass;
}

fn run_compiled_must_pass(
    init: std.process.Init,
    repo_root: []const u8,
    fixture: []const u8,
    temp_path: []const u8,
    stdlib_root: []const u8,
) !void {
    const wat = try fixture_output_path(init.gpa, temp_path, fixture, ".compiled.wat");
    defer init.gpa.free(wat);
    const wasm = try fixture_output_path(init.gpa, temp_path, fixture, ".compiled.wasm");
    defer init.gpa.free(wasm);
    const script = try join(init.gpa, repo_root, "src/build/test/run_compiled_test_case.mjs");
    defer init.gpa.free(script);
    const adapter = init.environ_map.get("DO_HARNESS_TOOLCHAIN_BIN") orelse
        return error.MissingHarnessEnvironment;
    const node = init.environ_map.get("NODE_BIN") orelse "node";
    const extra = [_][]const u8{ "--compiled", "-o", wat };
    var generated = try run_do_command(init, init.environ_map.get("DO_HARNESS_DO_BIN") orelse return error.MissingHarnessEnvironment, "test", fixture, &extra, stdlib_root, null);
    defer generated.deinit(init.gpa);
    try expect_success(init, &generated);

    const parse_argv = [_][]const u8{ adapter, "parse-core", wat, "-o", wasm };
    try run_success(init, .{ .argv = &parse_argv, .environ = init.environ_map });
    const node_argv = [_][]const u8{ node, script, wasm, wat };
    var executed = try process.run_checked(init.gpa, init.io, .{ .argv = &node_argv, .environ = init.environ_map });
    defer executed.deinit(init.gpa);
    try expect_success(init, &executed);
    try process.assert_stdout_contains(executed, " ... ok");
    try process.assert_stdout_contains(executed, "ok:");
}

fn run_std_fixture(init: std.process.Init, do_bin: []const u8, fixture: []const u8, lib_root: []const u8) !FixtureStatus {
    if (std.mem.eql(u8, std.fs.path.basename(fixture), "_.do")) return .pass;
    const output = try run_do_command(init, do_bin, "test", fixture, null, lib_root, null);
    defer init.gpa.free(output.stdout);
    defer init.gpa.free(output.stderr);
    defer init.gpa.free(output.command);
    if (output.exit_code() == 0) {
        const has_report = std.mem.indexOf(u8, output.stdout, "test \"") != null and
            std.mem.indexOf(u8, output.stdout, "ok:") != null;
        if (!has_report) return error.FixtureContractMismatch;
        if (std.mem.indexOf(u8, output.stdout, " ... skipped") != null) return .skip;
        return .pass;
    }
    if (std.mem.indexOf(u8, output.stderr, "NoTestDecl") != null) return .pass;
    try report_case_failure(init, output);
    unreachable;
}

fn run_std_library_matrix(init: std.process.Init, do_bin: []const u8, stdlib_root: []const u8) !void {
    const names = try collect_files(init.gpa, init.io, stdlib_root, ".do");
    defer free_names(init.gpa, names);
    for (names) |name| {
        const fixture = try join(init.gpa, stdlib_root, name);
        defer init.gpa.free(fixture);
        const status = try run_std_fixture(init, do_bin, fixture, stdlib_root);
        try report_fixture(init, "stdlib", fixture, status);
    }
}

fn run_err_fixture(init: std.process.Init, do_bin: []const u8, fixture: []const u8, lib_root: []const u8) !void {
    const expect = try replace_extension(init.gpa, fixture, ".expect");
    defer init.gpa.free(expect);
    if (!try file_exists(init.io, expect)) return error.MissingFixtureExpectation;

    const output = try run_do_command(init, do_bin, "test", fixture, null, lib_root, null);
    defer init.gpa.free(output.stdout);
    defer init.gpa.free(output.stderr);
    defer init.gpa.free(output.command);
    if (output.exit_code() == 0) return error.FixtureExpectedFailure;
    try assert_expected_lines(init, expect, output.stderr);
}

fn run_compile_fixture(
    init: std.process.Init,
    do_bin: []const u8,
    fixture: []const u8,
    temp_path: []const u8,
    lib_root: []const u8,
    expected_success: bool,
) !void {
    const wat = try fixture_output_path(init.gpa, temp_path, fixture, ".matrix.wat");
    defer init.gpa.free(wat);
    const expect = try replace_extension(init.gpa, fixture, ".expect");
    defer init.gpa.free(expect);
    const has_expect = try file_exists(init.io, expect);
    const host_export_expect = try replace_extension(init.gpa, fixture, ".host_export.expect");
    defer init.gpa.free(host_export_expect);
    const has_host_export_expect = try file_exists(init.io, host_export_expect);
    const host_manifest_expect = try replace_extension(init.gpa, fixture, ".host_manifest.expect");
    defer init.gpa.free(host_manifest_expect);
    const has_host_manifest_expect = try file_exists(init.io, host_manifest_expect);
    const host_manifest = try fixture_output_path(init.gpa, temp_path, fixture, ".host_manifest.json");
    defer init.gpa.free(host_manifest);
    var args = if (has_expect)
        try parse_build_args(init.gpa, init.io, expect)
    else
        std.ArrayList([]const u8).empty;
    defer free_args(init.gpa, &args);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(init.gpa);
    try argv.append(init.gpa, do_bin);
    try argv.append(init.gpa, "build");
    try argv.append(init.gpa, fixture);
    try argv.appendSlice(init.gpa, args.items);
    if (has_host_export_expect) {
        try argv.append(init.gpa, "--host-export");
        try argv.append(init.gpa, "--host-manifest");
        try argv.append(init.gpa, host_manifest);
    }
    try argv.append(init.gpa, "-o");
    try argv.append(init.gpa, wat);

    const env = [_]process.EnvVar{.{ .name = "DO_LIB_ROOT", .value = lib_root }};
    var output = try process.run_checked(init.gpa, init.io, .{
        .argv = argv.items,
        .environ = init.environ_map,
        .env = &env,
    });
    defer output.deinit(init.gpa);
    if (expected_success) {
        try expect_success(init, &output);
        if (!try file_exists(init.io, wat)) return error.FixtureMissingOutput;
        try process.assert_stdout_contains(output, "ok:");
        const wat_source = try std.Io.Dir.cwd().readFileAlloc(init.io, wat, init.gpa, .limited(64 * 1024 * 1024));
        defer init.gpa.free(wat_source);
        if (has_expect) try assert_expected_lines(init, expect, wat_source);
        if (has_host_export_expect) try assert_expected_lines(init, host_export_expect, wat_source);
        if (has_host_manifest_expect) {
            if (!try file_exists(init.io, host_manifest)) return error.FixtureMissingHostManifest;
            const manifest_source = try std.Io.Dir.cwd().readFileAlloc(init.io, host_manifest, init.gpa, .limited(16 * 1024 * 1024));
            defer init.gpa.free(manifest_source);
            try assert_expected_lines(init, host_manifest_expect, manifest_source);
        }
        try run_compile_wasi_expectations(init, do_bin, fixture, temp_path, lib_root, wat, wat_source);
    } else {
        if (output.exit_code() == 0) return error.FixtureExpectedFailure;
        try assert_expected_lines(init, expect, output.stderr);
    }
}

fn run_compile_wasi_expectations(
    init: std.process.Init,
    do_bin: []const u8,
    fixture: []const u8,
    temp_path: []const u8,
    lib_root: []const u8,
    wat: []const u8,
    wat_source: []const u8,
) !void {
    const repo_root = init.environ_map.get("DO_HARNESS_REPO_ROOT") orelse return error.MissingHarnessEnvironment;
    const toolchain_bin = init.environ_map.get("DO_HARNESS_TOOLCHAIN_BIN") orelse return error.MissingHarnessEnvironment;
    const lock_path = init.environ_map.get("DO_TOOLCHAIN_LOCK") orelse return error.MissingHarnessEnvironment;

    const sidecars = [_][]const u8{
        ".wasi_bind.expect",
        ".component_plan.expect",
        ".wit.expect",
        ".wit_dir.expect",
        ".core_imports.expect",
        ".core_shims.expect",
        ".component_input.expect",
        ".component_core.expect",
    };
    var has_sidecar = false;
    for (sidecars) |suffix| {
        const path = try replace_extension(init.gpa, fixture, suffix);
        defer init.gpa.free(path);
        if (try file_exists(init.io, path)) {
            has_sidecar = true;
            break;
        }
    }
    const has_manifest = std.mem.indexOf(u8, wat_source, ";; wasi-bind ") != null;
    if (!has_sidecar and !has_manifest) return;

    const node = try find_node_runtime(init);
    defer init.gpa.free(node);
    const script = try join(init.gpa, repo_root, "src/build/test/validate_wasi_bind_manifest.mjs");
    defer init.gpa.free(script);
    const registry = try join(init.gpa, repo_root, "doc/wit/wasi_registry.json");
    defer init.gpa.free(registry);

    if (has_manifest) {
        var result = try run_wasi_manifest_mode(init, repo_root, node, script, registry, lock_path, toolchain_bin, wat, null, null);
        defer result.deinit(init.gpa);
        try expect_success(init, &result);
    }

    const component_plan_expect = try replace_extension(init.gpa, fixture, ".component_plan.expect");
    defer init.gpa.free(component_plan_expect);
    const has_component_plan = try file_exists(init.io, component_plan_expect);
    if (has_component_plan) {
        var result = try run_wasi_manifest_mode(init, repo_root, node, script, registry, lock_path, toolchain_bin, wat, "--component-plan", null);
        defer result.deinit(init.gpa);
        try expect_success(init, &result);
        try assert_expected_lines(init, component_plan_expect, result.stdout);
    }

    const wit_expect = try replace_extension(init.gpa, fixture, ".wit.expect");
    defer init.gpa.free(wit_expect);
    const has_wit = try file_exists(init.io, wit_expect);
    const wit_dir_expect = try replace_extension(init.gpa, fixture, ".wit_dir.expect");
    defer init.gpa.free(wit_dir_expect);
    const has_wit_dir = try file_exists(init.io, wit_dir_expect);
    if (has_wit) {
        var result = try run_wasi_manifest_mode(init, repo_root, node, script, registry, lock_path, toolchain_bin, wat, "--wit", null);
        defer result.deinit(init.gpa);
        try expect_success(init, &result);
        try assert_expected_lines(init, wit_expect, result.stdout);
        if (!has_wit_dir) {
            const wit_path = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.wit");
            defer init.gpa.free(wit_path);
            try write_file(init, wit_path, result.stdout);
            var parsed = try run_adapter_command(init, toolchain_bin, &.{ "component-wit", wit_path });
            defer parsed.deinit(init.gpa);
            try expect_success(init, &parsed);
        }
    }

    if (has_wit_dir) {
        const wit_dir = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.wit-dir");
        defer init.gpa.free(wit_dir);
        var result = try run_wasi_manifest_mode(init, repo_root, node, script, registry, lock_path, toolchain_bin, wat, "--wit-dir", wit_dir);
        defer result.deinit(init.gpa);
        try expect_success(init, &result);
        const wit_dir_output = try collect_wit_dir_output(init, toolchain_bin, wit_dir, temp_path, fixture);
        defer init.gpa.free(wit_dir_output);
        try assert_expected_lines(init, wit_dir_expect, wit_dir_output);
    }

    const core_imports_expect = try replace_extension(init.gpa, fixture, ".core_imports.expect");
    defer init.gpa.free(core_imports_expect);
    if (try file_exists(init.io, core_imports_expect)) {
        var result = try run_wasi_manifest_mode(init, repo_root, node, script, registry, lock_path, toolchain_bin, wat, "--core-imports", null);
        defer result.deinit(init.gpa);
        try expect_success(init, &result);
        try assert_expected_lines(init, core_imports_expect, result.stdout);
    }

    const core_shims_expect = try replace_extension(init.gpa, fixture, ".core_shims.expect");
    defer init.gpa.free(core_shims_expect);
    if (try file_exists(init.io, core_shims_expect)) {
        var result = try run_wasi_manifest_mode(init, repo_root, node, script, registry, lock_path, toolchain_bin, wat, "--core-shims", null);
        defer result.deinit(init.gpa);
        try expect_success(init, &result);
        try assert_expected_lines(init, core_shims_expect, result.stdout);
        try parse_generated_core_shims(init, toolchain_bin, temp_path, fixture, result.stdout);
    }

    const component_input_expect = try replace_extension(init.gpa, fixture, ".component_input.expect");
    defer init.gpa.free(component_input_expect);
    const has_component_input = try file_exists(init.io, component_input_expect);
    if (has_component_input) {
        const component_input_dir = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.component-input");
        defer init.gpa.free(component_input_dir);
        var result = try run_wasi_manifest_mode(init, repo_root, node, script, registry, lock_path, toolchain_bin, wat, "--component-input-dir", component_input_dir);
        defer result.deinit(init.gpa);
        try expect_success(init, &result);

        const component_input_output = try collect_component_input_output(init, toolchain_bin, component_input_dir, temp_path, fixture);
        defer init.gpa.free(component_input_output);
        try assert_expected_lines(init, component_input_expect, component_input_output);
        const embedded = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.input.embedded.wasm");
        defer init.gpa.free(embedded);
        const component = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.input.component.wasm");
        defer init.gpa.free(component);
        const input_wit = try join(init.gpa, component_input_dir, "wit");
        defer init.gpa.free(input_wit);
        const input_core = try join(init.gpa, component_input_dir, "core_component.wat");
        defer init.gpa.free(input_core);
        try run_adapter_success(init, toolchain_bin, &.{
            "embed-component", input_wit, input_core, "imports", "--features", "none", "-o", embedded,
        });
        try run_adapter_success(init, toolchain_bin, &.{ "new-component", embedded, "-o", component });
        try run_adapter_success(init, toolchain_bin, &.{ "validate-component", component, "--features", "none" });

        const tool_component = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.input.tool.component.wasm");
        defer init.gpa.free(tool_component);
        var generated = try run_wasi_manifest_mode(init, repo_root, node, script, registry, lock_path, toolchain_bin, wat, "--component-wasm", tool_component);
        defer generated.deinit(init.gpa);
        try expect_success(init, &generated);
        try expect_file(init.io, tool_component);
    }

    const component_core_expect = try replace_extension(init.gpa, fixture, ".component_core.expect");
    defer init.gpa.free(component_core_expect);
    if (try file_exists(init.io, component_core_expect)) {
        const component_core = try fixture_output_path(init.gpa, temp_path, fixture, ".component-core.wat");
        defer init.gpa.free(component_core);
        const args = [_][]const u8{ "build", fixture, "--component-core", "-o", component_core };
        var built = try run_do_args(init, do_bin, &args, lib_root, null, 120_000);
        defer built.deinit(init.gpa);
        try expect_success(init, &built);
        const source = try read_file(init, component_core);
        defer init.gpa.free(source);
        try assert_expected_lines(init, component_core_expect, source);
        if (std.mem.indexOf(u8, source, "(memory (export \"memory\")") != null) return error.ComponentCoreExportsPlainMemory;
        if (has_component_input) {
            const input_root = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.component-core-input");
            defer init.gpa.free(input_root);
            const input_wit = try join(init.gpa, input_root, "wit");
            defer init.gpa.free(input_wit);
            var wit_result = try run_wasi_manifest_mode(init, repo_root, node, script, registry, lock_path, toolchain_bin, component_core, "--wit-dir", input_wit);
            defer wit_result.deinit(init.gpa);
            try expect_success(init, &wit_result);
            const embedded = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.component-core.embedded.wasm");
            defer init.gpa.free(embedded);
            const component = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.component-core.component.wasm");
            defer init.gpa.free(component);
            try run_adapter_success(init, toolchain_bin, &.{ "embed-component", input_wit, component_core, "imports", "--features", "none", "-o", embedded });
            try run_adapter_success(init, toolchain_bin, &.{ "new-component", embedded, "-o", component });
            try run_adapter_success(init, toolchain_bin, &.{ "validate-component", component, "--features", "none" });
        }
    }
}

fn run_wasi_manifest_mode(
    init: std.process.Init,
    cwd: []const u8,
    node: []const u8,
    script: []const u8,
    registry: []const u8,
    lock_path: []const u8,
    toolchain_bin: []const u8,
    wat: []const u8,
    mode: ?[]const u8,
    output_path: ?[]const u8,
) !process.CommandResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(init.gpa);
    try argv.append(init.gpa, node);
    try argv.append(init.gpa, script);
    try argv.append(init.gpa, "--registry");
    try argv.append(init.gpa, registry);
    if (mode) |value| {
        try argv.append(init.gpa, value);
        if (output_path) |path| try argv.append(init.gpa, path);
    }
    try argv.append(init.gpa, wat);
    const env = [_]process.EnvVar{
        .{ .name = "DO_TOOLCHAIN_BIN", .value = toolchain_bin },
        .{ .name = "DO_TOOLCHAIN_LOCK", .value = lock_path },
    };
    return process.run_checked(init.gpa, init.io, .{
        .argv = argv.items,
        .environ = init.environ_map,
        .env = &env,
        .cwd = cwd,
        .timeout_ms = 120_000,
    });
}

fn run_adapter_command(init: std.process.Init, toolchain_bin: []const u8, args: []const []const u8) !process.CommandResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(init.gpa);
    try argv.append(init.gpa, toolchain_bin);
    try argv.appendSlice(init.gpa, args);
    return process.run_checked(init.gpa, init.io, .{ .argv = argv.items, .environ = init.environ_map });
}

fn run_adapter_success(init: std.process.Init, toolchain_bin: []const u8, args: []const []const u8) !void {
    var result = try run_adapter_command(init, toolchain_bin, args);
    defer result.deinit(init.gpa);
    try expect_success(init, &result);
}

fn parse_generated_core_shims(
    init: std.process.Init,
    toolchain_bin: []const u8,
    temp_path: []const u8,
    fixture: []const u8,
    source: []const u8,
) !void {
    const module = try fixture_output_path(init.gpa, temp_path, fixture, ".core-shims.module.wat");
    defer init.gpa.free(module);
    var wrapped: std.ArrayList(u8) = .empty;
    defer wrapped.deinit(init.gpa);
    try wrapped.appendSlice(init.gpa, "(module\n");
    try wrapped.appendSlice(init.gpa, source);
    try wrapped.appendSlice(init.gpa, "\n)\n");
    try write_file(init, module, wrapped.items);
    const wasm = try fixture_output_path(init.gpa, temp_path, fixture, ".core-shims.module.wasm");
    defer init.gpa.free(wasm);
    try run_adapter_success(init, toolchain_bin, &.{ "parse-core", module, "-o", wasm });
}

fn collect_wit_dir_output(
    init: std.process.Init,
    toolchain_bin: []const u8,
    wit_dir: []const u8,
    temp_path: []const u8,
    fixture: []const u8,
) ![]u8 {
    const parsed = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.wit-dir.parsed");
    defer init.gpa.free(parsed);
    var result = try run_adapter_command(init, toolchain_bin, &.{ "component-wit", wit_dir });
    defer result.deinit(init.gpa);
    try expect_success(init, &result);
    try write_file(init, parsed, result.stdout);
    return read_file(init, parsed);
}

fn collect_component_input_output(
    init: std.process.Init,
    toolchain_bin: []const u8,
    input_dir: []const u8,
    temp_path: []const u8,
    fixture: []const u8,
) ![]u8 {
    const output_path = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.component-input.txt");
    defer init.gpa.free(output_path);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(init.gpa);
    const files = [_][]const u8{
        "metadata.json",
        "component_plan.json",
        "core_imports.wat",
        "core_shims.wat",
    };
    for (files) |name| {
        const path = try join(init.gpa, input_dir, name);
        defer init.gpa.free(path);
        const source = try read_file(init, path);
        defer init.gpa.free(source);
        try output.appendSlice(init.gpa, source);
    }

    const wit_dir = try join(init.gpa, input_dir, "wit");
    defer init.gpa.free(wit_dir);
    var wit_result = try run_adapter_command(init, toolchain_bin, &.{ "component-wit", wit_dir });
    defer wit_result.deinit(init.gpa);
    try expect_success(init, &wit_result);
    try output.appendSlice(init.gpa, wit_result.stdout);

    const shims_module = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.component-input.shims.module.wat");
    defer init.gpa.free(shims_module);
    const shims = try join(init.gpa, input_dir, "core_shims.wat");
    defer init.gpa.free(shims);
    const shims_source = try read_file(init, shims);
    defer init.gpa.free(shims_source);
    var wrapped: std.ArrayList(u8) = .empty;
    defer wrapped.deinit(init.gpa);
    try wrapped.appendSlice(init.gpa, "(module\n");
    try wrapped.appendSlice(init.gpa, shims_source);
    try wrapped.appendSlice(init.gpa, "\n)\n");
    try write_file(init, shims_module, wrapped.items);
    const shims_wasm = try fixture_output_path(init.gpa, temp_path, fixture, ".wasi.component-input.shims.module.wasm");
    defer init.gpa.free(shims_wasm);
    try run_adapter_success(init, toolchain_bin, &.{ "parse-core", shims_module, "-o", shims_wasm });
    try write_file(init, output_path, output.items);
    return read_file(init, output_path);
}

fn run_gc_default_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
) !void {
    const gc_root = try join(init.gpa, repo_root, "examples/gc-p3-runtime");
    defer init.gpa.free(gc_root);
    const lib_root = try join(init.gpa, repo_root, "lib");
    defer init.gpa.free(lib_root);
    const names = try collect_files(init.gpa, init.io, gc_root, ".do");
    defer free_names(init.gpa, names);

    var fixture_count: usize = 0;
    for (names) |name| {
        if (std.mem.eql(u8, name, "imported-text-helper.do") or std.mem.eql(u8, name, "imported_text_helper.do") or
            std.mem.eql(u8, name, "map-u32-u32-lower.do") or std.mem.eql(u8, name, "map-u32-u32-lift.do")) continue;
        const fixture = try join(init.gpa, gc_root, name);
        defer init.gpa.free(fixture);
        const wat = try fixture_output_path(init.gpa, temp_path, fixture, ".gc.wat");
        defer init.gpa.free(wat);
        const argv = [_][]const u8{ do_bin, "build", fixture, "-o", wat };
        const env = [_]process.EnvVar{.{ .name = "DO_LIB_ROOT", .value = lib_root }};
        var output = try process.run_checked(init.gpa, init.io, .{
            .argv = &argv,
            .environ = init.environ_map,
            .env = &env,
        });
        defer output.deinit(init.gpa);
        try expect_success(init, &output);
        const wat_source = try std.Io.Dir.cwd().readFileAlloc(init.io, wat, init.gpa, .limited(64 * 1024 * 1024));
        defer init.gpa.free(wat_source);
        try assert_gc_default_wat(name, wat_source);

        const wasm = try fixture_output_path(init.gpa, temp_path, fixture, ".gc.wasm");
        defer init.gpa.free(wasm);
        const parse_args = [_][]const u8{ toolchain_bin, "parse-core", wat, "-o", wasm };
        var parsed = try process.run_checked(init.gpa, init.io, .{ .argv = &parse_args, .environ = init.environ_map });
        defer parsed.deinit(init.gpa);
        try expect_success(init, &parsed);
        if (!try file_exists(init.io, wasm)) return error.MissingCompiledArtifact;
        fixture_count += 1;
    }
        if (fixture_count != 86) return error.GcFixtureManifestDrift;
}

fn assert_gc_default_wat(name: []const u8, source: []const u8) !void {
    if (std.mem.indexOf(u8, source, "__arc_") != null) return error.ObsoleteArcMarker;
    if (std.mem.eql(u8, name, "scalar-call-graph.do")) {
        if (std.mem.indexOf(u8, source, ";; gc-sync ") == null or
            std.mem.indexOf(u8, source, "call $leaf") == null or
            std.mem.indexOf(u8, source, "call $middle") == null) return error.GcCallChainMarkerMissing;
        return;
    }
    if (std.mem.eql(u8, name, "scalar-control-flow.do")) {
        if (std.mem.indexOf(u8, source, ";; gc-sync ") == null or
            std.mem.indexOf(u8, source, ";; gc-root branch_join") == null or
            std.mem.indexOf(u8, source, ";; gc-root guard_join") == null) return error.GcJoinMarkerMissing;
        return;
    }
    if (std.mem.eql(u8, name, "scalar-leaf.do")) {
        if (std.mem.indexOf(u8, source, ";; gc-sync ") == null) return error.GcMarkerMissing;
        return;
    }
    if (std.mem.indexOf(u8, source, ";; gc-sync ") == null or
        std.mem.indexOf(u8, source, "$do_") == null) return error.GcMarkerMissing;
}

fn run_compiler_smoke(init: std.process.Init, repo_root: []const u8, do_bin: []const u8, temp_path: []const u8) !void {
    const source = try join(init.gpa, repo_root, "src/build/test/compile_ok/01_start_entry_valid.do");
    defer init.gpa.free(source);
    const output = try join(init.gpa, temp_path, "compiler-smoke.wat");
    defer init.gpa.free(output);
    const argv = [_][]const u8{ do_bin, "build", source, "-o", output };
    const lib_root = try join(init.gpa, repo_root, "lib");
    defer init.gpa.free(lib_root);
    const env = [_]process.EnvVar{.{ .name = "DO_LIB_ROOT", .value = lib_root }};
    var result = try process.run_checked(init.gpa, init.io, .{
        .argv = &argv,
        .environ = init.environ_map,
        .env = &env,
    });
    defer result.deinit(init.gpa);
    try expect_success(init, &result);
    try expect_file(init.io, output);
}

fn run_wit_map(init: std.process.Init, do_bin: []const u8, temp_path: []const u8) !void {
    const input = try join(init.gpa, temp_path, "map.wit");
    defer init.gpa.free(input);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = input, .data = map_source });

    const argv = [_][]const u8{ do_bin, "wit", "check", input, "--world", "probe" };
    var result = try process.run_checked(init.gpa, init.io, .{ .argv = &argv, .environ = init.environ_map });
    defer result.deinit(init.gpa);
    try expect_success(init, &result);
    try process.assert_stdout_contains(result, "ok: demo:maps world=probe");
}

fn assemble_component(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
) !ComponentFixture {
    const source = try join(init.gpa, repo_root, "examples/p3-runtime/wait-for-component.do");
    defer init.gpa.free(source);
    const wat = try join(init.gpa, temp_path, "wait-for-core.wat");
    errdefer init.gpa.free(wat);
    const wit = try join(init.gpa, temp_path, "wait-for-component.wit");
    errdefer init.gpa.free(wit);
    const core = try join(init.gpa, temp_path, "wait-for-core.wasm");
    errdefer init.gpa.free(core);
    const embedded = try join(init.gpa, temp_path, "wait-for-embedded.wasm");
    errdefer init.gpa.free(embedded);
    const component = try join(init.gpa, temp_path, "wait-for.component.wasm");
    errdefer init.gpa.free(component);

    const build_argv = [_][]const u8{
        do_bin, "build", source, "--p3-async-component", "--p3-wit-output", wit, "-o", wat,
    };
    const lib_root = try join(init.gpa, repo_root, "lib");
    defer init.gpa.free(lib_root);
    const lib_env = [_]process.EnvVar{.{ .name = "DO_LIB_ROOT", .value = lib_root }};
    try run_success(init, .{ .argv = &build_argv, .environ = init.environ_map, .env = &lib_env });
    try expect_file(init.io, wat);
    try expect_file(init.io, wit);

    const parse_argv = [_][]const u8{ toolchain_bin, "parse-core", wat, "-o", core };
    try run_success(init, .{ .argv = &parse_argv, .environ = init.environ_map });
    const embed_argv = [_][]const u8{ toolchain_bin, "embed-component", wit, core, "probe", "-o", embedded };
    try run_success(init, .{ .argv = &embed_argv, .environ = init.environ_map });
    const new_argv = [_][]const u8{ toolchain_bin, "new-component", embedded, "-o", component };
    try run_success(init, .{ .argv = &new_argv, .environ = init.environ_map });
    const validate_argv = [_][]const u8{ toolchain_bin, "validate-component", component };
    try run_success(init, .{ .argv = &validate_argv, .environ = init.environ_map });

    return .{ .wat = wat, .wit = wit, .core = core, .embedded = embedded, .component = component };
}

fn assert_component_fixture(init: std.process.Init, fixture: ComponentFixture) !void {
    try expect_file(init.io, fixture.component);
    const adapter = init.environ_map.get("DO_HARNESS_TOOLCHAIN_BIN") orelse return error.MissingHarnessEnvironment;
    const argv = [_][]const u8{ adapter, "print-component", fixture.component };
    var result = try process.run_checked(init.gpa, init.io, .{ .argv = &argv, .environ = init.environ_map });
    defer result.deinit(init.gpa);
    try expect_success(init, &result);
    try process.assert_stdout_contains(result, "[async-lift]run");
}

fn run_assembly_validation(
    init: std.process.Init,
    repo_root: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
    fixture: ComponentFixture,
) !void {
    const helper = try join(init.gpa, repo_root, "examples/p3-runtime/assemble_async_component.sh");
    defer init.gpa.free(helper);
    const component = try join(init.gpa, temp_path, "helper-assembled.component.wasm");
    defer init.gpa.free(component);
    const args = [_][]const u8{ helper, fixture.wit, fixture.core, "probe", component };
    var assembled = try process.run_checked(init.gpa, init.io, .{
        .argv = &args,
        .environ = init.environ_map,
        .cwd = repo_root,
        .timeout_ms = 120_000,
    });
    defer assembled.deinit(init.gpa);
    try expect_success(init, &assembled);
    try process.assert_stdout_contains(assembled, "target=wasmtime-p3");
    try process.assert_stdout_contains(assembled, "toolchain-adapter=current-only");
    try process.assert_stdout_contains(assembled, "async-names=legacy");
    try expect_file(init.io, component);

    const validate_args = [_][]const u8{ toolchain_bin, "validate-component", component };
    var validated = try process.run_checked(init.gpa, init.io, .{ .argv = &validate_args, .environ = init.environ_map });
    defer validated.deinit(init.gpa);
    try expect_success(init, &validated);

    const probe_args = [_][]const u8{ toolchain_bin, "probe" };
    var probe = try process.run_checked(init.gpa, init.io, .{ .argv = &probe_args, .environ = init.environ_map });
    defer probe.deinit(init.gpa);
    try expect_success(init, &probe);
    try process.assert_stdout_contains(probe, "\"schema\":1");
    try process.assert_stdout_contains(probe, "wasm-tools 1.258.0");
    try process.assert_stdout_contains(probe, "wasmtime 48.0.1");
}

fn run_wit_snapshot_validation(
    init: std.process.Init,
    repo_root: []const u8,
    toolchain_bin: []const u8,
) !void {
    const wit = try join(init.gpa, repo_root, "examples/p3-runtime/wit/wasi-clocks-0.3.0.wit");
    defer init.gpa.free(wit);
    const manifest_path = try join(init.gpa, repo_root, "examples/p3-runtime/p3-clocks-manifest.json");
    defer init.gpa.free(manifest_path);
    const manifest_source = try read_file(init, manifest_path);
    defer init.gpa.free(manifest_source);
    const Manifest = struct {
        wit_sha256: []const u8,
        package: []const u8,
        interface: []const u8,
        member: []const u8,
        effect: []const u8,
    };
    var manifest = try std.json.parseFromSlice(Manifest, init.gpa, manifest_source, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    const actual_hash = try file_sha256_hex(init, wit);
    if (!std.mem.eql(u8, manifest.value.wit_sha256, &actual_hash)) return error.WitHashMismatch;

    const wit_args = [_][]const u8{ toolchain_bin, "component-wit", wit };
    var wit_output = try process.run_checked(init.gpa, init.io, .{ .argv = &wit_args, .environ = init.environ_map });
    defer wit_output.deinit(init.gpa);
    try expect_success(init, &wit_output);
    try process.assert_stdout_contains(wit_output, manifest.value.package);
    try process.assert_stdout_contains(wit_output, "interface monotonic-clock");
    try process.assert_stdout_contains(wit_output, manifest.value.member);
    try process.assert_stdout_contains(wit_output, manifest.value.effect);

    const resource_wit = try join(init.gpa, repo_root, "examples/p3-runtime/wit/resource-probe.wit");
    defer init.gpa.free(resource_wit);
    const resource_args = [_][]const u8{ toolchain_bin, "component-wit", resource_wit };
    var resource_output = try process.run_checked(init.gpa, init.io, .{ .argv = &resource_args, .environ = init.environ_map });
    defer resource_output.deinit(init.gpa);
    try expect_success(init, &resource_output);
    try process.assert_stdout_contains(resource_output, "resource ticket");
}

fn run_component_template_validation(
    init: std.process.Init,
    repo_root: []const u8,
    toolchain_bin: []const u8,
) !void {
    for (component_template_cases) |case| {
        const wit = try join(init.gpa, repo_root, case.wit);
        defer init.gpa.free(wit);
        const args = [_][]const u8{ toolchain_bin, "embed-component-template", wit, case.world };
        var result = try process.run_checked(init.gpa, init.io, .{
            .argv = &args,
            .environ = init.environ_map,
            .cwd = repo_root,
            .timeout_ms = 120_000,
        });
        defer result.deinit(init.gpa);
        try expect_success(init, &result);
        if (result.stderr.len != 0 or result.stdout.len == 0) return error.UnexpectedCommandOutput;
        for (case.markers) |marker| try process.assert_stdout_contains(result, marker);
    }
}

fn run_tool_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    temp_path: []const u8,
) !void {
    const test_root = try join(init.gpa, repo_root, "src/build/test");
    defer init.gpa.free(test_root);
    const compile_ok = try join(init.gpa, test_root, "compile_ok/01_start_entry_valid.do");
    defer init.gpa.free(compile_ok);
    const compiled_ok = try join(init.gpa, test_root, "compiled_ok/01_compiled_test_entry.do");
    defer init.gpa.free(compiled_ok);
    const validator = try join(init.gpa, test_root, "validate_wasi_bind_manifest.mjs");
    defer init.gpa.free(validator);
    const manifest_tool = try join(init.gpa, test_root, "test_wasi_bind_manifest_tool.mjs");
    defer init.gpa.free(manifest_tool);
    const lib_root = try join(init.gpa, repo_root, "lib");
    defer init.gpa.free(lib_root);

    const node = try find_node_runtime(init);
    defer init.gpa.free(node);
    const manifest_args = [_][]const u8{ node, manifest_tool, validator, temp_path };
    var manifest = try process.run_checked(init.gpa, init.io, .{
        .argv = &manifest_args,
        .environ = init.environ_map,
        .cwd = repo_root,
        .timeout_ms = 120_000,
    });
    defer manifest.deinit(init.gpa);
    try expect_success(init, &manifest);
    try process.assert_stdout_contains(manifest, "ok: wasi-bind manifest tool");

    const build_output = try std.fmt.allocPrint(init.gpa, "{s}/cli-output-order-build.wat", .{temp_path});
    defer init.gpa.free(build_output);
    const test_output = try std.fmt.allocPrint(init.gpa, "{s}/cli-output-order-test.wat", .{temp_path});
    defer init.gpa.free(test_output);
    const build_args = [_][]const u8{ "build", "-o", build_output, compile_ok };
    var built = try run_do_args(init, do_bin, &build_args, lib_root, repo_root, 120_000);
    defer built.deinit(init.gpa);
    try expect_success(init, &built);
    try process.assert_stdout_contains(built, "ok:");
    try expect_file(init.io, build_output);

    const compiled_args = [_][]const u8{ "test", "--compiled", "-o", test_output, compiled_ok };
    var compiled = try run_do_args(init, do_bin, &compiled_args, lib_root, repo_root, 120_000);
    defer compiled.deinit(init.gpa);
    try expect_success(init, &compiled);
    try process.assert_stdout_contains(compiled, "ok:");
    try expect_file(init.io, test_output);

    try expect_do_failure_with_marker(init, do_bin, lib_root, repo_root, &.{ "build", compile_ok, "--bad" }, "error[UnexpectedCliArg]");
    try expect_do_failure_with_marker(init, do_bin, lib_root, repo_root, &.{ "build", compile_ok, compile_ok }, "error[UnexpectedCliArg]");
    try expect_do_failure_with_marker(init, do_bin, lib_root, repo_root, &.{ "run", compile_ok, "--bad" }, "error[UnexpectedCliArg]");
    try expect_do_failure_with_marker(init, do_bin, lib_root, repo_root, &.{ "run", compile_ok, compile_ok }, "error[UnexpectedCliArg]");
    try expect_do_failure_with_marker(init, do_bin, lib_root, repo_root, &.{ "test", "ok/01_path_get_single.do", "-o", build_output }, "error[OutputRequiresCompiledTest]");
}

fn run_external_dependency_negative_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    temp_path: []const u8,
) !void {
    const test_root = try join(init.gpa, repo_root, "src/build/test");
    defer init.gpa.free(test_root);
    const fixture = try join(init.gpa, test_root, "run/01_start_scalar.do");
    defer init.gpa.free(fixture);
    const lib_root = try join(init.gpa, test_root, "lib");
    defer init.gpa.free(lib_root);

    const missing_tools_dir = try std.fmt.allocPrint(init.gpa, "{s}/missing-wasm-tools", .{temp_path});
    defer init.gpa.free(missing_tools_dir);
    var missing_tools = try std.Io.Dir.cwd().createDirPathOpen(init.io, missing_tools_dir, .{});
    missing_tools.close(init.io);
    const missing_tools_env = [_]process.EnvVar{
        .{ .name = "PATH", .value = missing_tools_dir },
    };
    var wasm_missing = try run_do_args_with_env(init, do_bin, &.{ "run", fixture }, lib_root, repo_root, 120_000, &missing_tools_env);
    defer wasm_missing.deinit(init.gpa);
    try expect_external_failure(&wasm_missing, "error[MissingExternalTool]: wasm-tools not found");

    const wasm_tools = try find_executable(init, "wasm-tools");
    defer init.gpa.free(wasm_tools);
    const node_tools_dir = try std.fmt.allocPrint(init.gpa, "{s}/missing-node-tools", .{temp_path});
    defer init.gpa.free(node_tools_dir);
    var node_tools = try std.Io.Dir.cwd().createDirPathOpen(init.io, node_tools_dir, .{});
    defer node_tools.close(init.io);
    try node_tools.symLink(init.io, wasm_tools, "wasm-tools", .{});
    const missing_node = try std.fmt.allocPrint(init.gpa, "{s}/missing-node", .{node_tools_dir});
    defer init.gpa.free(missing_node);
    const missing_node_env = [_]process.EnvVar{
        .{ .name = "PATH", .value = node_tools_dir },
        .{ .name = "NODE_BIN", .value = missing_node },
    };
    var node_missing = try run_do_args_with_env(init, do_bin, &.{ "run", fixture }, lib_root, repo_root, 120_000, &missing_node_env);
    defer node_missing.deinit(init.gpa);
    try expect_external_failure(&node_missing, "error[MissingExternalTool]: node not found");
}

fn run_socket_abi_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    temp_path: []const u8,
) !void {
    const test_root = try join(init.gpa, repo_root, "src/build/test");
    defer init.gpa.free(test_root);
    const lib_root = try join(init.gpa, repo_root, "lib");
    defer init.gpa.free(lib_root);
    const fixture_names = [_][]const u8{
        "compile_ok/291_wasi_tcp_create_union.do",
        "compile_ok/292_wasi_tcp_bind_payload_addr.do",
        "compile_ok/296_wasi_tcp_bind_ipv6_payload_addr.do",
        "compile_ok/297_wasi_tcp_create_dynamic_family.do",
    };
    var wat_paths: [fixture_names.len][]u8 = undefined;
    var wat_count: usize = 0;
    defer {
        for (wat_paths[0..wat_count]) |path| init.gpa.free(path);
    }
    for (fixture_names, 0..) |fixture_name, index| {
        const fixture = try join(init.gpa, test_root, fixture_name);
        defer init.gpa.free(fixture);
        wat_paths[index] = try fixture_output_path(init.gpa, temp_path, fixture, ".socket.wat");
        wat_count += 1;
        const build_args = [_][]const u8{ "build", fixture, "-o", wat_paths[index] };
        var built = try run_do_args(init, do_bin, &build_args, lib_root, repo_root, 120_000);
        defer built.deinit(init.gpa);
        try expect_success(init, &built);
        try expect_file(init.io, wat_paths[index]);
    }

    const node = try find_node_runtime(init);
    defer init.gpa.free(node);
    const socket_script = try join(init.gpa, test_root, "test_socket_abi.mjs");
    defer init.gpa.free(socket_script);
    const args = [_][]const u8{ node, socket_script, wat_paths[0], wat_paths[1], wat_paths[2], wat_paths[3] };
    var result = try process.run_checked(init.gpa, init.io, .{
        .argv = &args,
        .environ = init.environ_map,
        .cwd = repo_root,
        .timeout_ms = 120_000,
    });
    defer result.deinit(init.gpa);
    try expect_success(init, &result);
    try process.assert_stdout_contains(result, "ok: socket ABI");
}

fn run_structural_gate(init: std.process.Init, repo_root: []const u8) !void {
    const build_root = try join(init.gpa, repo_root, "src/build");
    defer init.gpa.free(build_root);
    const src_root = try join(init.gpa, repo_root, "src");
    defer init.gpa.free(src_root);
    try structural_checks.check_module_tree(init.gpa, init.io, build_root);
    try structural_checks.check_generated_text_tree(init.gpa, init.io, src_root);
}

fn run_gc_core_oracle(init: std.process.Init, repo_root: []const u8, temp_path: []const u8) !void {
    const toolchain = init.environ_map.get("DO_HARNESS_TOOLCHAIN_BIN") orelse
        return error.MissingHarnessEnvironment;
    const zig_name = init.environ_map.get("ZIG_BIN") orelse "zig";
    const zig_bin = try find_executable(init, zig_name);
    defer init.gpa.free(zig_bin);
    const probe = try join(init.gpa, repo_root, "src/build/gc_sync_probe.zig");
    defer init.gpa.free(probe);
    const example_root = try join(init.gpa, repo_root, "examples/gc-p3-runtime");
    defer init.gpa.free(example_root);
    const lib_root = try join(init.gpa, repo_root, "lib");
    defer init.gpa.free(lib_root);

    for (gc_core_oracle_cases) |case| {
        const fixture = try join(init.gpa, example_root, case.fixture);
        defer init.gpa.free(fixture);
        const stem = std.fs.path.basename(case.fixture)[0 .. std.fs.path.basename(case.fixture).len - ".do".len];
        const wat = try std.fmt.allocPrint(init.gpa, "{s}/{s}.gc-oracle.wat", .{ temp_path, stem });
        defer init.gpa.free(wat);
        if (case.mode) |mode| {
            const args = [_][]const u8{ zig_bin, "run", probe, "--", fixture, wat, mode };
            var generated = try process.run_checked(init.gpa, init.io, .{
                .argv = &args,
                .environ = init.environ_map,
                .cwd = repo_root,
                .timeout_ms = 120_000,
            });
            defer generated.deinit(init.gpa);
            try expect_success(init, &generated);
        } else {
            const do_bin = init.environ_map.get("DO_HARNESS_DO_BIN") orelse return error.MissingHarnessEnvironment;
            const build_args = [_][]const u8{ "build", fixture, "--gc-core", "-o", wat };
            var generated = try run_do_args(init, do_bin, &build_args, lib_root, repo_root, 120_000);
            defer generated.deinit(init.gpa);
            try expect_success(init, &generated);
        }
        try expect_file(init.io, wat);

        const wasm = try std.fmt.allocPrint(init.gpa, "{s}.wasm", .{wat});
        defer init.gpa.free(wasm);
        var parsed = try run_adapter_command(init, toolchain, &.{ "parse-core", wat, "-o", wasm });
        defer parsed.deinit(init.gpa);
        try expect_success(init, &parsed);

        const compiled = try std.fmt.allocPrint(init.gpa, "{s}.compiled", .{wat});
        defer init.gpa.free(compiled);
        var compiled_result = try run_adapter_command(init, toolchain, &.{ "compile-core-gc", wat, "-o", compiled });
        defer compiled_result.deinit(init.gpa);
        try expect_success(init, &compiled_result);
        try expect_file(init.io, compiled);

        var invoked = try run_adapter_command(init, toolchain, &.{ "invoke-core-gc", wat, "--export", "probe" });
        defer invoked.deinit(init.gpa);
        try expect_success(init, &invoked);
        const result = std.mem.trim(u8, invoked.stdout, " \t\r\n");
        if (!std.mem.eql(u8, result, "27815")) return error.GcCoreOracleMismatch;
    }
}

fn run_map_core_probe(
    init: std.process.Init,
    repo_root: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
) !void {
    const zig_name = init.environ_map.get("ZIG_BIN") orelse "zig";
    const zig_bin = try find_executable(init, zig_name);
    defer init.gpa.free(zig_bin);
    const probe = try join(init.gpa, repo_root, "src/gc_marshal_map_probe_main.zig");
    defer init.gpa.free(probe);

    const value_kinds = [_][]const u8{ "u32", "text" };
    const directions = [_][]const u8{ "lower", "lift" };
    for (value_kinds) |value_kind| {
        for (directions) |direction| {
            const wat = try std.fmt.allocPrint(init.gpa, "{s}/map-{s}-{s}.wat", .{ temp_path, value_kind, direction });
            defer init.gpa.free(wat);
            const wasm = try std.fmt.allocPrint(init.gpa, "{s}/map-{s}-{s}.wasm", .{ temp_path, value_kind, direction });
            defer init.gpa.free(wasm);

            var argv: std.ArrayList([]const u8) = .empty;
            defer argv.deinit(init.gpa);
            try argv.appendSlice(init.gpa, &.{ zig_bin, "run", probe, "--", direction });
            if (std.mem.eql(u8, value_kind, "text")) try argv.append(init.gpa, value_kind);
            try argv.append(init.gpa, wat);

            var generated = try process.run_checked(init.gpa, init.io, .{
                .argv = argv.items,
                .environ = init.environ_map,
                .cwd = repo_root,
                .timeout_ms = 120_000,
            });
            defer generated.deinit(init.gpa);
            try expect_success(init, &generated);
            try expect_file(init.io, wat);

            const source = try read_file(init, wat);
            defer init.gpa.free(source);
            if (std.mem.indexOf(u8, source, "(type $do_map") == null) return error.MapCoreTypeMissing;
            if (std.mem.eql(u8, value_kind, "u32")) {
                if (std.mem.indexOf(u8, source, "(type $do_u32") == null) return error.MapCoreScalarTypeMissing;
            } else if (std.mem.indexOf(u8, source, "(type $do_text_array") == null) {
                return error.MapCoreTextTypeMissing;
            }
            const canonical_type = if (std.mem.eql(u8, direction, "lower"))
                "(type $canonical_lower (func (param i32 i32)))"
            else
                "(type $canonical_lift (func (param i32)))";
            if (std.mem.indexOf(u8, source, canonical_type) == null) return error.MapCoreCanonicalTypeMissing;

            var parsed = try run_adapter_command(init, toolchain_bin, &.{ "parse-core", wat, "-o", wasm });
            defer parsed.deinit(init.gpa);
            try expect_success(init, &parsed);
            try expect_file(init.io, wasm);

            var validated = try run_adapter_command(init, toolchain_bin, &.{ "validate-core", wasm });
            defer validated.deinit(init.gpa);
            try expect_success(init, &validated);
        }
    }
}

fn run_map_sync_component(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
) !void {
    const lib_root = try join(init.gpa, repo_root, "lib");
    defer init.gpa.free(lib_root);
    const manifest = try join(init.gpa, repo_root, "examples/p3-runtime/rust-host-runner/Cargo.toml");
    defer init.gpa.free(manifest);
    const linker = try join(init.gpa, repo_root, "examples/p3-runtime/rust-host-runner/zig-cc.sh");
    defer init.gpa.free(linker);
    const env = [_]process.EnvVar{
        .{ .name = "CC", .value = linker },
        .{ .name = "CXX", .value = linker },
        .{ .name = "CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER", .value = linker },
    };

    for (map_sync_component_cases) |case| {
        const source = try join(init.gpa, repo_root, case.source);
        defer init.gpa.free(source);
        const wit = try join(init.gpa, repo_root, case.wit);
        defer init.gpa.free(wit);
        const stem = std.fs.path.basename(case.source)[0 .. std.fs.path.basename(case.source).len - ".do".len];
        const wat = try std.fmt.allocPrint(init.gpa, "{s}/{s}.map-sync.wat", .{ temp_path, stem });
        defer init.gpa.free(wat);
        const core = try std.fmt.allocPrint(init.gpa, "{s}/{s}.map-sync.wasm", .{ temp_path, stem });
        defer init.gpa.free(core);
        const embedded = try std.fmt.allocPrint(init.gpa, "{s}/{s}.map-sync.embedded.wasm", .{ temp_path, stem });
        defer init.gpa.free(embedded);
        const component = try std.fmt.allocPrint(init.gpa, "{s}/{s}.map-sync.component.wasm", .{ temp_path, stem });
        defer init.gpa.free(component);

        const build_args = [_][]const u8{
            "build", source, "--gc-wit-marshal", case.descriptor, "-o", wat,
        };
        var built = try run_do_args(init, do_bin, &build_args, lib_root, repo_root, 120_000);
        defer built.deinit(init.gpa);
        try expect_success(init, &built);
        try expect_file(init.io, wat);

        const wat_source = try read_file(init, wat);
        defer init.gpa.free(wat_source);
        if (std.mem.indexOf(u8, wat_source, case.canonical_type) == null) return error.MapCanonicalTypeMissing;
        if (std.mem.indexOf(u8, wat_source, "__arc_") != null) return error.ObsoleteArcMarker;
        if (std.mem.indexOf(u8, wat_source, "(import") == null) return error.MapCanonicalImportMissing;
        if (import_decl_has_reference(wat_source)) return error.MapReferenceCrossedComponentAbi;

        try run_adapter_success(init, toolchain_bin, &.{ "parse-core", wat, "-o", core });
        try run_adapter_success(init, toolchain_bin, &.{
            "embed-component", wit, core, "probe", "--features", "component-map", "-o", embedded,
        });
        try run_adapter_success(init, toolchain_bin, &.{ "new-component", embedded, "-o", component });
        try run_adapter_success(init, toolchain_bin, &.{ "validate-component", component, "--features", "component-map" });

        var component_wit = try run_adapter_command(init, toolchain_bin, &.{ "component-wit", component });
        defer component_wit.deinit(init.gpa);
        try expect_success(init, &component_wit);
        try process.assert_stdout_contains(component_wit, case.wit_marker);

        const runner_args = [_][]const u8{
            "cargo", "run", "--quiet", "--locked", "--manifest-path", manifest,
            "--bin", "do-p3-gc-marshal-map-u32-u32", "--", component, case.mode,
        };
        var runtime = try process.run_checked(init.gpa, init.io, .{
            .argv = &runner_args,
            .environ = init.environ_map,
            .env = &env,
            .cwd = repo_root,
            .timeout_ms = 600_000,
        });
        defer runtime.deinit(init.gpa);
        try expect_success(init, &runtime);
        try process.assert_stdout_contains(runtime, case.runtime_marker);
    }
}

fn import_decl_has_reference(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "(import")) continue;
        if (std.mem.indexOf(u8, trimmed, "(param") == null and
            std.mem.indexOf(u8, trimmed, "(result") == null) continue;
        if (std.mem.indexOf(u8, trimmed, "(ref") != null) return true;
    }
    return false;
}

fn run_p3_pure_lowering_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
) !void {
    for (pure_lowering_cases) |case| {
        const source = try join(init.gpa, repo_root, case.source);
        defer init.gpa.free(source);
        const stem = std.fs.path.basename(case.source)[0 .. std.fs.path.basename(case.source).len - ".do".len];
        const wat = try std.fmt.allocPrint(init.gpa, "{s}/{s}.pure.wat", .{ temp_path, stem });
        defer init.gpa.free(wat);
        const wit_output = if (case.wit_output_kind == .package)
            try std.fmt.allocPrint(init.gpa, "{s}/{s}.pure.wit-package", .{ temp_path, stem })
        else
            try std.fmt.allocPrint(init.gpa, "{s}/{s}.pure.wit", .{ temp_path, stem });
        defer init.gpa.free(wit_output);
        const core = try std.fmt.allocPrint(init.gpa, "{s}/{s}.pure.core.wasm", .{ temp_path, stem });
        defer init.gpa.free(core);
        const embedded = try std.fmt.allocPrint(init.gpa, "{s}/{s}.pure.embedded.wasm", .{ temp_path, stem });
        defer init.gpa.free(embedded);
        const component = try std.fmt.allocPrint(init.gpa, "{s}/{s}.pure.component.wasm", .{ temp_path, stem });
        defer init.gpa.free(component);
        const lib_root = try join(init.gpa, repo_root, "lib");
        defer init.gpa.free(lib_root);

        const build_args = [_][]const u8{
            "build", source, case.build_flag,
            if (case.wit_output_kind == .package) "--p3-wit-package-output" else "--p3-wit-output",
            wit_output, "-o", wat,
        };
        var build_result = try run_do_args(init, do_bin, &build_args, lib_root, null, 120_000);
        defer build_result.deinit(init.gpa);
        try expect_success(init, &build_result);
        if (build_result.stderr.len != 0) return error.UnexpectedCommandStderr;

        const wit_for_embed = wit_output;
        if (case.wit_output_kind == .package) {
            try expect_file(init.io, wit_output);
            for ([_][]const u8{ "worlds.wit", "types.wit", "deps.toml", "deps.lock" }) |package_file| {
                const path = try join(init.gpa, wit_output, package_file);
                defer init.gpa.free(path);
                try expect_file(init.io, path);
            }
            if (case.package_world_suffix) |suffix| {
                const worlds_path = try join(init.gpa, wit_output, "worlds.wit");
                defer init.gpa.free(worlds_path);
                const worlds = try read_file(init, worlds_path);
                defer init.gpa.free(worlds);
                var updated = std.ArrayList(u8).empty;
                defer updated.deinit(init.gpa);
                try updated.appendSlice(init.gpa, worlds);
                try updated.appendSlice(init.gpa, suffix);
                try write_file(init, worlds_path, updated.items);
            }
            const worlds_path = try join(init.gpa, wit_output, "worlds.wit");
            defer init.gpa.free(worlds_path);
            const worlds = try read_file(init, worlds_path);
            defer init.gpa.free(worlds);
            for (case.package_wit_markers) |marker| {
                if (std.mem.indexOf(u8, worlds, marker) == null) return error.P3LoweringWitMarkerMissing;
            }
            const types_path = try join(init.gpa, wit_output, "types.wit");
            defer init.gpa.free(types_path);
            const types = try read_file(init, types_path);
            defer init.gpa.free(types);
            for (case.package_type_markers) |marker| {
                if (std.mem.indexOf(u8, types, marker) == null) return error.P3LoweringWitMarkerMissing;
            }
        } else {
            const generated_wit = try read_file(init, wit_output);
            defer init.gpa.free(generated_wit);
            if (case.wit_snapshot) |snapshot_path| {
                const snapshot = try join(init.gpa, repo_root, snapshot_path);
                defer init.gpa.free(snapshot);
                try assert_file_equals(init, snapshot, generated_wit);
            } else {
                for (case.wit_markers) |marker| {
                    if (std.mem.indexOf(u8, generated_wit, marker) == null) return error.P3LoweringWitMarkerMissing;
                }
            }
        }
        if (case.ordinary_build_error) |expected_error| {
            const ordinary_wat = try std.fmt.allocPrint(init.gpa, "{s}/{s}.ordinary.wat", .{ temp_path, stem });
            defer init.gpa.free(ordinary_wat);
            const ordinary_args = [_][]const u8{ "build", source, "-o", ordinary_wat };
            var ordinary = try run_do_args(init, do_bin, &ordinary_args, lib_root, null, 120_000);
            defer ordinary.deinit(init.gpa);
            if (ordinary.succeeded()) return error.P3LoweringUnexpectedSuccess;
            if (std.mem.indexOf(u8, ordinary.stdout, expected_error) == null and
                std.mem.indexOf(u8, ordinary.stderr, expected_error) == null)
            {
                return error.P3LoweringExpectedErrorMissing;
            }
        }
        const wat_source = try read_file(init, wat);
        defer init.gpa.free(wat_source);
        if (case.wat_snapshot) |snapshot_path| {
            const snapshot = try join(init.gpa, repo_root, snapshot_path);
            defer init.gpa.free(snapshot);
            try assert_file_equals(init, snapshot, wat_source);
        }
        if (case.wit_sha256) |expected_hash| {
            if (case.wit_output_kind != .sidecar) return error.InvalidWitHashTarget;
            const actual_hash = try file_sha256_hex(init, wit_output);
            if (!std.mem.eql(u8, &actual_hash, expected_hash)) return error.WitHashMismatch;
        }
        for (case.markers) |marker| {
            if (std.mem.indexOf(u8, wat_source, marker) == null) return error.P3LoweringMarkerMissing;
        }
        for (case.forbidden_markers) |marker| {
            if (std.mem.indexOf(u8, wat_source, marker) != null) return error.P3LoweringForbiddenMarker;
        }
        if (case.count_marker) |marker| {
            if (std.mem.count(u8, wat_source, marker) != case.expected_count) return error.P3LoweringCountMismatch;
        }
        if (case.ordered_markers) |ordered| {
            const first = std.mem.indexOf(u8, wat_source, ordered.first) orelse return error.P3LoweringOrderedMarkerMissing;
            const second = std.mem.indexOf(u8, wat_source, ordered.second) orelse return error.P3LoweringOrderedMarkerMissing;
            if (first >= second) return error.P3LoweringMarkerOrderMismatch;
        }

        try validate_pure_component(init, toolchain_bin, wit_for_embed, wat, case.world, core, embedded, component, case.validate_core);

        if (case.wat_snapshot) |canonical_wat_path| {
            const canonical_wat = try join(init.gpa, repo_root, canonical_wat_path);
            defer init.gpa.free(canonical_wat);
            const canonical_wit_path = case.wit_snapshot orelse return error.MissingCanonicalWitSnapshot;
            const canonical_wit = try join(init.gpa, repo_root, canonical_wit_path);
            defer init.gpa.free(canonical_wit);
            const canonical_core = try std.fmt.allocPrint(init.gpa, "{s}/{s}.canonical.core.wasm", .{ temp_path, stem });
            defer init.gpa.free(canonical_core);
            const canonical_embedded = try std.fmt.allocPrint(init.gpa, "{s}/{s}.canonical.embedded.wasm", .{ temp_path, stem });
            defer init.gpa.free(canonical_embedded);
            const canonical_component = try std.fmt.allocPrint(init.gpa, "{s}/{s}.canonical.component.wasm", .{ temp_path, stem });
            defer init.gpa.free(canonical_component);
            try validate_pure_component(init, toolchain_bin, canonical_wit, canonical_wat, case.world, canonical_core, canonical_embedded, canonical_component, false);
        }
    }
}

fn validate_pure_component(
    init: std.process.Init,
    toolchain_bin: []const u8,
    wit: []const u8,
    wat: []const u8,
    world: []const u8,
    core: []const u8,
    embedded: []const u8,
    component: []const u8,
    validate_core: bool,
) !void {
    const parse_args = [_][]const u8{ toolchain_bin, "parse-core", wat, "-o", core };
    var parsed = try process.run_checked(init.gpa, init.io, .{ .argv = &parse_args, .environ = init.environ_map });
    defer parsed.deinit(init.gpa);
    try expect_success(init, &parsed);

    if (validate_core) {
        const core_validate_args = [_][]const u8{ toolchain_bin, "validate-core", core };
        var core_validated = try process.run_checked(init.gpa, init.io, .{ .argv = &core_validate_args, .environ = init.environ_map });
        defer core_validated.deinit(init.gpa);
        try expect_success(init, &core_validated);
    }

    const embed_args = [_][]const u8{ toolchain_bin, "embed-component", wit, core, world, "-o", embedded };
    var embedded_result = try process.run_checked(init.gpa, init.io, .{ .argv = &embed_args, .environ = init.environ_map });
    defer embedded_result.deinit(init.gpa);
    try expect_success(init, &embedded_result);

    const new_args = [_][]const u8{ toolchain_bin, "new-component", embedded, "-o", component };
    var created = try process.run_checked(init.gpa, init.io, .{ .argv = &new_args, .environ = init.environ_map });
    defer created.deinit(init.gpa);
    try expect_success(init, &created);
    try expect_file(init.io, component);

    const validate_args = [_][]const u8{ toolchain_bin, "validate-component", component };
    var validated = try process.run_checked(init.gpa, init.io, .{ .argv = &validate_args, .environ = init.environ_map });
    defer validated.deinit(init.gpa);
    try expect_success(init, &validated);
}

fn run_rust_runtime_matrix(
    init: std.process.Init,
    repo_root: []const u8,
    do_bin: []const u8,
    toolchain_bin: []const u8,
    temp_path: []const u8,
) !void {
    const lib_root = try join(init.gpa, repo_root, "lib");
    defer init.gpa.free(lib_root);
    const manifest = try join(init.gpa, repo_root, "examples/p3-runtime/rust-host-runner/Cargo.toml");
    defer init.gpa.free(manifest);
    const linker = try join(init.gpa, repo_root, "examples/p3-runtime/rust-host-runner/zig-cc.sh");
    defer init.gpa.free(linker);
    const env = [_]process.EnvVar{
        .{ .name = "CC", .value = linker },
        .{ .name = "CXX", .value = linker },
        .{ .name = "CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER", .value = linker },
    };

    for (rust_runtime_cases) |case| {
        const source = try join(init.gpa, repo_root, case.source);
        defer init.gpa.free(source);
        const stem = std.fs.path.basename(case.source)[0 .. std.fs.path.basename(case.source).len - ".do".len];
        const wat = try std.fmt.allocPrint(init.gpa, "{s}/{s}.rust.wat", .{ temp_path, stem });
        defer init.gpa.free(wat);
        const wit = try std.fmt.allocPrint(init.gpa, "{s}/{s}.rust.wit", .{ temp_path, stem });
        defer init.gpa.free(wit);
        const core = try std.fmt.allocPrint(init.gpa, "{s}/{s}.rust.core.wasm", .{ temp_path, stem });
        defer init.gpa.free(core);
        const embedded = try std.fmt.allocPrint(init.gpa, "{s}/{s}.rust.embedded.wasm", .{ temp_path, stem });
        defer init.gpa.free(embedded);
        const component = try std.fmt.allocPrint(init.gpa, "{s}/{s}.rust.component.wasm", .{ temp_path, stem });
        defer init.gpa.free(component);

        const build_args = [_][]const u8{
            "build", source, case.build_flag, "--p3-wit-output", wit, "-o", wat,
        };
        var built = try run_do_args(init, do_bin, &build_args, lib_root, null, 120_000);
        defer built.deinit(init.gpa);
        try expect_success(init, &built);
        if (built.stderr.len != 0) return error.UnexpectedCommandStderr;

        const generated_wit = try read_file(init, wit);
        defer init.gpa.free(generated_wit);
        const snapshot = try join(init.gpa, repo_root, case.wit_snapshot);
        defer init.gpa.free(snapshot);
        try assert_file_equals(init, snapshot, generated_wit);

        const parse_args = [_][]const u8{ toolchain_bin, "parse-core", wat, "-o", core };
        var parsed = try process.run_checked(init.gpa, init.io, .{ .argv = &parse_args, .environ = init.environ_map });
        defer parsed.deinit(init.gpa);
        try expect_success(init, &parsed);

        const embed_args = [_][]const u8{ toolchain_bin, "embed-component", wit, core, case.world, "-o", embedded };
        var embedded_result = try process.run_checked(init.gpa, init.io, .{ .argv = &embed_args, .environ = init.environ_map });
        defer embedded_result.deinit(init.gpa);
        try expect_success(init, &embedded_result);

        const new_args = [_][]const u8{ toolchain_bin, "new-component", embedded, "-o", component };
        var created = try process.run_checked(init.gpa, init.io, .{ .argv = &new_args, .environ = init.environ_map });
        defer created.deinit(init.gpa);
        try expect_success(init, &created);
        try expect_file(init.io, component);

        const validate_args = [_][]const u8{ toolchain_bin, "validate-component", component };
        var validated = try process.run_checked(init.gpa, init.io, .{ .argv = &validate_args, .environ = init.environ_map });
        defer validated.deinit(init.gpa);
        try expect_success(init, &validated);

        for (case.expectations) |expectation| {
            const runner_args = [_][]const u8{
                "cargo", "run", "--quiet", "--locked", "--manifest-path", manifest,
                "--bin", case.runner_bin, "--", component, expectation.mode,
            };
            var runtime = try process.run_checked(init.gpa, init.io, .{
                .argv = &runner_args,
                .environ = init.environ_map,
                .env = &env,
                .cwd = repo_root,
                .timeout_ms = 600_000,
            });
            defer runtime.deinit(init.gpa);
            try expect_success(init, &runtime);
            for (expectation.markers) |marker| {
                try process.assert_stdout_contains(runtime, marker);
            }
        }
    }
}

fn file_sha256_hex(init: std.process.Init, path: []const u8) ![64]u8 {
    const source = try read_file(init, path);
    defer init.gpa.free(source);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    var encoded: [64]u8 = undefined;
    const digits = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        encoded[index * 2] = digits[byte >> 4];
        encoded[index * 2 + 1] = digits[byte & 0x0f];
    }
    return encoded;
}

fn run_rust_async_runner(init: std.process.Init, repo_root: []const u8, component: []const u8) !void {
    const manifest = try join(init.gpa, repo_root, "examples/p3-runtime/rust-host-runner/Cargo.toml");
    defer init.gpa.free(manifest);
    const linker = try join(init.gpa, repo_root, "examples/p3-runtime/rust-host-runner/zig-cc.sh");
    defer init.gpa.free(linker);
    const argv = [_][]const u8{
        "cargo", "run",                        "--quiet", "--locked", "--manifest-path", manifest,
        "--bin", "do-p3-wait-for-host-runner", "--",      component,
    };
    const env = [_]process.EnvVar{
        .{ .name = "CC", .value = linker },
        .{ .name = "CXX", .value = linker },
        .{ .name = "CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER", .value = linker },
    };
    var result = try process.run_checked(init.gpa, init.io, .{
        .argv = &argv,
        .environ = init.environ_map,
        .env = &env,
        .cwd = repo_root,
        .timeout_ms = 600_000,
    });
    defer result.deinit(init.gpa);
    try expect_success(init, &result);
    try process.assert_stdout_contains(result, "Rust P3 clocks pending adapter passed");
    try process.assert_stdout_contains(result, "clock pending-polls=1");
}

fn run_success(init: std.process.Init, options: process.RunOptions) !void {
    var result = try process.run_checked(init.gpa, init.io, options);
    defer result.deinit(init.gpa);
    try expect_success(init, &result);
}

fn expect_success(init: std.process.Init, result: *const process.CommandResult) !void {
    if (result.succeeded()) return;
    const report = try process.failure_report(init.gpa, result.*);
    defer init.gpa.free(report);
    try write_stderr(init.io, report);
    try write_stderr(init.io, "\n");
    return error.CaseFailed;
}

fn expect_file(io: std.Io, path: []const u8) !void {
    _ = try std.Io.Dir.cwd().statFile(io, path, .{});
}

fn print_case_passed(io: std.Io, name: []const u8) !void {
    var line: [256]u8 = undefined;
    const rendered = try std.fmt.bufPrint(&line, "integration case passed: {s}\n", .{name});
    try std.Io.File.stdout().writeStreamingAll(io, rendered);
}

fn write_stderr(io: std.Io, text: []const u8) !void {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    try writer.interface.writeAll(text);
    try writer.interface.flush();
}

fn join(allocator: std.mem.Allocator, first: []const u8, second: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ first, second });
}

fn collect_files(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory_path: []const u8,
    suffix: []const u8,
) ![][]u8 {
    var directory = try std.Io.Dir.openDirAbsolute(io, directory_path, .{ .iterate = true });
    defer directory.close(io);
    var names: std.ArrayList([]u8) = .empty;
    errdefer free_names(allocator, names.items);

    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, suffix)) continue;
        try names.append(allocator, try allocator.dupe(u8, entry.name));
    }
    sort_names(names.items);
    return names.toOwnedSlice(allocator);
}

fn sort_names(names: [][]u8) void {
    var index: usize = 1;
    while (index < names.len) : (index += 1) {
        var cursor = index;
        while (cursor > 0 and std.mem.lessThan(u8, names[cursor], names[cursor - 1])) : (cursor -= 1) {
            const tmp = names[cursor];
            names[cursor] = names[cursor - 1];
            names[cursor - 1] = tmp;
        }
    }
}

fn free_names(allocator: std.mem.Allocator, names: [][]u8) void {
    for (names) |name| allocator.free(name);
    allocator.free(names);
}

fn file_exists(io: std.Io, path: []const u8) !bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

fn replace_extension(allocator: std.mem.Allocator, path: []const u8, extension: []const u8) ![]u8 {
    if (!std.mem.endsWith(u8, path, ".do")) return error.InvalidFixturePath;
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ path[0 .. path.len - ".do".len], extension });
}

fn fixture_output_path(
    allocator: std.mem.Allocator,
    temp_path: []const u8,
    fixture: []const u8,
    suffix: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ temp_path, std.fs.path.basename(fixture), suffix });
}

fn parse_build_args(
    allocator: std.mem.Allocator,
    io: std.Io,
    expect_path: []const u8,
) !std.ArrayList([]const u8) {
    const source = try std.Io.Dir.cwd().readFileAlloc(io, expect_path, allocator, .limited(4 * 1024 * 1024));
    defer allocator.free(source);
    var args: std.ArrayList([]const u8) = .empty;
    errdefer free_args(allocator, &args);
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const prefix = "# build-arg: ";
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        try args.append(allocator, try allocator.dupe(u8, line[prefix.len..]));
    }
    return args;
}

fn free_args(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8)) void {
    for (args.items) |arg| allocator.free(arg);
    args.deinit(allocator);
}

fn assert_expected_lines(init: std.process.Init, expect_path: []const u8, actual: []const u8) !void {
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, expect_path, init.gpa, .limited(4 * 1024 * 1024));
    defer init.gpa.free(source);
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "count=")) {
            const separator = std.mem.indexOfScalar(u8, line, ' ') orelse return error.InvalidExpectation;
            const expected = try std.fmt.parseInt(usize, line["count=".len..separator], 10);
            const pattern = line[separator + 1 ..];
            if (std.mem.count(u8, actual, pattern) != expected) return error.ExpectationMismatch;
            continue;
        }
        if (std.mem.indexOf(u8, actual, line) == null) return error.ExpectationMismatch;
    }
}

fn run_do_command(
    init: std.process.Init,
    do_bin: []const u8,
    command: []const u8,
    fixture: []const u8,
    extra: ?[]const []const u8,
    lib_root: []const u8,
    cwd: ?[]const u8,
) !process.CommandResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(init.gpa);
    try argv.append(init.gpa, do_bin);
    try argv.append(init.gpa, command);
    try argv.append(init.gpa, fixture);
    if (extra) |values| try argv.appendSlice(init.gpa, values);
    const env = [_]process.EnvVar{.{ .name = "DO_LIB_ROOT", .value = lib_root }};
    return process.run_checked(init.gpa, init.io, .{
        .argv = argv.items,
        .environ = init.environ_map,
        .env = &env,
        .cwd = cwd,
    });
}

fn run_do_args(
    init: std.process.Init,
    do_bin: []const u8,
    args: []const []const u8,
    lib_root: []const u8,
    cwd: ?[]const u8,
    timeout_ms: u64,
) !process.CommandResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(init.gpa);
    try argv.append(init.gpa, do_bin);
    try argv.appendSlice(init.gpa, args);
    const env = [_]process.EnvVar{.{ .name = "DO_LIB_ROOT", .value = lib_root }};
    return process.run_checked(init.gpa, init.io, .{
        .argv = argv.items,
        .environ = init.environ_map,
        .env = &env,
        .cwd = cwd,
        .timeout_ms = timeout_ms,
    });
}

fn run_do_args_with_env(
    init: std.process.Init,
    do_bin: []const u8,
    args: []const []const u8,
    lib_root: []const u8,
    cwd: ?[]const u8,
    timeout_ms: u64,
    extra_env: []const process.EnvVar,
) !process.CommandResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(init.gpa);
    try argv.append(init.gpa, do_bin);
    try argv.appendSlice(init.gpa, args);

    var env: std.ArrayList(process.EnvVar) = .empty;
    defer env.deinit(init.gpa);
    try env.append(init.gpa, .{ .name = "DO_LIB_ROOT", .value = lib_root });
    try env.appendSlice(init.gpa, extra_env);
    return process.run_checked(init.gpa, init.io, .{
        .argv = argv.items,
        .environ = init.environ_map,
        .env = env.items,
        .cwd = cwd,
        .timeout_ms = timeout_ms,
    });
}

fn expect_do_failure_with_marker(
    init: std.process.Init,
    do_bin: []const u8,
    lib_root: []const u8,
    cwd: ?[]const u8,
    args: []const []const u8,
    marker: []const u8,
) !void {
    var result = try run_do_args(init, do_bin, args, lib_root, cwd, 120_000);
    defer result.deinit(init.gpa);
    if (result.succeeded()) return error.ExpectedCommandFailure;
    try process.assert_stderr_contains(result, marker);
    if (result.stdout.len != 0) return error.UnexpectedCommandStdout;
}

fn expect_external_failure(result: *const process.CommandResult, marker: []const u8) !void {
    if (result.succeeded()) return error.ExpectedCommandFailure;
    try process.assert_stderr_contains(result.*, marker);
    if (result.stdout.len != 0) return error.UnexpectedCommandStdout;
}

fn find_executable(init: std.process.Init, name: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(name)) {
        std.Io.Dir.cwd().access(init.io, name, .{ .execute = true }) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => return error.FileNotFound,
            else => return err,
        };
        return init.gpa.dupe(u8, name);
    }

    const path_env = init.environ_map.get("PATH") orelse return error.FileNotFound;
    var paths = std.mem.tokenizeScalar(u8, path_env, std.fs.path.delimiter);
    while (paths.next()) |directory| {
        const candidate = try std.fs.path.join(init.gpa, &.{ directory, name });
        defer init.gpa.free(candidate);
        std.Io.Dir.cwd().access(init.io, candidate, .{ .execute = true }) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => continue,
            else => return err,
        };
        return init.gpa.dupe(u8, candidate);
    }
    return error.FileNotFound;
}

fn find_node_runtime(init: std.process.Init) ![]u8 {
    if (init.environ_map.get("NODE_BIN")) |configured| {
        if (configured.len != 0) return find_executable(init, configured);
    }
    return find_executable(init, "node") catch |err| switch (err) {
        error.FileNotFound => find_executable(init, "bun"),
        else => err,
    };
}

fn run_fmt_flag(
    init: std.process.Init,
    do_bin: []const u8,
    flag: []const u8,
    path: []const u8,
    lib_root: []const u8,
) !process.CommandResult {
    const args = [_][]const u8{ "fmt", flag, path };
    return run_do_args(init, do_bin, &args, lib_root, null, 120_000);
}

fn read_file(init: std.process.Init, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(64 * 1024 * 1024));
}

fn write_file(init: std.process.Init, path: []const u8, contents: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = contents });
}

fn assert_file_equals(init: std.process.Init, expected_path: []const u8, actual: []const u8) !void {
    const expected = try read_file(init, expected_path);
    defer init.gpa.free(expected);
    if (!std.mem.eql(u8, expected, actual)) return error.FileContentsMismatch;
}

fn assert_file_contents_path(init: std.process.Init, path: []const u8, expected: []const u8) !void {
    const actual = try read_file(init, path);
    defer init.gpa.free(actual);
    if (!std.mem.eql(u8, actual, expected)) return error.FileContentsMismatch;
}

fn report_case_failure(init: std.process.Init, result: process.CommandResult) !void {
    const report = try process.failure_report(init.gpa, result);
    defer init.gpa.free(report);
    try write_stderr(init.io, report);
    try write_stderr(init.io, "\n");
    return error.CaseFailed;
}

test "integration harness case table has required routes" {
    try std.testing.expectEqual(@as(usize, 21), test_cases.cases.len);
}

test "compile-only WASI sidecars have explicit expectation kinds" {
    const expected = [_]struct { suffix: []const u8, kind: CompileExpectationKind }{
        .{ .suffix = ".wasi_bind.expect", .kind = .wasi_bind },
        .{ .suffix = ".component_plan.expect", .kind = .component_plan },
        .{ .suffix = ".wit.expect", .kind = .wit },
        .{ .suffix = ".wit_dir.expect", .kind = .wit_dir },
        .{ .suffix = ".core_imports.expect", .kind = .core_imports },
        .{ .suffix = ".core_shims.expect", .kind = .core_shims },
        .{ .suffix = ".component_input.expect", .kind = .component_input },
        .{ .suffix = ".component_core.expect", .kind = .component_core },
    };
    for (expected) |entry| {
        try std.testing.expectEqual(entry.kind, classify_compile_expectation(entry.suffix).?);
    }
    try std.testing.expect(classify_compile_expectation(".expect") == null);
}

test "RUN_WASM smoke has a dedicated integration route" {
    var found = false;
    for (test_cases.cases) |case| {
        if (case.kind == .wasm_smoke_matrix) found = true;
    }
    try std.testing.expect(found);
}

test "fixture report line has stable status encoding" {
    const line = try format_fixture_report(std.testing.allocator, "compile_ok", "fixture.do", .pass);
    defer std.testing.allocator.free(line);
    try std.testing.expectEqualStrings(
        "fixture-result category=compile_ok name=fixture.do status=pass\n",
        line,
    );
}

test "compiled must pass promotes skipped ok fixture to pass" {
    try std.testing.expectEqual(FixtureStatus.pass, status_after_compiled_must_pass());
}

test "p3 pure lowering matrix has explicit cases" {
    try std.testing.expect(pure_lowering_cases.len >= 31);
}

test "rust runtime matrix has explicit cases" {
    try std.testing.expectEqual(@as(usize, 1), rust_runtime_cases.len);
    const case = rust_runtime_cases[0];
    try std.testing.expectEqualStrings("examples/p3-runtime/async-call-component.do", case.source);
    try std.testing.expectEqualStrings("--p3-async-call-component", case.build_flag);
    try std.testing.expectEqualStrings("probe", case.world);
    try std.testing.expectEqualStrings("examples/p3-runtime/async-call-component.wit", case.wit_snapshot);
    try std.testing.expectEqualStrings("do-p3-async-call-component-host-runner", case.runner_bin);
    try std.testing.expectEqual(@as(usize, 4), case.expectations.len);
    try std.testing.expectEqualStrings("ready", case.expectations[0].mode);
    try std.testing.expectEqualStrings("pending", case.expectations[1].mode);
    try std.testing.expectEqualStrings("cancel-inline", case.expectations[2].mode);
    try std.testing.expectEqualStrings("cancel-child", case.expectations[3].mode);
    for (case.expectations) |expectation| {
        try std.testing.expect(expectation.markers.len > 0);
    }
}

test "map synchronous Component matrix has explicit lower and lift cases" {
    try std.testing.expectEqual(@as(usize, 2), map_sync_component_cases.len);
    try std.testing.expectEqualStrings("examples/gc-p3-runtime/map-u32-u32-lower.do", map_sync_component_cases[0].source);
    try std.testing.expectEqualStrings("demo:marshal-map-u32-u32/api.write@1.0.0/lower", map_sync_component_cases[0].descriptor);
    try std.testing.expectEqualStrings("lower", map_sync_component_cases[0].mode);
    try std.testing.expectEqualStrings("examples/gc-p3-runtime/map-u32-u32-lift.do", map_sync_component_cases[1].source);
    try std.testing.expectEqualStrings("demo:marshal-map-u32-u32/api.read@1.0.0/lift", map_sync_component_cases[1].descriptor);
    try std.testing.expectEqualStrings("lift", map_sync_component_cases[1].mode);
    for (map_sync_component_cases) |case| {
        try std.testing.expect(case.canonical_type.len > 0);
        try std.testing.expect(case.wit_marker.len > 0);
        try std.testing.expect(case.runtime_marker.len > 0);
    }
}
