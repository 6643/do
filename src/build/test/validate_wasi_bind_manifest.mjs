#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const parsedArgs = parseArgs(args);
if (!parsedArgs) {
  console.error("usage: validate_wasi_bind_manifest.mjs [--registry file.json] [--json|--component-plan|--wit|--wit-dir dir|--core-imports|--core-shims|--component-input-dir dir|--component-wasm file.wasm] <file.wat>");
  process.exit(2);
}

const {
  jsonOutput,
  componentPlanOutput,
  witOutput,
  witDirOutput,
  coreImportsOutput,
  coreShimsOutput,
  componentInputDirOutput,
  componentWasmOutput,
  watPath,
  registryPath,
} = parsedArgs;
const witRegistry = loadRegistry(registryPath);
const wat = fs.readFileSync(watPath, "utf8");
const lines = wat.split(/\r?\n/);
const bindRe = /^\s*;; wasi-bind source="([^"]+)" alias="([^"]+)" target="([^"]+)" params="([^"]*)" result="([^"]+)"\s*$/;
const identities = new Set();
const bindings = [];
let count = 0;

for (let lineNo = 0; lineNo < lines.length; lineNo += 1) {
  const line = lines[lineNo];
  if (!line.includes(";; wasi-bind ")) continue;

  const match = bindRe.exec(line);
  if (!match) fail(lineNo, "invalid wasi-bind field format");

  const [, source, alias, target, params, result] = match;
  validateName(lineNo, "source", source);
  validateName(lineNo, "alias", alias);
  validateTarget(lineNo, target);
  const paramItems = validateWitTypeList(lineNo, params);
  validateWitType(lineNo, "result", result);

  const identity = `${source}\0${alias}`;
  if (identities.has(identity)) {
    fail(lineNo, `duplicate wasi binding identity: ${source}/${alias}`);
  }
  identities.add(identity);

  const resolved = resolveKnownSignature(lineNo, target, params, result);
  const binding = {
    source,
    alias,
    target,
    params: paramItems,
    result,
    identity: `${source}/${alias}`,
    known: resolved != null,
  };
  if (resolved?.record) binding.record = resolved.record;
  if (resolved?.resolved) {
    binding.resolved = resolved.resolved;
    binding.shim = buildShimPlan(resolved.resolved);
  }
  bindings.push(binding);
  count += 1;
}

if (witOutput) {
  process.stdout.write(emitWitWorld(buildComponentPlan(bindings)));
} else if (witDirOutput) {
  emitWitPackageDir(buildComponentPlan(bindings), witDirOutput);
  console.log(`ok: wrote WIT package directory ${witDirOutput}`);
} else if (coreImportsOutput) {
  process.stdout.write(emitCoreImports(buildComponentPlan(bindings)));
} else if (coreShimsOutput) {
  process.stdout.write(emitCoreShims(buildComponentPlan(bindings)));
} else if (componentInputDirOutput) {
  emitComponentInputDir(buildComponentPlan(bindings), componentInputDirOutput, wat);
  console.log(`ok: wrote component input directory ${componentInputDirOutput}`);
} else if (componentWasmOutput) {
  emitComponentWasm(buildComponentPlan(bindings), componentWasmOutput, wat);
  console.log(`ok: wrote component wasm ${componentWasmOutput}`);
} else if (componentPlanOutput) {
  console.log(JSON.stringify(buildComponentPlan(bindings), null, 2));
} else if (jsonOutput) {
  console.log(JSON.stringify({ bindings }, null, 2));
} else {
  console.log(`ok: ${count} wasi-bind manifest entries`);
}

function parseArgs(items) {
  let jsonOutput = false;
  let componentPlanOutput = false;
  let witOutput = false;
  let witDirOutput = null;
  let coreImportsOutput = false;
  let coreShimsOutput = false;
  let componentInputDirOutput = null;
  let componentWasmOutput = null;
  let registryPath = defaultRegistryPath();
  let watPath = null;
  for (let i = 0; i < items.length; i += 1) {
    const item = items[i];
    if (item === "--json") {
      jsonOutput = true;
      continue;
    }
    if (item === "--component-plan") {
      componentPlanOutput = true;
      continue;
    }
    if (item === "--wit") {
      witOutput = true;
      continue;
    }
    if (item === "--wit-dir") {
      i += 1;
      if (i >= items.length) return null;
      witDirOutput = items[i];
      continue;
    }
    if (item === "--core-imports") {
      coreImportsOutput = true;
      continue;
    }
    if (item === "--core-shims") {
      coreShimsOutput = true;
      continue;
    }
    if (item === "--component-input-dir") {
      i += 1;
      if (i >= items.length) return null;
      componentInputDirOutput = items[i];
      continue;
    }
    if (item === "--component-wasm") {
      i += 1;
      if (i >= items.length) return null;
      componentWasmOutput = items[i];
      continue;
    }
    if (item === "--registry") {
      i += 1;
      if (i >= items.length) return null;
      registryPath = items[i];
      continue;
    }
    if (watPath !== null) return null;
    watPath = item;
  }
  if (!watPath) return null;
  const outputModeCount =
    Number(jsonOutput) +
    Number(componentPlanOutput) +
    Number(witOutput) +
    Number(witDirOutput !== null) +
    Number(coreImportsOutput) +
    Number(coreShimsOutput) +
    Number(componentInputDirOutput !== null) +
    Number(componentWasmOutput !== null);
  if (outputModeCount > 1) return null;
  return {
    jsonOutput,
    componentPlanOutput,
    witOutput,
    witDirOutput,
    coreImportsOutput,
    coreShimsOutput,
    componentInputDirOutput,
    componentWasmOutput,
    registryPath,
    watPath,
  };
}

function defaultRegistryPath() {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  return path.resolve(scriptDir, "../../../doc/wit/wasi_registry.json");
}

function loadRegistry(filePath) {
  const registry = JSON.parse(fs.readFileSync(filePath, "utf8"));
  if (!registry || typeof registry !== "object") {
    failRegistry(filePath, "registry must be an object");
  }
  if (!registry.records || typeof registry.records !== "object") {
    failRegistry(filePath, "registry.records must be an object");
  }
  if (!Array.isArray(registry.functions)) {
    failRegistry(filePath, "registry.functions must be an array");
  }
  return registry;
}

function validateName(lineNo, field, value) {
  if (value.length === 0) fail(lineNo, `${field} must not be empty`);
  if (value.includes("\0")) fail(lineNo, `${field} contains invalid NUL`);
}

function validateTarget(lineNo, target) {
  const parts = target.split("/");
  if (parts.length < 3 || parts.some((part) => part.length === 0)) {
    fail(lineNo, `target must be package/interface/member: ${target}`);
  }
}

function validateWitTypeList(lineNo, params) {
  if (params.length === 0) return [];
  const items = splitTopLevel(params);
  for (const item of items) {
    validateWitType(lineNo, "params", item);
  }
  return items;
}

function validateWitType(lineNo, field, text) {
  if (text.length === 0) fail(lineNo, `${field} type must not be empty`);
  let depth = 0;
  for (const ch of text) {
    if (ch === "<") {
      depth += 1;
      continue;
    }
    if (ch === ">") {
      depth -= 1;
      if (depth < 0) fail(lineNo, `${field} has unmatched >: ${text}`);
    }
  }
  if (depth !== 0) fail(lineNo, `${field} has unmatched <: ${text}`);
}

function splitTopLevel(text) {
  const parts = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (ch === "<") {
      depth += 1;
      continue;
    }
    if (ch === ">") {
      depth -= 1;
      continue;
    }
    if (ch !== "," || depth !== 0) continue;
    parts.push(text.slice(start, i));
    start = i + 1;
  }
  parts.push(text.slice(start));
  return parts;
}

function resolveKnownSignature(lineNo, target, params, result) {
  const known = witRegistry.functions.find((item) => item?.target === target);
  if (!known) return null;
  const knownParams = Array.isArray(known.params) ? known.params.join(",") : null;
  const knownResult = typeof known.result === "string" ? known.result : null;
  if (knownParams === null || knownResult === null) {
    failRegistry(registryPath, `invalid signature entry: ${target}`);
  }
  if (params !== knownParams || result !== knownResult) {
    fail(lineNo, `known signature mismatch: ${target}`);
  }
  const resolved = {
    ...splitTarget(target),
    params: known.params,
    result: known.result,
  };
  if (!known.result_record) return { resolved };

  const recordFields = witRegistry.records[known.result_record];
  if (!Array.isArray(recordFields)) {
    failRegistry(registryPath, `missing record mirror: ${known.result_record}`);
  }
  const record = {
    name: known.result_record,
    fields: recordFields,
  };
  resolved.record = record;
  return { resolved, record };
}

function splitTarget(target) {
  const parts = target.split("/");
  return {
    package: parts[0],
    interface: parts[1],
    member: parts.slice(2).join("/"),
  };
}

function buildShimPlan(resolved) {
  if (isResourceDropSignature(resolved)) {
    const doResult = buildUnitResultLayout();
    return {
      kind: "resource-drop",
      params: resolved.params,
      result: {
        kind: "unit",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (isResultUnitErrorCodeSignature(resolved)) {
    const doResult = buildResultUnitErrorCodeLayout();
    return {
      kind: "result-unit-error-code",
      params: resolved.params,
      result: {
        kind: "result",
        ok: "_",
        err: "error-code",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (isResultFilesizeErrorCodeSignature(resolved)) {
    const doResult = buildResultFilesizeErrorCodeLayout();
    return {
      kind: "result-filesize-error-code",
      params: resolved.params,
      result: {
        kind: "result",
        ok: "filesize",
        err: "error-code",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (isResultDescriptorErrorCodeSignature(resolved)) {
    const doResult = buildResultDescriptorErrorCodeLayout();
    return {
      kind: "result-descriptor-error-code",
      params: resolved.params,
      result: {
        kind: "result",
        ok: "descriptor",
        err: "error-code",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  // G6.3: tcp/udp-socket.create → result<socket,error-code> (same result-area as open-at).
  if (isResultSocketErrorCodeSignature(resolved)) {
    const okTy = resolved.result === "result<tcp-socket,error-code>" ? "tcp-socket" : "udp-socket";
    const doResult = buildResultDescriptorErrorCodeLayout();
    return {
      kind: "result-socket-error-code",
      params: resolved.params,
      result: {
        kind: "result",
        ok: okTy,
        err: "error-code",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (isResultListU8BoolErrorCodeSignature(resolved)) {
    const doResult = buildResultListU8BoolErrorCodeLayout();
    return {
      kind: "result-list-u8-bool-error-code",
      params: resolved.params,
      result: {
        kind: "result",
        ok: "tuple<list<u8>, bool>",
        err: "error-code",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (isResultListU8StreamErrorSignature(resolved)) {
    const doResult = buildResultListU8StreamErrorLayout();
    return {
      kind: "result-list-u8-stream-error",
      params: resolved.params,
      result: {
        kind: "result",
        ok: "list<u8>",
        err: "stream-error",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (isResultUnitStreamErrorSignature(resolved)) {
    const doResult = buildResultUnitStreamErrorLayout();
    return {
      kind: "result-unit-stream-error",
      params: resolved.params,
      result: {
        kind: "result",
        ok: "_",
        err: "stream-error",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (isResultU64StreamErrorSignature(resolved)) {
    const doResult = buildResultU64StreamErrorLayout();
    return {
      kind: "result-u64-stream-error",
      params: resolved.params,
      result: {
        kind: "result",
        ok: "u64",
        err: "stream-error",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (!resolved.params.every((item) => isLowerableParamWitType(item))) return unsupportedShim();
  if (resolved.record) {
    if (!resolved.record.fields.every((field) => isScalarWitType(field.type))) {
      return unsupportedShim();
    }
    const doResult = buildRecordResultLayout(resolved.record);
    return {
      kind: "record-result",
      params: resolved.params,
      result: {
        kind: "record",
        name: resolved.record.name,
        fields: resolved.record.fields,
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (isScalarWitType(resolved.result)) {
    const doResult = buildScalarResultLayout(resolved.result);
    return {
      kind: "scalar-result",
      params: resolved.params,
      result: {
        kind: "scalar",
        type: resolved.result,
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  if (resolved.result === "list<u8>") {
    const doResult = buildListU8ResultLayout();
    return {
      kind: "list-u8-result",
      params: resolved.params,
      result: {
        kind: "list",
        elem: "u8",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  // G6.1 A: list<tuple<descriptor,string>> — lowerable list result with resource+string elements.
  if (isListTupleDescriptorStringSignature(resolved)) {
    const doResult = buildListPreopenResultLayout();
    return {
      kind: "list-preopen-result",
      params: resolved.params,
      result: {
        kind: "list",
        elem: "tuple<descriptor,string>",
      },
      lowering: buildLoweringPlan(resolved, doResult),
    };
  }
  return unsupportedShim();
}

function buildComponentPlan(items) {
  const imports = [];
  const seenTargets = new Set();
  const shims = [];

  for (const item of items) {
    if (!item.known || !item.resolved) {
      failPlan(`cannot build component plan for unknown binding: ${item.identity}`);
    }
    if (!item.shim || item.shim.kind === "unsupported" || !item.shim.lowering) {
      failPlan(`cannot build component plan for unsupported binding: ${item.identity}`);
    }
    if (!seenTargets.has(item.target)) {
      imports.push({
        target: item.target,
        package: item.resolved.package,
        interface: item.resolved.interface,
        member: item.resolved.member,
        params: item.resolved.params,
        result: item.resolved.result,
      });
      seenTargets.add(item.target);
    }
    shims.push({
      identity: item.identity,
      source: item.source,
      alias: item.alias,
      target: item.target,
      kind: item.shim.kind,
      lowering: item.shim.lowering,
    });
  }

  return {
    schema_version: 1,
    imports,
    shims,
  };
}

function emitWitWorld(plan) {
  if (plan.imports.length === 0) {
    failPlan("cannot emit WIT for empty component plan");
  }

  const packageName = plan.imports[0].package;
  ensureWitIdent(packageName, "package");
  for (const item of plan.imports) {
    if (item.package !== packageName) {
      failPlan("cannot emit a single WIT file for multiple packages");
    }
  }

  const shimsByTarget = new Map(plan.shims.map((shim) => [shim.target, shim]));
  return emitWitPackage(packageName, plan.imports, shimsByTarget, true);
}

function emitWitPackageDir(plan, dirPath) {
  if (plan.imports.length === 0) {
    failPlan("cannot emit WIT package directory for empty component plan");
  }

  const shimsByTarget = new Map(plan.shims.map((shim) => [shim.target, shim]));
  const packages = groupImportsByPackage(plan.imports);

  fs.rmSync(dirPath, { recursive: true, force: true });
  fs.mkdirSync(dirPath, { recursive: true });

  const rootLines = ["package do:imports;", ""];
  rootLines.push("world imports {");
  for (const group of packages) {
    ensureWitIdent(group.package, "package");
    for (const iface of groupImportsByInterface(group.imports)) {
      ensureWitIdent(iface.interface, "interface");
      rootLines.push(`  import wasi:${group.package}/${iface.interface};`);
    }
  }
  rootLines.push("}", "");
  fs.writeFileSync(path.join(dirPath, "world.wit"), rootLines.join("\n"));

  const depsDir = path.join(dirPath, "deps");
  for (const group of packages) {
    const packageDir = path.join(depsDir, group.package);
    fs.mkdirSync(packageDir, { recursive: true });
    fs.writeFileSync(
      path.join(packageDir, `${group.package}.wit`),
      emitWitPackage(group.package, group.imports, shimsByTarget, false),
    );
  }
}

function emitComponentInputDir(plan, dirPath, coreWat) {
  fs.rmSync(dirPath, { recursive: true, force: true });
  fs.mkdirSync(dirPath, { recursive: true });

  fs.writeFileSync(path.join(dirPath, "core.wat"), coreWat);
  fs.writeFileSync(path.join(dirPath, "core_component.wat"), componentCoreWat(coreWat));
  fs.writeFileSync(path.join(dirPath, "component_plan.json"), `${JSON.stringify(plan, null, 2)}\n`);
  fs.writeFileSync(path.join(dirPath, "core_imports.wat"), emitCoreImports(plan));
  fs.writeFileSync(path.join(dirPath, "core_shims.wat"), emitCoreShims(plan));
  emitWitPackageDir(plan, path.join(dirPath, "wit"));
  fs.writeFileSync(
    path.join(dirPath, "metadata.json"),
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
}

function emitComponentWasm(plan, outputPath, coreWat) {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "do-component-wasm-"));
  try {
    emitComponentInputDir(plan, tmpDir, coreWat);

    const embeddedPath = path.join(tmpDir, "embedded.wasm");
    const componentPath = path.join(tmpDir, "component.wasm");
    runWasmTools(
      [
        "component",
        "embed",
        path.join(tmpDir, "wit"),
        path.join(tmpDir, "core_component.wat"),
        "-o",
        embeddedPath,
      ],
      "wasm-tools component embed",
    );
    runWasmTools(["component", "new", embeddedPath, "-o", componentPath], "wasm-tools component new");
    runWasmTools(["validate", componentPath], "wasm-tools validate");

    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.copyFileSync(componentPath, outputPath);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

function runWasmTools(args, label) {
  const wasmTools = process.env.WASM_TOOLS || "wasm-tools";
  const result = spawnSync(wasmTools, args, { encoding: "utf8" });
  if (result.error) {
    failPlan(`${label} failed: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const detail = [result.stderr, result.stdout].filter(Boolean).join("\n").trim();
    failPlan(`${label} failed${detail.length > 0 ? `: ${detail}` : ""}`);
  }
}

function componentCoreWat(coreWat) {
  const componentReady = coreWat.replace(/\(memory \(export "memory"\) ([0-9]+)\)/, "(memory $1)");
  if (componentReady === coreWat && coreWat.includes('(export "memory"')) {
    failPlan("cannot rewrite core memory export for component input");
  }
  return componentReady;
}

function emitWitPackage(packageName, imports, shimsByTarget, includeWorld) {
  ensureWitIdent(packageName, "package");
  // G6.1: preopens references descriptor from types; ensure types is present when needed.
  let packageImports = imports.slice();
  if (
    packageName === "filesystem" &&
    packageImports.some((item) => item.interface === "preopens") &&
    !packageImports.some((item) => item.interface === "types")
  ) {
    packageImports = packageImports.concat([
      {
        target: "filesystem/types/descriptor.drop",
        package: "filesystem",
        interface: "types",
        member: "descriptor.drop",
        params: ["descriptor"],
        result: "nil",
      },
    ]);
    if (!shimsByTarget.has("filesystem/types/descriptor.drop")) {
      shimsByTarget.set("filesystem/types/descriptor.drop", {
        target: "filesystem/types/descriptor.drop",
        kind: "resource-drop",
        lowering: {
          do_result: { kind: "unit", size: 0, align: 1 },
          component_import: {
            package: "filesystem",
            interface: "types",
            member: "descriptor.drop",
          },
          core_import: {
            module: "cm32p2|wasi:filesystem/types",
            name: "[resource-drop]descriptor",
            params: ["i32"],
            results: [],
          },
        },
      });
    }
  }
  const interfaces = groupImportsByInterface(packageImports);
  const lines = [`package wasi:${packageName};`, ""];

  for (const group of interfaces) {
    emitWitInterface(lines, group, shimsByTarget);
  }

  if (!includeWorld) return lines.join("\n");

  lines.push("world imports {");
  for (const group of interfaces) {
    lines.push(`  import ${group.interface};`);
  }
  lines.push("}", "");

  return lines.join("\n");
}

function emitWitInterface(lines, group, shimsByTarget) {
  ensureWitIdent(group.interface, "interface");
  lines.push(`interface ${group.interface} {`);

  // preopens.get-directories returns list<tuple<descriptor,string>> — need types.descriptor.
  if (group.interface === "preopens") {
    lines.push("  use types.{descriptor};", "");
  }

  if (group.imports.some(isResourceMethodImport)) {
    emitResourceInterfaceBody(lines, group.imports, shimsByTarget);
  } else {
    const records = collectInterfaceRecords(group.imports, shimsByTarget);
    for (const record of records) {
      lines.push(`  record ${record.name} {`);
      for (const field of record.fields) {
        ensureWitIdent(field.name, "record field");
        lines.push(`    ${field.name}: ${field.type},`);
      }
      lines.push("  }", "");
    }

    group.imports.forEach((item, index) => {
      const shim = shimsByTarget.get(item.target);
      if (!shim) failPlan(`missing shim for import: ${item.target}`);
      const result = witFunctionResultType(shim);
      const params = item.params.map((type, paramIndex) => `p${paramIndex}: ${type}`).join(", ");
      ensureWitIdent(item.member, "function");
      lines.push(`  ${item.member}: func(${params}) -> ${result};`);
      if (index + 1 < group.imports.length) lines.push("");
    });
  }

  lines.push("}", "");
}

function emitCoreImports(plan) {
  return [...coreImportLines(plan), ""].join("\n");
}

function emitCoreShims(plan) {
  const lines = coreImportLines(plan);
  lines.push("");
  for (const shim of plan.shims) {
    lines.push(coreShimHeader(shim));
    const paramNames = coreShimParamNames(shim.lowering.core_import.params, shim.lowering.do_result);
    for (const name of paramNames) {
      lines.push(`    local.get $${name}`);
    }
    lines.push(`    call $${coreImportSymbol(shim.lowering.component_import)}`);
    lines.push("  )");
  }
  lines.push("");
  return lines.join("\n");
}

function coreImportLines(plan) {
  const lines = [];
  const seenTargets = new Set();
  for (const shim of plan.shims) {
    if (seenTargets.has(shim.target)) continue;
    seenTargets.add(shim.target);

    const coreImport = shim.lowering.core_import;
    const symbol = coreImportSymbol(shim.lowering.component_import);
    const pieces = [
      `  (import "${coreImport.module}" "${coreImport.name}" (func $${symbol}`,
    ];
    if (coreImport.params.length !== 0) {
      pieces.push(` (param ${coreImport.params.join(" ")})`);
    }
    if (coreImport.results.length !== 0) {
      pieces.push(` (result ${coreImport.results.join(" ")})`);
    }
    pieces.push("))");
    lines.push(pieces.join(""));
  }
  return lines;
}

function coreShimHeader(shim) {
  const coreImport = shim.lowering.core_import;
  const paramNames = coreShimParamNames(coreImport.params, shim.lowering.do_result);
  const pieces = [`  (func $${coreShimSymbol(shim)}`];
  for (const [index, type] of coreImport.params.entries()) {
    pieces.push(` (param $${paramNames[index]} ${type})`);
  }
  if (coreImport.results.length !== 0) {
    pieces.push(` (result ${coreImport.results.join(" ")})`);
  }
  return pieces.join("");
}

function coreShimParamNames(coreParams, doResult) {
  const names = coreParams.map((_, index) => `p${index}`);
  if ((doResult.kind === "record" || doResult.kind === "list" || doResult.kind === "result") && names.length !== 0) {
    names[names.length - 1] = "__result_area";
  }
  return names;
}

function coreShimSymbol(shim) {
  return [
    "__wasi_shim",
    sanitizeWatIdentPart(shim.source),
    sanitizeWatIdentPart(shim.alias),
  ].join("_");
}

function coreImportSymbol(componentImport) {
  return [
    "__wasi_import",
    sanitizeWatIdentPart(componentImport.package),
    sanitizeWatIdentPart(componentImport.interface),
    sanitizeWatIdentPart(componentImport.member),
  ].join("_");
}

function sanitizeWatIdentPart(value) {
  return value.replace(/[^A-Za-z0-9_]+/g, "_").replace(/^_+|_+$/g, "");
}

function groupImportsByInterface(items) {
  const groups = [];
  const indexes = new Map();
  for (const item of items) {
    if (!indexes.has(item.interface)) {
      indexes.set(item.interface, groups.length);
      groups.push({ interface: item.interface, imports: [] });
    }
    groups[indexes.get(item.interface)].imports.push(item);
  }
  groups.sort((left, right) => left.interface.localeCompare(right.interface));
  return groups;
}

function groupImportsByPackage(items) {
  const groups = [];
  const indexes = new Map();
  for (const item of items) {
    if (!indexes.has(item.package)) {
      indexes.set(item.package, groups.length);
      groups.push({ package: item.package, imports: [] });
    }
    groups[indexes.get(item.package)].imports.push(item);
  }
  groups.sort((left, right) => left.package.localeCompare(right.package));
  return groups;
}

function collectInterfaceRecords(items, shimsByTarget) {
  const records = [];
  const seen = new Set();
  for (const item of items) {
    const shim = shimsByTarget.get(item.target);
    if (!shim || shim.lowering.do_result.kind !== "record") continue;
    const record = shim.lowering.do_result;
    const name = witRecordTypeName(record.name);
    if (seen.has(name)) continue;
    records.push({
      name,
      fields: record.fields,
    });
    seen.add(name);
  }
  return records;
}

function witFunctionResultType(shim) {
  const result = shim.lowering.do_result;
  if (result.kind === "unit") return "_";
  if (result.kind === "scalar") return result.type;
  if (result.kind === "record") return witRecordTypeName(result.name);
  if (result.kind === "list") return `list<${result.elem}>`;
  if (result.kind === "result") return `result<${result.ok}, ${result.err}>`;
  failPlan(`unsupported WIT function result kind: ${result.kind}`);
}

function witRecordTypeName(name) {
  return name
    .replace(/([a-z0-9])([A-Z])/g, "$1-$2")
    .replace(/_/g, "-")
    .toLowerCase();
}

function emitResourceInterfaceBody(lines, items, shimsByTarget) {
  if (items.some((item) => item.package === "filesystem" && item.interface === "types")) {
    lines.push("  type filesize = u64;", "");
    lines.push("  flags path-flags {");
    lines.push("    symlink-follow,");
    lines.push("  }", "");
    if (items.some((item) => item.member === "descriptor.open-at")) {
      lines.push("  flags open-flags {");
      lines.push("    create,");
      lines.push("    directory,");
      lines.push("    exclusive,");
      lines.push("    truncate,");
      lines.push("  }", "");
      lines.push("  flags descriptor-flags {");
      lines.push("    read,");
      lines.push("    write,");
      lines.push("    file-integrity-sync,");
      lines.push("    data-integrity-sync,");
      lines.push("    requested-write-sync,");
      lines.push("    mutate-directory,");
      lines.push("  }", "");
    }
    lines.push("  enum error-code {");
    for (const variant of wasiFilesystemErrorCodeVariants()) {
      lines.push(`    ${variant},`);
    }
    lines.push("  }", "");
  }
  if (items.some((item) => item.package === "io" && item.interface === "streams")) {
    lines.push("  variant stream-error {");
    lines.push("    closed,");
    lines.push("  }", "");
  }

  const descriptorMethods = items.filter(isDescriptorMethodImport);
  const descriptorDrops = items.filter(isDescriptorDropImport);
  if (descriptorMethods.length !== 0 || descriptorDrops.length !== 0) {
    lines.push("  resource descriptor {");
    for (const item of descriptorMethods) {
      const shim = shimsByTarget.get(item.target);
      if (!shim) failPlan(`missing shim for import: ${item.target}`);
      const method = item.member.slice("descriptor.".length);
      ensureWitIdent(method, "resource method");
      lines.push(`    ${method}: func(${witResourceMethodParams(item)}) -> ${witFunctionResultType(shim)};`);
    }
    lines.push("  }");
  }

  const inputStreamMethods = items.filter(isInputStreamMethodImport);
  if (inputStreamMethods.length !== 0) {
    lines.push("  resource input-stream {");
    for (const item of inputStreamMethods) {
      const shim = shimsByTarget.get(item.target);
      if (!shim) failPlan(`missing shim for import: ${item.target}`);
      const method = item.member.slice("input-stream.".length);
      ensureWitIdent(method, "resource method");
      lines.push(`    ${method}: func(${witResourceMethodParams(item)}) -> ${witFunctionResultType(shim)};`);
    }
    lines.push("  }");
  }

  const outputStreamMethods = items.filter(isOutputStreamMethodImport);
  if (outputStreamMethods.length !== 0) {
    lines.push("  resource output-stream {");
    for (const item of outputStreamMethods) {
      const shim = shimsByTarget.get(item.target);
      if (!shim) failPlan(`missing shim for import: ${item.target}`);
      const method = item.member.slice("output-stream.".length);
      ensureWitIdent(method, "resource method");
      lines.push(`    ${method}: func(${witResourceMethodParams(item)}) -> ${witFunctionResultType(shim)};`);
    }
    lines.push("  }");
  }
}

function wasiFilesystemErrorCodeVariants() {
  return [
    "access",
    "would-block",
    "already",
    "bad-descriptor",
    "busy",
    "deadlock",
    "quota",
    "exist",
    "file-too-large",
    "illegal-byte-sequence",
    "in-progress",
    "interrupted",
    "invalid",
    "io",
    "is-directory",
    "loop",
    "too-many-links",
    "message-size",
    "name-too-long",
    "no-device",
    "no-entry",
    "no-lock",
    "insufficient-memory",
    "insufficient-space",
    "not-directory",
    "not-empty",
    "not-recoverable",
    "unsupported",
    "no-tty",
    "no-such-device",
    "overflow",
    "not-permitted",
    "pipe",
    "read-only",
    "invalid-seek",
    "text-file-busy",
    "cross-device",
  ];
}

function isResourceMethodImport(item) {
  return isDescriptorDropImport(item) || isDescriptorMethodImport(item) || isInputStreamMethodImport(item) || isOutputStreamMethodImport(item);
}

function isDescriptorMethodImport(item) {
  return item.package === "filesystem" && item.interface === "types" && item.member.startsWith("descriptor.") && !isDescriptorDropImport(item);
}

function isDescriptorDropImport(item) {
  return item.package === "filesystem" && item.interface === "types" && item.member === "descriptor.drop";
}

function isInputStreamMethodImport(item) {
  return item.package === "io" && item.interface === "streams" && item.member.startsWith("input-stream.");
}

function isOutputStreamMethodImport(item) {
  return item.package === "io" && item.interface === "streams" && item.member.startsWith("output-stream.");
}

function witResourceMethodParams(item) {
  if (item.package === "filesystem" && item.interface === "types" && item.member === "descriptor.sync") {
    return "";
  }
  if (item.package === "filesystem" && item.interface === "types" && item.member === "descriptor.write") {
    return "buffer: list<u8>, offset: filesize";
  }
  if (item.package === "filesystem" && item.interface === "types" && item.member === "descriptor.read") {
    return "length: filesize, offset: filesize";
  }
  if (item.package === "filesystem" && item.interface === "types" && item.member === "descriptor.link-at") {
    return "old-flags: path-flags, old-path: string, new-descriptor: borrow<descriptor>, new-path: string";
  }
  if (item.package === "filesystem" && item.interface === "types" && item.member === "descriptor.create-directory-at") {
    return "path: string";
  }
  if (item.package === "filesystem" && item.interface === "types" && item.member === "descriptor.open-at") {
    return "path-flags: path-flags, path: string, open-flags: open-flags, descriptor-flags: descriptor-flags";
  }
  if (item.package === "filesystem" && item.interface === "types" && item.member === "descriptor.remove-directory-at") {
    return "path: string";
  }
  if (item.package === "io" && item.interface === "streams" && item.member === "input-stream.read") {
    return "len: u64";
  }
  if (item.package === "io" && item.interface === "streams" && item.member === "output-stream.check-write") {
    return "";
  }
  if (item.package === "io" && item.interface === "streams" && item.member === "output-stream.write") {
    return "contents: list<u8>";
  }
  if (item.package === "io" && item.interface === "streams" && item.member === "output-stream.flush") {
    return "";
  }
  failPlan(`unsupported resource method WIT emitter: ${item.target}`);
}

function ensureWitIdent(value, kind) {
  if (/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(value)) return;
  failPlan(`invalid WIT ${kind} identifier: ${value}`);
}

function buildLoweringPlan(resolved, doResult) {
  const coreParams = resolved.params.flatMap(coreTypesForParamWit);
  const coreResults = canonicalResultTypes(doResult);
  if (doResult.kind === "record" || doResult.kind === "list" || doResult.kind === "result") {
    coreParams.push("i32");
  }

  return {
    component_import: {
      package: resolved.package,
      interface: resolved.interface,
      member: resolved.member,
    },
    canonical_abi: {
      params: coreParams,
      results: coreResults,
    },
    core_import: {
      module: `cm32p2|wasi:${resolved.package}/${resolved.interface}`,
      name: coreImportName(resolved),
      params: coreParams,
      results: coreResults,
    },
    do_result: doResult,
  };
}

function canonicalResultTypes(doResult) {
  if (doResult.kind === "unit") return [];
  if (doResult.kind === "scalar") return [doResult.core_type];
  if (doResult.kind === "record") return [];
  if (doResult.kind === "list") return [];
  if (doResult.kind === "result") return [];
  return [];
}

function buildScalarResultLayout(type) {
  return {
    kind: "scalar",
    type,
    size: scalarByteSize(type),
    align: scalarByteAlign(type),
    core_type: coreTypeForScalarWit(type),
  };
}

function buildUnitResultLayout() {
  return {
    kind: "unit",
    size: 0,
    align: 1,
  };
}

function buildRecordResultLayout(record) {
  const fields = [];
  let offset = 0;
  for (const field of record.fields) {
    const size = scalarByteSize(field.type);
    const align = scalarByteAlign(field.type);
    offset = alignUp(offset, align);
    fields.push({
      name: field.name,
      type: field.type,
      offset,
      size,
      align,
      core_type: coreTypeForScalarWit(field.type),
    });
    offset += size;
  }
  return {
    kind: "record",
    name: record.name,
    size: alignUp(offset, 4),
    align: 4,
    fields,
  };
}

function buildListPreopenResultLayout() {
  // Canonical ABI list{ptr,len} in result area; each element is tuple:
  // descriptor i32 @0, string {ptr,len} @4/@8 → 12 bytes (align 4).
  return {
    kind: "list",
    elem: "tuple<descriptor,string>",
    size: 8,
    align: 4,
    ptr_offset: 0,
    len_offset: 4,
    element: {
      size: 12,
      align: 4,
      fields: [
        { name: "descriptor", kind: "resource", type: "descriptor", offset: 0, core_type: "i32" },
        { name: "path", kind: "string", ptr_offset: 4, len_offset: 8 },
      ],
    },
  };
}

function isListTupleDescriptorStringSignature(resolved) {
  return (
    resolved.package === "filesystem" &&
    resolved.interface === "preopens" &&
    resolved.member === "get-directories" &&
    resolved.params.length === 0 &&
    (resolved.result === "list<tuple<descriptor,string>>" ||
      resolved.result === "list<tuple<descriptor,string>>")
  );
}

function buildListU8ResultLayout() {
  return {
    kind: "list",
    elem: "u8",
    size: 8,
    align: 4,
    ptr_offset: 0,
    len_offset: 4,
    elem_size: 1,
    elem_align: 1,
  };
}

function buildResultUnitErrorCodeLayout() {
  return {
    kind: "result",
    ok: "_",
    err: "error-code",
    ok_core_type: null,
    err_core_type: "i32",
    tag_offset: 0,
    payload_offset: 4,
    size: 8,
    align: 4,
  };
}

function buildResultFilesizeErrorCodeLayout() {
  return {
    kind: "result",
    ok: "filesize",
    err: "error-code",
    ok_core_type: "i64",
    err_core_type: "i32",
    tag_offset: 0,
    payload_offset: 8,
    size: 16,
    align: 8,
  };
}

function buildResultDescriptorErrorCodeLayout() {
  return {
    kind: "result",
    ok: "descriptor",
    err: "error-code",
    ok_core_type: "i32",
    err_core_type: "i32",
    tag_offset: 0,
    payload_offset: 4,
    size: 8,
    align: 4,
  };
}

function buildResultListU8BoolErrorCodeLayout() {
  return {
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
  };
}

function buildResultListU8StreamErrorLayout() {
  return {
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
  };
}

function buildResultUnitStreamErrorLayout() {
  return {
    kind: "result",
    ok: "_",
    err: "stream-error",
    ok_core_type: null,
    err_core_type: "i32",
    tag_offset: 0,
    payload_offset: 4,
    size: 8,
    align: 4,
  };
}

function buildResultU64StreamErrorLayout() {
  return {
    kind: "result",
    ok: "u64",
    err: "stream-error",
    ok_core_type: "i64",
    err_core_type: "i32",
    tag_offset: 0,
    payload_offset: 8,
    size: 16,
    align: 8,
  };
}

function isResultUnitErrorCodeSignature(resolved) {
  if (
    resolved.package === "filesystem" &&
    resolved.interface === "types" &&
    resolved.member === "descriptor.sync" &&
    resolved.params.length === 1 &&
    resolved.params[0] === "descriptor" &&
    resolved.result === "result<_,error-code>"
  ) {
    return true;
  }
  if (
    resolved.package === "filesystem" &&
    resolved.interface === "types" &&
    (resolved.member === "descriptor.create-directory-at" || resolved.member === "descriptor.remove-directory-at") &&
    resolved.params.length === 2 &&
    resolved.params[0] === "descriptor" &&
    resolved.params[1] === "string" &&
    resolved.result === "result<_,error-code>"
  ) {
    return true;
  }
  // G6.3: tcp/udp-socket.bind → result<_,error-code> with socket + address pack ptr.
  if (
    resolved.package === "sockets" &&
    resolved.interface === "types" &&
    (resolved.member === "tcp-socket.bind" || resolved.member === "udp-socket.bind") &&
    resolved.params.length === 2 &&
    (resolved.params[0] === "tcp-socket" || resolved.params[0] === "udp-socket") &&
    resolved.params[1] === "ip-socket-address" &&
    resolved.result === "result<_,error-code>"
  ) {
    return true;
  }
  return (
    resolved.package === "filesystem" &&
    resolved.interface === "types" &&
    resolved.member === "descriptor.link-at" &&
    resolved.params.length === 5 &&
    resolved.params[0] === "descriptor" &&
    resolved.params[1] === "path-flags" &&
    resolved.params[2] === "string" &&
    resolved.params[3] === "borrow<descriptor>" &&
    resolved.params[4] === "string" &&
    resolved.result === "result<_,error-code>"
  );
}

function isResourceDropSignature(resolved) {
  if (
    resolved.package === "filesystem" &&
    resolved.interface === "types" &&
    resolved.member === "descriptor.drop" &&
    resolved.params.length === 1 &&
    resolved.params[0] === "descriptor" &&
    resolved.result === "nil"
  ) {
    return true;
  }
  // G6.3: tcp/udp-socket.drop
  return (
    resolved.package === "sockets" &&
    resolved.interface === "types" &&
    (resolved.member === "tcp-socket.drop" || resolved.member === "udp-socket.drop") &&
    resolved.params.length === 1 &&
    (resolved.params[0] === "tcp-socket" || resolved.params[0] === "udp-socket") &&
    resolved.result === "nil"
  );
}

function isResultSocketErrorCodeSignature(resolved) {
  return (
    resolved.package === "sockets" &&
    resolved.interface === "types" &&
    (resolved.member === "tcp-socket.create" || resolved.member === "udp-socket.create") &&
    resolved.params.length === 1 &&
    resolved.params[0] === "ip-address-family" &&
    (resolved.result === "result<tcp-socket,error-code>" || resolved.result === "result<udp-socket,error-code>")
  );
}

function isResultFilesizeErrorCodeSignature(resolved) {
  return (
    resolved.package === "filesystem" &&
    resolved.interface === "types" &&
    resolved.member === "descriptor.write" &&
    resolved.params.length === 3 &&
    resolved.params[0] === "descriptor" &&
    resolved.params[1] === "list<u8>" &&
    resolved.params[2] === "filesize" &&
    resolved.result === "result<filesize,error-code>"
  );
}

function isResultDescriptorErrorCodeSignature(resolved) {
  return (
    resolved.package === "filesystem" &&
    resolved.interface === "types" &&
    resolved.member === "descriptor.open-at" &&
    resolved.params.length === 5 &&
    resolved.params[0] === "descriptor" &&
    resolved.params[1] === "path-flags" &&
    resolved.params[2] === "string" &&
    resolved.params[3] === "open-flags" &&
    resolved.params[4] === "descriptor-flags" &&
    resolved.result === "result<descriptor,error-code>"
  );
}

function isResultListU8BoolErrorCodeSignature(resolved) {
  return (
    resolved.package === "filesystem" &&
    resolved.interface === "types" &&
    resolved.member === "descriptor.read" &&
    resolved.params.length === 3 &&
    resolved.params[0] === "descriptor" &&
    resolved.params[1] === "filesize" &&
    resolved.params[2] === "filesize" &&
    resolved.result === "result<tuple<list<u8>,bool>,error-code>"
  );
}

function isResultListU8StreamErrorSignature(resolved) {
  return (
    resolved.package === "io" &&
    resolved.interface === "streams" &&
    resolved.member === "input-stream.read" &&
    resolved.params.length === 2 &&
    resolved.params[0] === "input-stream" &&
    resolved.params[1] === "u64" &&
    resolved.result === "result<list<u8>,stream-error>"
  );
}

function isResultUnitStreamErrorSignature(resolved) {
  if (resolved.package !== "io" || resolved.interface !== "streams") return false;
  if (resolved.member === "output-stream.write") {
    return (
      resolved.params.length === 2 &&
      resolved.params[0] === "output-stream" &&
      resolved.params[1] === "list<u8>" &&
      resolved.result === "result<_,stream-error>"
    );
  }
  return (
    resolved.member === "output-stream.flush" &&
    resolved.params.length === 1 &&
    resolved.params[0] === "output-stream" &&
    resolved.result === "result<_,stream-error>"
  );
}

function isResultU64StreamErrorSignature(resolved) {
  return (
    resolved.package === "io" &&
    resolved.interface === "streams" &&
    resolved.member === "output-stream.check-write" &&
    resolved.params.length === 1 &&
    resolved.params[0] === "output-stream" &&
    resolved.result === "result<u64,stream-error>"
  );
}

function coreImportName(resolved) {
  if (
    resolved.package === "filesystem" &&
    resolved.interface === "types" &&
    resolved.member === "descriptor.drop"
  ) {
    return "[resource-drop]descriptor";
  }
  if (
    resolved.package === "sockets" &&
    resolved.interface === "types" &&
    resolved.member === "tcp-socket.drop"
  ) {
    return "[resource-drop]tcp-socket";
  }
  if (
    resolved.package === "sockets" &&
    resolved.interface === "types" &&
    resolved.member === "udp-socket.drop"
  ) {
    return "[resource-drop]udp-socket";
  }
  if (
    resolved.package === "sockets" &&
    resolved.interface === "types" &&
    (resolved.member === "tcp-socket.create" || resolved.member === "udp-socket.create")
  ) {
    // Match wat_component_metadata wasiLowering: [static]tcp-socket.create
    return `[static]${resolved.member}`;
  }
  if (
    resolved.package === "sockets" &&
    resolved.interface === "types" &&
    (resolved.member === "tcp-socket.bind" || resolved.member === "udp-socket.bind")
  ) {
    return `[method]${resolved.member}`;
  }
  if (resolved.package === "filesystem" && resolved.interface === "types" && resolved.member.startsWith("descriptor.")) {
    return `[method]${resolved.member}`;
  }
  if (resolved.package === "io" && resolved.interface === "streams" &&
    (resolved.member.startsWith("input-stream.") || resolved.member.startsWith("output-stream."))) {
    return `[method]${resolved.member}`;
  }
  return resolved.member;
}

function isLowerableParamWitType(type) {
  return isScalarWitType(type) ||
    type === "descriptor" ||
    type === "input-stream" ||
    type === "output-stream" ||
    type === "borrow<descriptor>" ||
    type === "path-flags" ||
    type === "open-flags" ||
    type === "descriptor-flags" ||
    type === "string" ||
    type === "list<u8>" ||
    // G6.3 sockets
    type === "tcp-socket" ||
    type === "udp-socket" ||
    type === "ip-address-family" ||
    type === "ip-socket-address";
}

function coreTypesForParamWit(type) {
  if (type === "descriptor") return ["i32"];
  if (type === "input-stream") return ["i32"];
  if (type === "output-stream") return ["i32"];
  if (type === "borrow<descriptor>") return ["i32"];
  if (type === "path-flags") return ["i32"];
  if (type === "open-flags") return ["i32"];
  if (type === "descriptor-flags") return ["i32"];
  if (type === "string") return ["i32", "i32"];
  if (type === "list<u8>") return ["i32", "i32"];
  // G6.3: resource handles and family disc as i32; address is guest-packed ptr.
  if (type === "tcp-socket") return ["i32"];
  if (type === "udp-socket") return ["i32"];
  if (type === "ip-address-family") return ["i32"];
  if (type === "ip-socket-address") return ["i32"];
  return [coreTypeForScalarWit(type)];
}

function alignUp(value, align) {
  return Math.ceil(value / align) * align;
}

function unsupportedShim() {
  return {
    kind: "unsupported",
    reason: "non-scalar-or-record-signature",
  };
}

function isScalarWitType(type) {
  return [
    "bool",
    "filesize",
    "u8",
    "u16",
    "u32",
    "u64",
    "s8",
    "s16",
    "s32",
    "s64",
    "f32",
    "f64",
    "char",
  ].includes(type);
}

function scalarByteSize(type) {
  switch (type) {
    case "bool":
    case "u8":
    case "s8":
      return 1;
    case "u16":
    case "s16":
      return 2;
    case "u32":
    case "s32":
    case "f32":
    case "char":
      return 4;
    case "u64":
    case "s64":
    case "f64":
    case "filesize":
      return 8;
    default:
      throw new Error(`unsupported scalar WIT type: ${type}`);
  }
}

function scalarByteAlign(type) {
  return Math.min(scalarByteSize(type), 4);
}

function coreTypeForScalarWit(type) {
  switch (type) {
    case "bool":
    case "u8":
    case "u16":
    case "u32":
    case "s8":
    case "s16":
    case "s32":
    case "char":
      return "i32";
    case "u64":
    case "s64":
    case "filesize":
      return "i64";
    case "f32":
      return "f32";
    case "f64":
      return "f64";
    default:
      throw new Error(`unsupported scalar WIT type: ${type}`);
  }
}

function fail(lineNo, message) {
  console.error(`${watPath}:${lineNo + 1}: ${message}`);
  process.exit(1);
}

function failPlan(message) {
  console.error(`${watPath}: ${message}`);
  process.exit(1);
}

function failRegistry(filePath, message) {
  console.error(`${filePath}: ${message}`);
  process.exit(1);
}
