#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-mixed-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-mixed-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-mixed-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wat="$tmp_dir/mixed-owned-record-producer.wat"
wit="$tmp_dir/mixed-owned-record-producer.wit"

test -x "$do_bin"
test -f "$source"
test -f "$probe_wit"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat"

test -s "$wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
grep -Fq 'package do:g6-2-owned-record-mixed-producer@0.1.0;' "$wit"
grep -Fq 'record mixed-entry' "$wit"
grep -Fq 'data: stream<mixed-entry>' "$wit"
grep -Fq 'export produce: async func(mode: u32) -> result<_, error-code>;' "$wit"
grep -Fq ';; [producer-record-byte-size] 8' "$wat"
grep -Fq ';; [producer-record-code-offset] 0' "$wat"
grep -Fq ';; [producer-record-ticket-offset] 4' "$wat"
grep -Fq ';; [producer-stream-capacity] 1' "$wat"
grep -Fq ';; [producer-record-transfer]' "$wat"
grep -Fq ';; [producer-resource-drop-exactly-once]' "$wat"
if grep -Fq '__arc_' "$wat"; then
  printf 'mixed owned-record producer emitted an ARC symbol\n' >&2
  exit 1
fi

printf 'G6.2 mixed owned-record producer Do Component gate passed\n'
