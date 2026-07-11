import { readFileSync } from "node:fs";

const wasmPath = process.argv[2];
if (!wasmPath) {
  console.error("usage: node run_compiled_test_case.mjs <case.wasm> [case.wat]");
  process.exit(2);
}
const watPath = process.argv[3];

const bytes = readFileSync(wasmPath);
const testNames = readTestManifest(watPath);
const logs = [];
const decoder = new TextDecoder("utf-8", { fatal: true });
let instance;

const imports = {
  env: {
    add(a, b) {
      return a + b;
    },
    dep_add(a, b) {
      return a + b;
    },
    one() {
      return 1;
    },
    two() {
      return 2;
    },
    log(ptr, len) {
      const memory = instance?.exports?.memory;
      if (!(memory instanceof WebAssembly.Memory)) {
        throw new Error("missing exported memory");
      }
      const view = new Uint8Array(memory.buffer, ptr, len);
      logs.push(decoder.decode(view));
    },
  },
};

const loaded = await WebAssembly.instantiate(bytes, imports);
instance = loaded.instance;

const tests = Object.entries(instance.exports)
  .filter(([name, fn]) => /^__test_[0-9]+$/.test(name) && typeof fn === "function")
  .sort(([a], [b]) => Number(a.slice("__test_".length)) - Number(b.slice("__test_".length)));

if (tests.length === 0) {
  throw new Error("missing compiled test exports");
}

for (const [, fn] of tests) {
  const name = testDisplayName(testNames, tests, fn);
  try {
    fn();
    console.log(`test ${name} ... ok`);
  } catch (err) {
    console.error(`test ${name} ... failed`);
    throw err;
  }
}

console.log(`ok: ${tests.length} passed; 0 failed`);

for (const line of logs) {
  console.log(line);
}

function readTestManifest(path) {
  const names = new Map();
  if (!path) return names;

  const text = readFileSync(path, "utf8");
  for (const line of text.split(/\r?\n/)) {
    const match = /^\s*;; compiled-test ([0-9]+) (.+)$/.exec(line);
    if (!match) continue;
    names.set(Number(match[1]), match[2]);
  }
  return names;
}

function testDisplayName(names, tests, fn) {
  const idx = tests.findIndex(([, candidate]) => candidate === fn);
  if (idx < 0) return "\"unknown\"";
  return names.get(idx) ?? `"__test_${idx}"`;
}
