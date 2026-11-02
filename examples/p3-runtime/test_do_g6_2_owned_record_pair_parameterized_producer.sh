#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-pair-parameterized-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-pair-parameterized-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-pair-parameterized-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    fd -H -I --max-depth 1 --type f --type d . "$tmp_dir" -X rm -rf --
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

core_wat="$tmp_dir/owned-record-pair-parameterized-producer.wat"
wit="$tmp_dir/owned-record-pair-parameterized-producer.wit"
core_wasm="$tmp_dir/owned-record-pair-parameterized-producer.core.wasm"
embedded="$tmp_dir/owned-record-pair-parameterized-producer.embedded.wasm"
component="$tmp_dir/owned-record-pair-parameterized-producer.component.wasm"

test -x "$do_bin"
test -f "$source"
test -f "$probe_wit"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a

rg -Fq 'package do:g6-2-owned-record-pair-parameterized-producer@0.1.0;' "$wit"
rg -Fq 'record resource-pair {' "$wit"
rg -Fq 'left: own<ticket>,' "$wit"
rg -Fq 'right: own<ticket>,' "$wit"
rg -Fq 'data: stream<resource-pair>' "$wit"
rg -Fq 'world owned-record-pair-parameterized-producer' "$wit"
rg -Fq 'export produce: async func(' "$wit"
rg -Fq 'mode: u32,' "$wit"
rg -Fq 'left-seed: u32,' "$wit"
rg -Fq 'right-seed: u32' "$wit"
if rg -q 'do:g6-2-(c-min|batched|dynamic|scalar-list|owned-record)-producer|stream<list<|stream<variant' "$wit"; then
  printf 'parameterized pair producer emitted an out-of-scope neighboring shape\n' >&2
  exit 1
fi

for marker in \
  '[producer-record-byte-size] 8' \
  '[producer-record-left-offset] 0' \
  '[producer-record-right-offset] 4' \
  '[producer-stream-capacity] 1' \
  '[producer-input-mode]' \
  '[producer-left-ticket-seed-param]' \
  '[producer-right-ticket-seed-param]' \
  '[producer-seed-order] left then right' \
  '[producer-input-word-count] 3' \
  '[producer-record-transfer]' \
  '[producer-resource-drop-exactly-once]' \
  '[producer-child-before-parent-cleanup]'; do
  rg -Fq ";; $marker" "$core_wat"
done
rg -Fq '[async-lift]produce' "$core_wat"
if rg -Fq '__arc_' "$core_wat"; then
  printf 'parameterized pair producer emitted an ARC symbol\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-pair-parameterized-producer \
  -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'G6.2 parameterized owned-record pair producer Do Component gate passed\n'
