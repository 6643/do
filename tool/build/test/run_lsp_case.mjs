import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

function frame(message) {
  const body = JSON.stringify(message);
  return `Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`;
}

const [doBin, fixturePath] = process.argv.slice(2);
let cleanupPath = null;

async function cleanup() {
  if (cleanupPath) {
    await rm(cleanupPath, { recursive: true, force: true });
    cleanupPath = null;
  }
}

async function fail(message, details = "") {
  console.error(message);
  if (details) console.error(details);
  await cleanup();
  process.exit(1);
}

if (!doBin || !fixturePath) {
  await fail("usage: run_lsp_case.mjs <do-bin> <fixture.json>");
}

const fixture = JSON.parse(await readFile(fixturePath, "utf8"));

function replacePlaceholders(value, vars) {
  if (typeof value === "string") {
    let out = value;
    for (const [key, replacement] of Object.entries(vars)) {
      out = out.replaceAll(`{{${key}}}`, replacement);
    }
    return out;
  }
  if (Array.isArray(value)) return value.map((item) => replacePlaceholders(item, vars));
  if (value && typeof value === "object") {
    const out = {};
    for (const [key, nested] of Object.entries(value)) {
      out[key] = replacePlaceholders(nested, vars);
    }
    return out;
  }
  return value;
}

const vars = {};
if (fixture.workspace?.files) {
  cleanupPath = await mkdtemp(join(tmpdir(), "do-lsp-"));
  vars.workspaceUri = `file://${cleanupPath}`;
  for (const file of fixture.workspace.files) {
    const target = join(cleanupPath, file.path);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, file.text, "utf8");
  }
}
fixture.messages = replacePlaceholders(fixture.messages, vars);
fixture.expect = replacePlaceholders(fixture.expect, vars);

const child = spawn(doBin, ["lsp"], {
  stdio: ["pipe", "pipe", "pipe"],
  env: { ...process.env, DO_LIB_ROOT: "tool/build/test/lib" },
});

let stdout = "";
let stderr = "";
child.stdout.setEncoding("utf8");
child.stderr.setEncoding("utf8");
child.stdout.on("data", (chunk) => {
  stdout += chunk;
});
child.stderr.on("data", (chunk) => {
  stderr += chunk;
});

for (const message of fixture.messages) {
  child.stdin.write(frame(message));
}
child.stdin.end();

const exitCode = await new Promise((resolve) => {
  child.on("close", resolve);
});

if (exitCode !== 0) {
  await fail(stderr);
}

if (stderr.length !== 0) {
  await fail(`unexpected stderr: ${stderr}`);
}

let lastIndex = -1;
for (const needle of fixture.expect) {
  const index = stdout.indexOf(needle);
  if (index === -1) {
    await fail(`missing expected output: ${needle}`, stdout);
  }
  if (fixture.ordered === true && index < lastIndex) {
    await fail(`expected output out of order: ${needle}`, stdout);
  }
  lastIndex = index;
}

await cleanup();
console.log(`ok: lsp ${fixture.name}`);
