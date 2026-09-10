#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-list-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-list-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-list-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wat="$tmp_dir/list-owned-record-producer.wat"
wit="$tmp_dir/list-owned-record-producer.wit"
stderr="$tmp_dir/build.stderr"

test -x "$do_bin"
test -f "$source"

if DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat" \
  >"$tmp_dir/build.stdout" 2>"$stderr"; then
  printf 'list-owned-record producer unexpectedly admitted before implementation\n' >&2
  exit 1
fi
grep -Fq 'UnknownP3AsyncHostDescriptor' "$stderr"
test ! -e "$wat"
test ! -e "$wit"

printf 'G6.2 list-owned-record producer RED gate passed diagnostic=UnknownP3AsyncHostDescriptor emission=none\n'
