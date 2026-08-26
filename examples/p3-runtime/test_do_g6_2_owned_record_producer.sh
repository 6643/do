#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
wasm_tools_bin=${WASM_TOOLS:-wasm-tools}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
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
command -v "$wasm_tools_bin" >/dev/null 2>&1

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace

grep -Fq 'package do:g6-2-owned-record-producer@0.1.0;' "$wit"
grep -Fq 'interface source {' "$wit"
grep -Fq 'interface sink {' "$wit"
grep -Fq 'consume-via-stream: async func(' "$wit"
grep -Fq 'data: stream<resource-entry>' "$wit"
grep -Fq 'resource-entry { ticket: own<ticket> }' "$wit"
grep -Fq 'world owned-record-producer' "$wit"
grep -Fq 'export produce: async func(mode: u32) -> result<_, error-code>;' "$wit"
if grep -Eq 'do:g6-2-(c-min|batched|dynamic|scalar-list)-producer|stream<list<|stream<variant' "$wit"; then
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
  grep -Fq ";; $marker" "$core_wat"
done
grep -Fq '[async-lift]produce' "$core_wat"
if grep -Fq '__arc_' "$core_wat"; then
  printf 'owned-record producer emitted an ARC symbol\n' >&2
  exit 1
fi

wasm-tools parse "$core_wat" -o "$core_wasm"
"$wasm_tools_bin" component embed "$wit" "$core_wasm" \
  --world owned-record-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
"$wasm_tools_bin" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools_bin" validate --features cm-async,cm-more-async-builtins "$component"

printf 'G6.2 owned-record producer Do Component gate passed\n'
