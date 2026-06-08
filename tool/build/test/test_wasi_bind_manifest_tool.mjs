#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const [validatorPath, tmpDir] = process.argv.slice(2);
if (!validatorPath || !tmpDir) {
  console.error("usage: test_wasi_bind_manifest_tool.mjs <validator> <tmp-dir>");
  process.exit(2);
}

fs.mkdirSync(tmpDir, { recursive: true });

const wasmTools = process.env.WASM_TOOLS || commandPath("wasm-tools");

const registryPath = path.join(tmpDir, "wasi_registry.json");
fs.writeFileSync(
  registryPath,
  JSON.stringify(
    {
      records: {
        Datetime: [
          { name: "seconds", type: "s64" },
          { name: "nanoseconds", type: "u32" },
        ],
      },
      functions: [
        {
          target: "io/streams/input-stream.read",
          params: ["input-stream", "u64"],
          result: "result<list<u8>,stream-error>",
        },
        {
          target: "io/streams/output-stream.check-write",
          params: ["output-stream"],
          result: "result<u64,stream-error>",
        },
        {
          target: "io/streams/output-stream.write",
          params: ["output-stream", "list<u8>"],
          result: "result<_,stream-error>",
        },
        {
          target: "io/streams/output-stream.flush",
          params: ["output-stream"],
          result: "result<_,stream-error>",
        },
        {
          target: "clocks/system-clock/now",
          params: [],
          result: "Datetime",
          result_record: "Datetime",
        },
        {
          target: "clocks/system-clock/get-resolution",
          params: [],
          result: "u64",
        },
        {
          target: "filesystem/types/descriptor.write",
          params: ["descriptor", "list<u8>", "filesize"],
          result: "result<filesize,error-code>",
        },
        {
          target: "filesystem/types/descriptor.read",
          params: ["descriptor", "filesize", "filesize"],
          result: "result<tuple<list<u8>,bool>,error-code>",
        },
        {
          target: "filesystem/types/descriptor.sync",
          params: ["descriptor"],
          result: "result<_,error-code>",
        },
        {
          target: "filesystem/types/descriptor.link-at",
          params: ["descriptor", "path-flags", "string", "borrow<descriptor>", "string"],
          result: "result<_,error-code>",
        },
        {
          target: "filesystem/types/descriptor.open-at",
          params: ["descriptor", "path-flags", "string", "open-flags", "descriptor-flags"],
          result: "result<descriptor,error-code>",
        },
        {
          target: "filesystem/types/descriptor.drop",
          params: ["descriptor"],
          result: "nil",
        },
        {
          target: "random/random/get-random-bytes",
          params: ["u64"],
          result: "list<u8>",
        },
        {
          target: "random/random/get-random-u64",
          params: [],
          result: "u64",
        },
      ],
    },
    null,
    2,
  ),
);

function commandPath(name) {
  const result = spawnSync("sh", ["-c", `command -v ${name}`], {
    encoding: "utf8",
  });
  if (result.status !== 0) return null;
  return result.stdout.trim() || null;
}

const okWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_ok.wat");
fs.writeFileSync(
  okWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_stream_read" target="io/streams/input-stream.read" params="input-stream,u64" result="result<list<u8>,stream-error>"',
    '  ;; wasi-bind source="src/time.do" alias="host_now" target="clocks/system-clock/now" params="" result="Datetime"',
    '  ;; wasi-bind source="src/time.do" alias="host_resolution" target="clocks/system-clock/get-resolution" params="" result="u64"',
    "",
  ].join("\n"),
);

const jsonResult = spawnSync(process.execPath, [validatorPath, "--registry", registryPath, "--json", okWatPath], {
  encoding: "utf8",
});
assert.equal(jsonResult.status, 0, jsonResult.stderr);

const parsed = JSON.parse(jsonResult.stdout);
assert.deepEqual(parsed.bindings, [
  {
    source: "entry",
    alias: "host_stream_read",
    target: "io/streams/input-stream.read",
    params: ["input-stream", "u64"],
    result: "result<list<u8>,stream-error>",
    identity: "entry/host_stream_read",
    known: true,
    resolved: {
      package: "io",
      interface: "streams",
      member: "input-stream.read",
      params: ["input-stream", "u64"],
      result: "result<list<u8>,stream-error>",
    },
    shim: {
      kind: "result-list-u8-stream-error",
      params: ["input-stream", "u64"],
      result: {
        kind: "result",
        ok: "list<u8>",
        err: "stream-error",
      },
      lowering: {
        component_import: {
          package: "io",
          interface: "streams",
          member: "input-stream.read",
        },
        canonical_abi: {
          params: ["i32", "i64", "i32"],
          results: [],
        },
        core_import: {
          module: "cm32p2|wasi:io/streams",
          name: "[method]input-stream.read",
          params: ["i32", "i64", "i32"],
          results: [],
        },
        do_result: {
          kind: "result",
          ok: "list<u8>",
          err: "stream-error",
          err_core_type: "i32",
          tag_offset: 0,
          payload_offset: 4,
          size: 12,
          align: 4,
          list: {
            elem: "u8",
            ptr_offset: 4,
            len_offset: 8,
          },
        },
      },
    },
  },
  {
    source: "src/time.do",
    alias: "host_now",
    target: "clocks/system-clock/now",
    params: [],
    result: "Datetime",
    identity: "src/time.do/host_now",
    known: true,
    record: {
      name: "Datetime",
      fields: [
        { name: "seconds", type: "s64" },
        { name: "nanoseconds", type: "u32" },
      ],
    },
    resolved: {
      package: "clocks",
      interface: "system-clock",
      member: "now",
      params: [],
      result: "Datetime",
      record: {
        name: "Datetime",
        fields: [
          { name: "seconds", type: "s64" },
          { name: "nanoseconds", type: "u32" },
        ],
      },
    },
    shim: {
      kind: "record-result",
      params: [],
      result: {
        kind: "record",
        name: "Datetime",
        fields: [
          { name: "seconds", type: "s64" },
          { name: "nanoseconds", type: "u32" },
        ],
      },
      lowering: {
        component_import: {
          package: "clocks",
          interface: "system-clock",
          member: "now",
        },
        canonical_abi: {
          params: ["i32"],
          results: [],
        },
        core_import: {
          module: "cm32p2|wasi:clocks/system-clock",
          name: "now",
          params: ["i32"],
          results: [],
        },
        do_result: {
          kind: "record",
          name: "Datetime",
          size: 12,
          align: 4,
          fields: [
            { name: "seconds", type: "s64", offset: 0, size: 8, align: 4, core_type: "i64" },
            { name: "nanoseconds", type: "u32", offset: 8, size: 4, align: 4, core_type: "i32" },
          ],
        },
      },
    },
  },
  {
    source: "src/time.do",
    alias: "host_resolution",
    target: "clocks/system-clock/get-resolution",
    params: [],
    result: "u64",
    identity: "src/time.do/host_resolution",
    known: true,
    resolved: {
      package: "clocks",
      interface: "system-clock",
      member: "get-resolution",
      params: [],
      result: "u64",
    },
    shim: {
      kind: "scalar-result",
      params: [],
      result: {
        kind: "scalar",
        type: "u64",
      },
      lowering: {
        component_import: {
          package: "clocks",
          interface: "system-clock",
          member: "get-resolution",
        },
        canonical_abi: {
          params: [],
          results: ["i64"],
        },
        core_import: {
          module: "cm32p2|wasi:clocks/system-clock",
          name: "get-resolution",
          params: [],
          results: ["i64"],
        },
        do_result: {
          kind: "scalar",
          type: "u64",
          size: 8,
          align: 4,
          core_type: "i64",
        },
      },
    },
  },
]);

const defaultRegistryReadDirWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_default_read_dir.wat");
fs.writeFileSync(
  defaultRegistryReadDirWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_dir_read" target="filesystem/types/descriptor.read-directory" params="descriptor" result="tuple<stream<directory-entry>,future<result<_,error-code>>>"',
    "",
  ].join("\n"),
);

const defaultRegistryReadDirResult = spawnSync(process.execPath, [validatorPath, "--json", defaultRegistryReadDirWatPath], {
  encoding: "utf8",
});
assert.equal(defaultRegistryReadDirResult.status, 0, defaultRegistryReadDirResult.stderr);
assert.deepEqual(JSON.parse(defaultRegistryReadDirResult.stdout).bindings, [
  {
    source: "entry",
    alias: "host_dir_read",
    target: "filesystem/types/descriptor.read-directory",
    params: ["descriptor"],
    result: "tuple<stream<directory-entry>,future<result<_,error-code>>>",
    identity: "entry/host_dir_read",
    known: true,
    resolved: {
      package: "filesystem",
      interface: "types",
      member: "descriptor.read-directory",
      params: ["descriptor"],
      result: "tuple<stream<directory-entry>,future<result<_,error-code>>>",
    },
    shim: {
      kind: "unsupported",
      reason: "non-scalar-or-record-signature",
    },
  },
]);

const readDirPlanResult = spawnSync(process.execPath, [validatorPath, "--component-plan", defaultRegistryReadDirWatPath], {
  encoding: "utf8",
});
assert.notEqual(readDirPlanResult.status, 0, "read-directory should not be lowerable yet");
assert.match(readDirPlanResult.stderr, /cannot build component plan for unsupported binding: entry\/host_dir_read/);

const defaultRegistryPreopensWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_default_preopens.wat");
fs.writeFileSync(
  defaultRegistryPreopensWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_preopens" target="filesystem/preopens/get-directories" params="" result="list<tuple<descriptor,string>>"',
    "",
  ].join("\n"),
);

const defaultRegistryPreopensResult = spawnSync(process.execPath, [validatorPath, "--json", defaultRegistryPreopensWatPath], {
  encoding: "utf8",
});
assert.equal(defaultRegistryPreopensResult.status, 0, defaultRegistryPreopensResult.stderr);
assert.deepEqual(JSON.parse(defaultRegistryPreopensResult.stdout).bindings, [
  {
    source: "entry",
    alias: "host_preopens",
    target: "filesystem/preopens/get-directories",
    params: [],
    result: "list<tuple<descriptor,string>>",
    identity: "entry/host_preopens",
    known: true,
    resolved: {
      package: "filesystem",
      interface: "preopens",
      member: "get-directories",
      params: [],
      result: "list<tuple<descriptor,string>>",
    },
    shim: {
      kind: "unsupported",
      reason: "non-scalar-or-record-signature",
    },
  },
]);

const preopensPlanResult = spawnSync(process.execPath, [validatorPath, "--component-plan", defaultRegistryPreopensWatPath], {
  encoding: "utf8",
});
assert.notEqual(preopensPlanResult.status, 0, "preopens should not be lowerable yet");
assert.match(preopensPlanResult.stderr, /cannot build component plan for unsupported binding: entry\/host_preopens/);

const defaultRegistrySocketsWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_default_sockets.wat");
fs.writeFileSync(
  defaultRegistrySocketsWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_tcp_create" target="sockets/types/tcp-socket.create" params="ip-address-family" result="result<tcp-socket,error-code>"',
    '  ;; wasi-bind source="entry" alias="host_tcp_bind" target="sockets/types/tcp-socket.bind" params="tcp-socket,ip-socket-address" result="result<_,error-code>"',
    '  ;; wasi-bind source="entry" alias="host_udp_create" target="sockets/types/udp-socket.create" params="ip-address-family" result="result<udp-socket,error-code>"',
    '  ;; wasi-bind source="entry" alias="host_udp_bind" target="sockets/types/udp-socket.bind" params="udp-socket,ip-socket-address" result="result<_,error-code>"',
    "",
  ].join("\n"),
);

const defaultRegistrySocketsResult = spawnSync(process.execPath, [validatorPath, "--json", defaultRegistrySocketsWatPath], {
  encoding: "utf8",
});
assert.equal(defaultRegistrySocketsResult.status, 0, defaultRegistrySocketsResult.stderr);
const socketsBindings = JSON.parse(defaultRegistrySocketsResult.stdout).bindings;
assert.deepEqual(
  socketsBindings.map((binding) => ({
    target: binding.target,
    known: binding.known,
    shim: binding.shim,
  })),
  [
    {
      target: "sockets/types/tcp-socket.create",
      known: true,
      shim: { kind: "unsupported", reason: "non-scalar-or-record-signature" },
    },
    {
      target: "sockets/types/tcp-socket.bind",
      known: true,
      shim: { kind: "unsupported", reason: "non-scalar-or-record-signature" },
    },
    {
      target: "sockets/types/udp-socket.create",
      known: true,
      shim: { kind: "unsupported", reason: "non-scalar-or-record-signature" },
    },
    {
      target: "sockets/types/udp-socket.bind",
      known: true,
      shim: { kind: "unsupported", reason: "non-scalar-or-record-signature" },
    },
  ],
);

const socketsPlanResult = spawnSync(process.execPath, [validatorPath, "--component-plan", defaultRegistrySocketsWatPath], {
  encoding: "utf8",
});
assert.notEqual(socketsPlanResult.status, 0, "sockets should not be lowerable yet");
assert.match(socketsPlanResult.stderr, /cannot build component plan for unsupported binding: entry\/host_tcp_create/);

const defaultRegistryHttpWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_default_http.wat");
fs.writeFileSync(
  defaultRegistryHttpWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_http_send" target="http/client/send" params="request" result="result<response,error-code>"',
    "",
  ].join("\n"),
);

const defaultRegistryHttpResult = spawnSync(process.execPath, [validatorPath, "--json", defaultRegistryHttpWatPath], {
  encoding: "utf8",
});
assert.equal(defaultRegistryHttpResult.status, 0, defaultRegistryHttpResult.stderr);
assert.deepEqual(
  JSON.parse(defaultRegistryHttpResult.stdout).bindings.map((binding) => ({
    target: binding.target,
    known: binding.known,
    shim: binding.shim,
  })),
  [
    {
      target: "http/client/send",
      known: true,
      shim: { kind: "unsupported", reason: "non-scalar-or-record-signature" },
    },
  ],
);

const httpPlanResult = spawnSync(process.execPath, [validatorPath, "--component-plan", defaultRegistryHttpWatPath], {
  encoding: "utf8",
});
assert.notEqual(httpPlanResult.status, 0, "http client should not be lowerable yet");
assert.match(httpPlanResult.stderr, /cannot build component plan for unsupported binding: entry\/host_http_send/);

const mixedComponentPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", okWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(mixedComponentPlanResult.status, 0, mixedComponentPlanResult.stderr);
const mixedPlan = JSON.parse(mixedComponentPlanResult.stdout);
assert.equal(mixedPlan.shims[0].kind, "result-list-u8-stream-error");

const mixedWitResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--wit", okWatPath],
  {
    encoding: "utf8",
  },
);
assert.notEqual(mixedWitResult.status, 0, "mixed packages should not produce a single WIT file");
assert.match(mixedWitResult.stderr, /cannot emit a single WIT file for multiple packages/);

const streamOutputWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_stream_output.wat");
fs.writeFileSync(
  streamOutputWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_output_check_write" target="io/streams/output-stream.check-write" params="output-stream" result="result<u64,stream-error>"',
    '  ;; wasi-bind source="entry" alias="host_output_write" target="io/streams/output-stream.write" params="output-stream,list<u8>" result="result<_,stream-error>"',
    '  ;; wasi-bind source="entry" alias="host_output_flush" target="io/streams/output-stream.flush" params="output-stream" result="result<_,stream-error>"',
    "",
  ].join("\n"),
);

const streamOutputPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", streamOutputWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(streamOutputPlanResult.status, 0, streamOutputPlanResult.stderr);
const streamOutputPlan = JSON.parse(streamOutputPlanResult.stdout);
assert.deepEqual(streamOutputPlan.shims.map((item) => item.kind), [
  "result-u64-stream-error",
  "result-unit-stream-error",
  "result-unit-stream-error",
]);
assert.equal(streamOutputPlan.shims[0].lowering.core_import.name, "[method]output-stream.check-write");
assert.equal(streamOutputPlan.shims[1].lowering.core_import.name, "[method]output-stream.write");
assert.equal(streamOutputPlan.shims[2].lowering.core_import.name, "[method]output-stream.flush");

const openAtWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_open_at.wat");
fs.writeFileSync(
  openAtWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_file_open_at" target="filesystem/types/descriptor.open-at" params="descriptor,path-flags,string,open-flags,descriptor-flags" result="result<descriptor,error-code>"',
    "",
  ].join("\n"),
);

const openAtPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", openAtWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(openAtPlanResult.status, 0, openAtPlanResult.stderr);
const openAtPlan = JSON.parse(openAtPlanResult.stdout);
assert.equal(openAtPlan.shims[0].kind, "result-descriptor-error-code");
assert.equal(openAtPlan.shims[0].lowering.core_import.name, "[method]descriptor.open-at");
assert.deepEqual(openAtPlan.shims[0].lowering.canonical_abi.params, ["i32", "i32", "i32", "i32", "i32", "i32", "i32"]);

const descriptorDropWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_descriptor_drop.wat");
fs.writeFileSync(
  descriptorDropWatPath,
  [
    '  ;; wasi-bind source="src/file.do" alias="host_file_drop" target="filesystem/types/descriptor.drop" params="descriptor" result="nil"',
    "",
  ].join("\n"),
);

const descriptorDropPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", descriptorDropWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(descriptorDropPlanResult.status, 0, descriptorDropPlanResult.stderr);
const descriptorDropPlan = JSON.parse(descriptorDropPlanResult.stdout);
assert.equal(descriptorDropPlan.shims[0].kind, "resource-drop");
assert.equal(descriptorDropPlan.shims[0].lowering.core_import.name, "[resource-drop]descriptor");
assert.deepEqual(descriptorDropPlan.shims[0].lowering.core_import.params, ["i32"]);

const descriptorDropWitResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--wit", descriptorDropWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(descriptorDropWitResult.status, 0, descriptorDropWitResult.stderr);
assert.match(descriptorDropWitResult.stdout, /resource descriptor \{/);
assert.doesNotMatch(descriptorDropWitResult.stdout, /drop: func/);

const lowerableWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_lowerable.wat");
fs.writeFileSync(
  lowerableWatPath,
  [
    '  ;; wasi-bind source="src/time.do" alias="host_now" target="clocks/system-clock/now" params="" result="Datetime"',
    '  ;; wasi-bind source="src/time.do" alias="host_resolution" target="clocks/system-clock/get-resolution" params="" result="u64"',
    "",
  ].join("\n"),
);

const componentPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", lowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(componentPlanResult.status, 0, componentPlanResult.stderr);
assert.deepEqual(JSON.parse(componentPlanResult.stdout), {
  schema_version: 1,
  imports: [
    {
      target: "clocks/system-clock/now",
      package: "clocks",
      interface: "system-clock",
      member: "now",
      params: [],
      result: "Datetime",
    },
    {
      target: "clocks/system-clock/get-resolution",
      package: "clocks",
      interface: "system-clock",
      member: "get-resolution",
      params: [],
      result: "u64",
    },
  ],
  shims: [
    {
      identity: "src/time.do/host_now",
      source: "src/time.do",
      alias: "host_now",
      target: "clocks/system-clock/now",
      kind: "record-result",
      lowering: {
        component_import: {
          package: "clocks",
          interface: "system-clock",
          member: "now",
        },
        canonical_abi: {
          params: ["i32"],
          results: [],
        },
        core_import: {
          module: "cm32p2|wasi:clocks/system-clock",
          name: "now",
          params: ["i32"],
          results: [],
        },
        do_result: {
          kind: "record",
          name: "Datetime",
          size: 12,
          align: 4,
          fields: [
            { name: "seconds", type: "s64", offset: 0, size: 8, align: 4, core_type: "i64" },
            { name: "nanoseconds", type: "u32", offset: 8, size: 4, align: 4, core_type: "i32" },
          ],
        },
      },
    },
    {
      identity: "src/time.do/host_resolution",
      source: "src/time.do",
      alias: "host_resolution",
      target: "clocks/system-clock/get-resolution",
      kind: "scalar-result",
      lowering: {
        component_import: {
          package: "clocks",
          interface: "system-clock",
          member: "get-resolution",
        },
        canonical_abi: {
          params: [],
          results: ["i64"],
        },
        core_import: {
          module: "cm32p2|wasi:clocks/system-clock",
          name: "get-resolution",
          params: [],
          results: ["i64"],
        },
        do_result: {
          kind: "scalar",
          type: "u64",
          size: 8,
          align: 4,
          core_type: "i64",
        },
      },
    },
  ],
});

const witResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--wit", lowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(witResult.status, 0, witResult.stderr);
assert.equal(
  witResult.stdout,
  [
    "package wasi:clocks;",
    "",
    "interface system-clock {",
    "  record datetime {",
    "    seconds: s64,",
    "    nanoseconds: u32,",
    "  }",
    "",
    "  now: func() -> datetime;",
    "",
    "  get-resolution: func() -> u64;",
    "}",
    "",
    "world imports {",
    "  import system-clock;",
    "}",
    "",
  ].join("\n"),
);

const coreImportsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-imports", lowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(coreImportsResult.status, 0, coreImportsResult.stderr);
assert.equal(
  coreImportsResult.stdout,
  [
    '  (import "cm32p2|wasi:clocks/system-clock" "now" (func $__wasi_import_clocks_system_clock_now (param i32)))',
    '  (import "cm32p2|wasi:clocks/system-clock" "get-resolution" (func $__wasi_import_clocks_system_clock_get_resolution (result i64)))',
    "",
  ].join("\n"),
);

const coreShimsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-shims", lowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(coreShimsResult.status, 0, coreShimsResult.stderr);
assert.equal(
  coreShimsResult.stdout,
  [
    '  (import "cm32p2|wasi:clocks/system-clock" "now" (func $__wasi_import_clocks_system_clock_now (param i32)))',
    '  (import "cm32p2|wasi:clocks/system-clock" "get-resolution" (func $__wasi_import_clocks_system_clock_get_resolution (result i64)))',
    "",
    "  (func $__wasi_shim_src_time_do_host_now (param $__result_area i32)",
    "    local.get $__result_area",
    "    call $__wasi_import_clocks_system_clock_now",
    "  )",
    "  (func $__wasi_shim_src_time_do_host_resolution (result i64)",
    "    call $__wasi_import_clocks_system_clock_get_resolution",
    "  )",
    "",
  ].join("\n"),
);

const listLowerableWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_list_lowerable.wat");
fs.writeFileSync(
  listLowerableWatPath,
  [
    '  ;; wasi-bind source="src/random.do" alias="host_random_bytes" target="random/random/get-random-bytes" params="u64" result="list<u8>"',
    '  ;; wasi-bind source="src/random.do" alias="host_random_u64" target="random/random/get-random-u64" params="" result="u64"',
    "",
  ].join("\n"),
);

const listComponentPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", listLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(listComponentPlanResult.status, 0, listComponentPlanResult.stderr);
const listPlan = JSON.parse(listComponentPlanResult.stdout);
assert.equal(listPlan.shims[0].kind, "list-u8-result");
assert.deepEqual(listPlan.shims[0].lowering.core_import, {
  module: "cm32p2|wasi:random/random",
  name: "get-random-bytes",
  params: ["i64", "i32"],
  results: [],
});
assert.deepEqual(listPlan.shims[0].lowering.do_result, {
  kind: "list",
  elem: "u8",
  size: 8,
  align: 4,
  ptr_offset: 0,
  len_offset: 4,
  elem_size: 1,
  elem_align: 1,
});

const listWitResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--wit", listLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(listWitResult.status, 0, listWitResult.stderr);
assert.equal(
  listWitResult.stdout,
  [
    "package wasi:random;",
    "",
    "interface random {",
    "  get-random-bytes: func(p0: u64) -> list<u8>;",
    "",
    "  get-random-u64: func() -> u64;",
    "}",
    "",
    "world imports {",
    "  import random;",
    "}",
    "",
  ].join("\n"),
);

const listCoreImportsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-imports", listLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(listCoreImportsResult.status, 0, listCoreImportsResult.stderr);
assert.equal(
  listCoreImportsResult.stdout,
  [
    '  (import "cm32p2|wasi:random/random" "get-random-bytes" (func $__wasi_import_random_random_get_random_bytes (param i64 i32)))',
    '  (import "cm32p2|wasi:random/random" "get-random-u64" (func $__wasi_import_random_random_get_random_u64 (result i64)))',
    "",
  ].join("\n"),
);

const listCoreShimsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-shims", listLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(listCoreShimsResult.status, 0, listCoreShimsResult.stderr);
assert.equal(
  listCoreShimsResult.stdout,
  [
    '  (import "cm32p2|wasi:random/random" "get-random-bytes" (func $__wasi_import_random_random_get_random_bytes (param i64 i32)))',
    '  (import "cm32p2|wasi:random/random" "get-random-u64" (func $__wasi_import_random_random_get_random_u64 (result i64)))',
    "",
    "  (func $__wasi_shim_src_random_do_host_random_bytes (param $p0 i64) (param $__result_area i32)",
    "    local.get $p0",
    "    local.get $__result_area",
    "    call $__wasi_import_random_random_get_random_bytes",
    "  )",
    "  (func $__wasi_shim_src_random_do_host_random_u64 (result i64)",
    "    call $__wasi_import_random_random_get_random_u64",
    "  )",
    "",
  ].join("\n"),
);

const writeLowerableWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_write_lowerable.wat");
fs.writeFileSync(
  writeLowerableWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_file_write" target="filesystem/types/descriptor.write" params="descriptor,list<u8>,filesize" result="result<filesize,error-code>"',
    "",
  ].join("\n"),
);

const writeComponentPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", writeLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(writeComponentPlanResult.status, 0, writeComponentPlanResult.stderr);
const writePlan = JSON.parse(writeComponentPlanResult.stdout);
assert.equal(writePlan.shims[0].kind, "result-filesize-error-code");
assert.deepEqual(writePlan.shims[0].lowering.core_import, {
  module: "cm32p2|wasi:filesystem/types",
  name: "[method]descriptor.write",
  params: ["i32", "i32", "i32", "i64", "i32"],
  results: [],
});
assert.deepEqual(writePlan.shims[0].lowering.do_result, {
  kind: "result",
  ok: "filesize",
  err: "error-code",
  ok_core_type: "i64",
  err_core_type: "i32",
  tag_offset: 0,
  payload_offset: 8,
  size: 16,
  align: 8,
});

const writeCoreImportsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-imports", writeLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(writeCoreImportsResult.status, 0, writeCoreImportsResult.stderr);
assert.equal(
  writeCoreImportsResult.stdout,
  [
    '  (import "cm32p2|wasi:filesystem/types" "[method]descriptor.write" (func $__wasi_import_filesystem_types_descriptor_write (param i32 i32 i32 i64 i32)))',
    "",
  ].join("\n"),
);

const writeCoreShimsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-shims", writeLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(writeCoreShimsResult.status, 0, writeCoreShimsResult.stderr);
assert.equal(
  writeCoreShimsResult.stdout,
  [
    '  (import "cm32p2|wasi:filesystem/types" "[method]descriptor.write" (func $__wasi_import_filesystem_types_descriptor_write (param i32 i32 i32 i64 i32)))',
    "",
    "  (func $__wasi_shim_entry_host_file_write (param $p0 i32) (param $p1 i32) (param $p2 i32) (param $p3 i64) (param $__result_area i32)",
    "    local.get $p0",
    "    local.get $p1",
    "    local.get $p2",
    "    local.get $p3",
    "    local.get $__result_area",
    "    call $__wasi_import_filesystem_types_descriptor_write",
    "  )",
    "",
  ].join("\n"),
);

const writeWitResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--wit", writeLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(writeWitResult.status, 0, writeWitResult.stderr);
assert.equal(
  writeWitResult.stdout,
  [
    "package wasi:filesystem;",
    "",
    "interface types {",
    "  type filesize = u64;",
    "",
    "  flags path-flags {",
    "    symlink-follow,",
    "  }",
    "",
    "  enum error-code {",
    "    access,",
    "    would-block,",
    "    already,",
    "    bad-descriptor,",
    "    busy,",
    "    deadlock,",
    "    quota,",
    "    exist,",
    "    file-too-large,",
    "    illegal-byte-sequence,",
    "    in-progress,",
    "    interrupted,",
    "    invalid,",
    "    io,",
    "    is-directory,",
    "    loop,",
    "    too-many-links,",
    "    message-size,",
    "    name-too-long,",
    "    no-device,",
    "    no-entry,",
    "    no-lock,",
    "    insufficient-memory,",
    "    insufficient-space,",
    "    not-directory,",
    "    not-empty,",
    "    not-recoverable,",
    "    unsupported,",
    "    no-tty,",
    "    no-such-device,",
    "    overflow,",
    "    not-permitted,",
    "    pipe,",
    "    read-only,",
    "    invalid-seek,",
    "    text-file-busy,",
    "    cross-device,",
    "  }",
    "",
    "  resource descriptor {",
    "    write: func(buffer: list<u8>, offset: filesize) -> result<filesize, error-code>;",
    "  }",
    "}",
    "",
    "world imports {",
    "  import types;",
    "}",
    "",
  ].join("\n"),
);

const readLowerableWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_read_lowerable.wat");
fs.writeFileSync(
  readLowerableWatPath,
  [
    '  ;; wasi-bind source="src/file.do" alias="host_file_read" target="filesystem/types/descriptor.read" params="descriptor,filesize,filesize" result="result<tuple<list<u8>,bool>,error-code>"',
    "",
  ].join("\n"),
);

const readComponentPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", readLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(readComponentPlanResult.status, 0, readComponentPlanResult.stderr);
const readPlan = JSON.parse(readComponentPlanResult.stdout);
assert.equal(readPlan.shims[0].kind, "result-list-u8-bool-error-code");
assert.deepEqual(readPlan.shims[0].lowering.core_import, {
  module: "cm32p2|wasi:filesystem/types",
  name: "[method]descriptor.read",
  params: ["i32", "i64", "i64", "i32"],
  results: [],
});
assert.deepEqual(readPlan.shims[0].lowering.do_result, {
  kind: "result",
  ok: "tuple<list<u8>, bool>",
  err: "error-code",
  err_core_type: "i32",
  tag_offset: 0,
  payload_offset: 4,
  size: 16,
  align: 4,
  tuple: {
    fields: [
      { name: "data", kind: "list", elem: "u8", ptr_offset: 4, len_offset: 8 },
      { name: "done", type: "bool", offset: 12, size: 1, align: 1, core_type: "i32" },
    ],
  },
});

const readCoreImportsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-imports", readLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(readCoreImportsResult.status, 0, readCoreImportsResult.stderr);
assert.equal(
  readCoreImportsResult.stdout,
  [
    '  (import "cm32p2|wasi:filesystem/types" "[method]descriptor.read" (func $__wasi_import_filesystem_types_descriptor_read (param i32 i64 i64 i32)))',
    "",
  ].join("\n"),
);

const readCoreShimsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-shims", readLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(readCoreShimsResult.status, 0, readCoreShimsResult.stderr);
assert.equal(
  readCoreShimsResult.stdout,
  [
    '  (import "cm32p2|wasi:filesystem/types" "[method]descriptor.read" (func $__wasi_import_filesystem_types_descriptor_read (param i32 i64 i64 i32)))',
    "",
    "  (func $__wasi_shim_src_file_do_host_file_read (param $p0 i32) (param $p1 i64) (param $p2 i64) (param $__result_area i32)",
    "    local.get $p0",
    "    local.get $p1",
    "    local.get $p2",
    "    local.get $__result_area",
    "    call $__wasi_import_filesystem_types_descriptor_read",
    "  )",
    "",
  ].join("\n"),
);

const readWitResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--wit", readLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(readWitResult.status, 0, readWitResult.stderr);
assert.equal(
  readWitResult.stdout,
  [
    "package wasi:filesystem;",
    "",
    "interface types {",
    "  type filesize = u64;",
    "",
    "  flags path-flags {",
    "    symlink-follow,",
    "  }",
    "",
    "  enum error-code {",
    "    access,",
    "    would-block,",
    "    already,",
    "    bad-descriptor,",
    "    busy,",
    "    deadlock,",
    "    quota,",
    "    exist,",
    "    file-too-large,",
    "    illegal-byte-sequence,",
    "    in-progress,",
    "    interrupted,",
    "    invalid,",
    "    io,",
    "    is-directory,",
    "    loop,",
    "    too-many-links,",
    "    message-size,",
    "    name-too-long,",
    "    no-device,",
    "    no-entry,",
    "    no-lock,",
    "    insufficient-memory,",
    "    insufficient-space,",
    "    not-directory,",
    "    not-empty,",
    "    not-recoverable,",
    "    unsupported,",
    "    no-tty,",
    "    no-such-device,",
    "    overflow,",
    "    not-permitted,",
    "    pipe,",
    "    read-only,",
    "    invalid-seek,",
    "    text-file-busy,",
    "    cross-device,",
    "  }",
    "",
    "  resource descriptor {",
    "    read: func(length: filesize, offset: filesize) -> result<tuple<list<u8>, bool>, error-code>;",
    "  }",
    "}",
    "",
    "world imports {",
    "  import types;",
    "}",
    "",
  ].join("\n"),
);

const syncLowerableWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_sync_lowerable.wat");
fs.writeFileSync(
  syncLowerableWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_file_sync" target="filesystem/types/descriptor.sync" params="descriptor" result="result<_,error-code>"',
    "",
  ].join("\n"),
);

const syncComponentPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", syncLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(syncComponentPlanResult.status, 0, syncComponentPlanResult.stderr);
const syncPlan = JSON.parse(syncComponentPlanResult.stdout);
assert.equal(syncPlan.shims[0].kind, "result-unit-error-code");
assert.deepEqual(syncPlan.shims[0].lowering.core_import, {
  module: "cm32p2|wasi:filesystem/types",
  name: "[method]descriptor.sync",
  params: ["i32", "i32"],
  results: [],
});
assert.deepEqual(syncPlan.shims[0].lowering.do_result, {
  kind: "result",
  ok: "_",
  err: "error-code",
  ok_core_type: null,
  err_core_type: "i32",
  tag_offset: 0,
  payload_offset: 4,
  size: 8,
  align: 4,
});

const syncCoreImportsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-imports", syncLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(syncCoreImportsResult.status, 0, syncCoreImportsResult.stderr);
assert.equal(
  syncCoreImportsResult.stdout,
  [
    '  (import "cm32p2|wasi:filesystem/types" "[method]descriptor.sync" (func $__wasi_import_filesystem_types_descriptor_sync (param i32 i32)))',
    "",
  ].join("\n"),
);

const syncCoreShimsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-shims", syncLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(syncCoreShimsResult.status, 0, syncCoreShimsResult.stderr);
assert.equal(
  syncCoreShimsResult.stdout,
  [
    '  (import "cm32p2|wasi:filesystem/types" "[method]descriptor.sync" (func $__wasi_import_filesystem_types_descriptor_sync (param i32 i32)))',
    "",
    "  (func $__wasi_shim_entry_host_file_sync (param $p0 i32) (param $__result_area i32)",
    "    local.get $p0",
    "    local.get $__result_area",
    "    call $__wasi_import_filesystem_types_descriptor_sync",
    "  )",
    "",
  ].join("\n"),
);

const syncWitResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--wit", syncLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(syncWitResult.status, 0, syncWitResult.stderr);
assert.equal(
  syncWitResult.stdout,
  [
    "package wasi:filesystem;",
    "",
    "interface types {",
    "  type filesize = u64;",
    "",
    "  flags path-flags {",
    "    symlink-follow,",
    "  }",
    "",
    "  enum error-code {",
    "    access,",
    "    would-block,",
    "    already,",
    "    bad-descriptor,",
    "    busy,",
    "    deadlock,",
    "    quota,",
    "    exist,",
    "    file-too-large,",
    "    illegal-byte-sequence,",
    "    in-progress,",
    "    interrupted,",
    "    invalid,",
    "    io,",
    "    is-directory,",
    "    loop,",
    "    too-many-links,",
    "    message-size,",
    "    name-too-long,",
    "    no-device,",
    "    no-entry,",
    "    no-lock,",
    "    insufficient-memory,",
    "    insufficient-space,",
    "    not-directory,",
    "    not-empty,",
    "    not-recoverable,",
    "    unsupported,",
    "    no-tty,",
    "    no-such-device,",
    "    overflow,",
    "    not-permitted,",
    "    pipe,",
    "    read-only,",
    "    invalid-seek,",
    "    text-file-busy,",
    "    cross-device,",
    "  }",
    "",
    "  resource descriptor {",
    "    sync: func() -> result<_, error-code>;",
    "  }",
    "}",
    "",
    "world imports {",
    "  import types;",
    "}",
    "",
  ].join("\n"),
);

const linkAtLowerableWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_link_at_lowerable.wat");
fs.writeFileSync(
  linkAtLowerableWatPath,
  [
    '  ;; wasi-bind source="entry" alias="host_file_link_at" target="filesystem/types/descriptor.link-at" params="descriptor,path-flags,string,borrow<descriptor>,string" result="result<_,error-code>"',
    "",
  ].join("\n"),
);

const linkAtComponentPlanResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-plan", linkAtLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(linkAtComponentPlanResult.status, 0, linkAtComponentPlanResult.stderr);
const linkAtPlan = JSON.parse(linkAtComponentPlanResult.stdout);
assert.equal(linkAtPlan.shims[0].kind, "result-unit-error-code");
assert.deepEqual(linkAtPlan.shims[0].lowering.core_import, {
  module: "cm32p2|wasi:filesystem/types",
  name: "[method]descriptor.link-at",
  params: ["i32", "i32", "i32", "i32", "i32", "i32", "i32", "i32"],
  results: [],
});

const linkAtCoreImportsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-imports", linkAtLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(linkAtCoreImportsResult.status, 0, linkAtCoreImportsResult.stderr);
assert.equal(
  linkAtCoreImportsResult.stdout,
  [
    '  (import "cm32p2|wasi:filesystem/types" "[method]descriptor.link-at" (func $__wasi_import_filesystem_types_descriptor_link_at (param i32 i32 i32 i32 i32 i32 i32 i32)))',
    "",
  ].join("\n"),
);

const linkAtCoreShimsResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--core-shims", linkAtLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(linkAtCoreShimsResult.status, 0, linkAtCoreShimsResult.stderr);
assert.equal(
  linkAtCoreShimsResult.stdout,
  [
    '  (import "cm32p2|wasi:filesystem/types" "[method]descriptor.link-at" (func $__wasi_import_filesystem_types_descriptor_link_at (param i32 i32 i32 i32 i32 i32 i32 i32)))',
    "",
    "  (func $__wasi_shim_entry_host_file_link_at (param $p0 i32) (param $p1 i32) (param $p2 i32) (param $p3 i32) (param $p4 i32) (param $p5 i32) (param $p6 i32) (param $__result_area i32)",
    "    local.get $p0",
    "    local.get $p1",
    "    local.get $p2",
    "    local.get $p3",
    "    local.get $p4",
    "    local.get $p5",
    "    local.get $p6",
    "    local.get $__result_area",
    "    call $__wasi_import_filesystem_types_descriptor_link_at",
    "  )",
    "",
  ].join("\n"),
);

const linkAtWitResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--wit", linkAtLowerableWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(linkAtWitResult.status, 0, linkAtWitResult.stderr);
assert.match(linkAtWitResult.stdout, /flags path-flags/);
assert.match(linkAtWitResult.stdout, /link-at: func\(old-flags: path-flags, old-path: string, new-descriptor: borrow<descriptor>, new-path: string\) -> result<_, error-code>;/);

const mismatchWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_mismatch.wat");
fs.writeFileSync(
  mismatchWatPath,
  '  ;; wasi-bind source="entry" alias="host_write" target="filesystem/types/descriptor.write" params="descriptor,list<u8>" result="result<filesize,error-code>"\n',
);

const mismatchResult = spawnSync(process.execPath, [validatorPath, "--registry", registryPath, "--json", mismatchWatPath], {
  encoding: "utf8",
});
assert.notEqual(mismatchResult.status, 0, "known signature mismatch should fail");
assert.match(mismatchResult.stderr, /known signature mismatch/);

const mixedWitDir = path.join(tmpDir, "mixed_wit_dir");
const mixedWitDirResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--wit-dir", mixedWitDir, okWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(mixedWitDirResult.status, 0, mixedWitDirResult.stderr);
assert.equal(mixedWitDirResult.stdout, `ok: wrote WIT package directory ${mixedWitDir}\n`);
assert.equal(
  fs.readFileSync(path.join(mixedWitDir, "world.wit"), "utf8"),
  [
    "package do:imports;",
    "",
    "world imports {",
    "  import wasi:clocks/system-clock;",
    "  import wasi:io/streams;",
    "}",
    "",
  ].join("\n"),
);
assert.equal(
  fs.readFileSync(path.join(mixedWitDir, "deps", "clocks", "clocks.wit"), "utf8"),
  [
    "package wasi:clocks;",
    "",
    "interface system-clock {",
    "  record datetime {",
    "    seconds: s64,",
    "    nanoseconds: u32,",
    "  }",
    "",
    "  now: func() -> datetime;",
    "",
    "  get-resolution: func() -> u64;",
    "}",
    "",
  ].join("\n"),
);
assert.equal(
  fs.readFileSync(path.join(mixedWitDir, "deps", "io", "io.wit"), "utf8"),
  [
    "package wasi:io;",
    "",
    "interface streams {",
    "  variant stream-error {",
    "    closed,",
    "  }",
    "",
    "  resource input-stream {",
    "    read: func(len: u64) -> result<list<u8>, stream-error>;",
    "  }",
    "}",
    "",
  ].join("\n"),
);
if (wasmTools) {
  const parseMixedWitDirResult = spawnSync(wasmTools, ["component", "wit", mixedWitDir], {
    encoding: "utf8",
  });
  assert.equal(parseMixedWitDirResult.status, 0, parseMixedWitDirResult.stderr);
  assert.match(parseMixedWitDirResult.stdout, /package do:imports;/);
  assert.match(parseMixedWitDirResult.stdout, /package wasi:clocks/);
  assert.match(parseMixedWitDirResult.stdout, /package wasi:io/);
}

const componentCoreWatPath = path.join(tmpDir, "wasi_bind_manifest_tool_component_core.wat");
fs.writeFileSync(
  componentCoreWatPath,
  [
    "(module",
    '  ;; wasi-bind source="entry" alias="host_stream_read" target="io/streams/input-stream.read" params="input-stream,u64" result="result<list<u8>,stream-error>"',
    '  ;; wasi-bind source="src/time.do" alias="host_now" target="clocks/system-clock/now" params="" result="Datetime"',
    '  ;; wasi-bind source="src/time.do" alias="host_resolution" target="clocks/system-clock/get-resolution" params="" result="u64"',
    '  (import "cm32p2|wasi:io/streams" "[method]input-stream.read" (func $__wasi_import_io_streams_input_stream_read (param i32 i64 i32)))',
    '  (import "cm32p2|wasi:clocks/system-clock" "now" (func $__wasi_import_clocks_system_clock_now (param i32)))',
    '  (import "cm32p2|wasi:clocks/system-clock" "get-resolution" (func $__wasi_import_clocks_system_clock_get_resolution (result i64)))',
    '  (memory (export "memory") 1)',
    '  (export "cm32p2_memory" (memory 0))',
    '  (func $cm32p2_realloc (export "cm32p2_realloc") (param i32 i32 i32 i32) (result i32) unreachable)',
    '  (func $cm32p2_initialize (export "cm32p2_initialize"))',
    ")",
    "",
  ].join("\n"),
);

const componentInputDir = path.join(tmpDir, "component_input");
const componentInputResult = spawnSync(
  process.execPath,
  [validatorPath, "--registry", registryPath, "--component-input-dir", componentInputDir, componentCoreWatPath],
  {
    encoding: "utf8",
  },
);
assert.equal(componentInputResult.status, 0, componentInputResult.stderr);
assert.equal(componentInputResult.stdout, `ok: wrote component input directory ${componentInputDir}\n`);
assert.equal(fs.readFileSync(path.join(componentInputDir, "core.wat"), "utf8"), fs.readFileSync(componentCoreWatPath, "utf8"));
const componentCoreWat = fs.readFileSync(path.join(componentInputDir, "core_component.wat"), "utf8");
assert.match(componentCoreWat, /\(memory 1\)/);
assert.match(componentCoreWat, /\(export "cm32p2_memory" \(memory 0\)\)/);
assert.doesNotMatch(componentCoreWat, /\(memory \(export "memory"\)/);
assert.deepEqual(JSON.parse(fs.readFileSync(path.join(componentInputDir, "component_plan.json"), "utf8")), mixedPlan);
assert.match(
  fs.readFileSync(path.join(componentInputDir, "core_imports.wat"), "utf8"),
  /cm32p2\|wasi:clocks\/system-clock/,
);
assert.match(
  fs.readFileSync(path.join(componentInputDir, "core_shims.wat"), "utf8"),
  /\$__wasi_shim_src_time_do_host_now/,
);
assert.equal(
  fs.readFileSync(path.join(componentInputDir, "wit", "world.wit"), "utf8"),
  fs.readFileSync(path.join(mixedWitDir, "world.wit"), "utf8"),
);
assert.equal(
  fs.readFileSync(path.join(componentInputDir, "metadata.json"), "utf8"),
  `${JSON.stringify(
      {
        schema_version: 1,
        core_wat: "core.wat",
        component_core_wat: "core_component.wat",
        component_plan: "component_plan.json",
        core_imports: "core_imports.wat",
        core_shims: "core_shims.wat",
        wit_dir: "wit",
    },
    null,
    2,
  )}\n`,
);
if (wasmTools) {
  const embeddedPath = path.join(tmpDir, "component_input_embedded.wasm");
  const componentPath = path.join(tmpDir, "component_input.component.wasm");
  const embedResult = spawnSync(
    wasmTools,
    ["component", "embed", path.join(componentInputDir, "wit"), path.join(componentInputDir, "core_component.wat"), "-o", embeddedPath],
    { encoding: "utf8" },
  );
  assert.equal(embedResult.status, 0, embedResult.stderr);
  const componentResult = spawnSync(wasmTools, ["component", "new", embeddedPath, "-o", componentPath], {
    encoding: "utf8",
  });
  assert.equal(componentResult.status, 0, componentResult.stderr);
  const validateComponentResult = spawnSync(wasmTools, ["validate", componentPath], {
    encoding: "utf8",
  });
  assert.equal(validateComponentResult.status, 0, validateComponentResult.stderr);
}

console.log("ok: wasi-bind manifest tool");
