import assert from "node:assert/strict";
import fs from "node:fs";

const [createPath, ipv4Path, ipv6Path, dynamicPath] = process.argv.slice(2);
if (!createPath || !ipv4Path || !ipv6Path || !dynamicPath) {
  throw new Error("usage: test_socket_abi.mjs <create.wat> <ipv4.wat> <ipv6.wat> <dynamic.wat>");
}

const readFunction = (filePath, name) => {
  const wat = fs.readFileSync(filePath, "utf8");
  const start = wat.indexOf(`  (func $${name}`);
  assert.notEqual(start, -1, `${filePath}: missing ${name}`);
  return wat.slice(start, wat.indexOf("\n  )", start));
};

const readStart = (filePath) => readFunction(filePath, "_start");

const create = readStart(createPath);
assert.match(create, /i32\.const 4\n\s+local\.set \$__wasi_family_tmp/);
assert.match(create, /local\.get \$__wasi_family_tmp\n\s+i32\.const 4\n\s+i32\.eq\n\s+if \(result i32\)\n\s+i32\.const 0/);
assert.doesNotMatch(
  create,
  /i32\.const 4\n\s+global\.get \$__wasi_result_area_base\n\s+call \$__wasi_import_sockets_types_tcp_socket_create/,
);

const ipv4 = readStart(ipv4Path);
for (const [offset, field] of [[72, "a"], [73, "b"], [74, "c"], [75, "d"]]) {
  assert.match(
    ipv4,
    new RegExp(`i32\\.const ${offset}\\n\\s+i32\\.add\\n\\s+local\\.get \\$a\\.${field}\\n\\s+i32\\.store8`),
  );
}
assert.doesNotMatch(ipv4, /i32\.const 70\n\s+i32\.add\n\s+local\.get \$a\.a\n\s+i32\.store8/);

const ipv6 = readStart(ipv6Path);
assert.match(ipv6, /i32\.const 76\n\s+i32\.add\n\s+local\.get \$v\.hi\n\s+i64\.const 56\n\s+i64\.shr_u/);
assert.match(ipv6, /i32\.const 84\n\s+i32\.add\n\s+local\.get \$v\.lo\n\s+i64\.const 56\n\s+i64\.shr_u/);
assert.doesNotMatch(ipv6, /local\.get \$v\.hi\n\s+i64\.store/);
assert.doesNotMatch(ipv6, /local\.get \$v\.lo\n\s+i64\.store/);

const dynamic = readFunction(dynamicPath, "make_socket");
assert.match(dynamic, /local\.get \$family\n\s+local\.set \$__wasi_family_tmp/);
assert.match(dynamic, /local\.get \$__wasi_family_tmp\n\s+i32\.const 4\n\s+i32\.eq/);

console.log("ok: socket ABI");
