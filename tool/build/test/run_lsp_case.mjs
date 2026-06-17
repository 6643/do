import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";

function frame(message) {
  const body = JSON.stringify(message);
  return `Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`;
}

const [doBin, fixturePath] = process.argv.slice(2);
if (!doBin || !fixturePath) {
  console.error("usage: run_lsp_case.mjs <do-bin> <fixture.json>");
  process.exit(1);
}

const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
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
  console.error(stderr);
  process.exit(1);
}

if (stderr.length !== 0) {
  console.error(`unexpected stderr: ${stderr}`);
  process.exit(1);
}

let lastIndex = -1;
for (const needle of fixture.expect) {
  const index = stdout.indexOf(needle);
  if (index === -1) {
    console.error(`missing expected output: ${needle}`);
    console.error(stdout);
    process.exit(1);
  }
  if (fixture.ordered === true && index < lastIndex) {
    console.error(`expected output out of order: ${needle}`);
    console.error(stdout);
    process.exit(1);
  }
  lastIndex = index;
}

console.log(`ok: lsp ${fixture.name}`);
