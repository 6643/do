#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    fd -H -I --max-depth 1 --type f --type d . "$tmp_dir" -X rm -rf --
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

core_wat="$tmp_dir/owned-record-producer.wat"
wit="$tmp_dir/owned-record-producer.wit"
core_wasm="$tmp_dir/owned-record-producer.core.wasm"
embedded="$tmp_dir/owned-record-producer.embedded.wasm"
component="$tmp_dir/owned-record-producer.component.wasm"

test -x "$do_bin"
test -f "$source"
test -f "$probe_wit"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace

rg -Fq 'package do:g6-2-owned-record-producer@0.1.0;' "$wit"
rg -Fq 'interface source {' "$wit"
rg -Fq 'interface sink {' "$wit"
rg -Fq 'consume-via-stream: async func(' "$wit"
rg -Fq 'data: stream<resource-entry>' "$wit"
rg -Fq 'resource-entry { ticket: own<ticket> }' "$wit"
rg -Fq 'world owned-record-producer' "$wit"
rg -Fq 'export produce: async func(mode: u32) -> result<_, error-code>;' "$wit"
if rg -q 'do:g6-2-(c-min|batched|dynamic|scalar-list)-producer|stream<list<|stream<variant' "$wit"; then
  printf 'owned-record producer emitted an out-of-scope neighboring shape\n' >&2
  exit 1
fi

for marker in \
  '[producer-record-byte-size] 4' \
  '[producer-record-ticket-offset] 0' \
  '[producer-stream-capacity] 1' \
  '[producer-ticket-seed] 111' \
  '[producer-record-transfer]' \
  '[producer-resource-drop-exactly-once]' \
  '[producer-child-before-parent-cleanup]'; do
  rg -Fq ";; $marker" "$core_wat"
done
rg -Fq '[async-lift]produce' "$core_wat"
if rg -Fq '__arc_' "$core_wat"; then
  printf 'owned-record producer emitted an ARC symbol\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-producer \
  -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'G6.2 owned-record producer Do Component gate passed\n'
