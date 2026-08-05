#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-sockets.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

version=$(wasm-tools --version)
case "$version" in
  "wasm-tools 1.254.0"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$version" >&2; exit 1 ;;
esac

for protocol in tcp udp; do
  source="$repo_root/examples/p3-runtime/wasi-sockets-create-bind-drop-component.do"
  if [[ "$protocol" == "udp" ]]; then
    source="$repo_root/examples/p3-runtime/wasi-udp-sockets-create-bind-drop-component.do"
  fi
  wat="$tmp_dir/${protocol}.wat"
  wit="$tmp_dir/${protocol}.wit"
  core="$tmp_dir/${protocol}.core.wasm"
  embedded="$tmp_dir/${protocol}.embedded.wasm"
  component="$tmp_dir/${protocol}.component.wasm"

  DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
    "$source" \
    --p3-wasi-sockets-create-bind-drop-component \
    --p3-wit-output "$wit" \
    -o "$wat" >/dev/null

  grep -Fq "[static]${protocol}-socket.create" "$wat"
  grep -Fq "[method]${protocol}-socket.bind" "$wat"
  grep -Fq "[resource-drop]${protocol}-socket" "$wat"
  wasm-tools parse "$wat" -o "$core"
  wasm-tools component embed "$wit" "$core" --world socket-probe -o "$embedded"
  wasm-tools component new "$embedded" -o "$component"
  wasm-tools validate "$component"
done

negative_wat="$tmp_dir/negative.wat"
negative_stderr="$tmp_dir/negative.stderr"
if DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/wasi-sockets-create-bind-drop-negative.do" \
  --p3-wasi-sockets-create-bind-drop-component \
  -o "$negative_wat" >/dev/null 2>"$negative_stderr"; then
  printf 'negative socket target unexpectedly compiled\n' >&2
  exit 1
fi
grep -Fq 'UnsupportedP3WasiSocketsCreateBindDropComponent' "$negative_stderr"

printf 'D2 socket Component assembly passed tcp+udp\n'
