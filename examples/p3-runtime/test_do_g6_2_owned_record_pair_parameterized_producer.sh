#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
wasm_tools_bin=${WASM_TOOLS:-wasm-tools}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-pair-parameterized-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-pair-parameterized-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-pair-parameterized-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
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
command -v "$wasm_tools_bin" >/dev/null 2>&1
expected_tools_version=${WASM_TOOLS_EXPECT_VERSION:-1.255.0}
actual_tools_version=$($wasm_tools_bin --version | awk 'NR == 1 { print $2 }')
test "$actual_tools_version" = "$expected_tools_version"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a

grep -Fq 'package do:g6-2-owned-record-pair-parameterized-producer@0.1.0;' "$wit"
grep -Fq 'record resource-pair {' "$wit"
grep -Fq 'left: own<ticket>,' "$wit"
grep -Fq 'right: own<ticket>,' "$wit"
grep -Fq 'data: stream<resource-pair>' "$wit"
grep -Fq 'world owned-record-pair-parameterized-producer' "$wit"
grep -Fq 'export produce: async func(' "$wit"
grep -Fq 'mode: u32,' "$wit"
grep -Fq 'left-seed: u32,' "$wit"
grep -Fq 'right-seed: u32' "$wit"
if grep -Eq 'do:g6-2-(c-min|batched|dynamic|scalar-list|owned-record)-producer|stream<list<|stream<variant' "$wit"; then
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
  grep -Fq ";; $marker" "$core_wat"
done
grep -Fq '[async-lift]produce' "$core_wat"
if grep -Fq '__arc_' "$core_wat"; then
  printf 'parameterized pair producer emitted an ARC symbol\n' >&2
  exit 1
fi

"$wasm_tools_bin" parse "$core_wat" -o "$core_wasm"
"$wasm_tools_bin" component embed "$wit" "$core_wasm" \
  --world owned-record-pair-parameterized-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
"$wasm_tools_bin" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools_bin" validate --features cm-async,cm-more-async-builtins "$component"

printf 'G6.2 parameterized owned-record pair producer Do Component gate passed\n'
