import { readFileSync } from "node:fs";

const wasmPath = process.argv[2];
if (!wasmPath) {
  console.error("usage: node run_wasm_program.mjs <program.wasm>");
  process.exit(2);
}

const bytes = readFileSync(wasmPath);
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

if (typeof instance.exports._start !== "function") {
  throw new Error("missing _start export");
}

instance.exports._start();

for (const line of logs) {
  console.log(line);
}
