#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-sockets-real.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

runner_env=(
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

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
    "$source" --p3-wasi-sockets-create-bind-drop-component \
    --p3-wit-output "$wit" -o "$wat" >/dev/null
  wasm-tools parse "$wat" -o "$core"
  wasm-tools component embed "$wit" "$core" --world socket-probe -o "$embedded"
  wasm-tools component new "$embedded" -o "$component"
  wasm-tools validate "$component"

  for failure in none create bind; do
    output=$(cd "$runner_dir" && env "${runner_env[@]}" \
      DO_D2_SOCKET_FAILURE="$failure" \
      cargo run --quiet --bin do-p3-wasi-sockets-real -- "$component" "$protocol")
    case "$failure" in
      none) grep -Fq "real-sockets passed protocol=${protocol} failure=none result=1 create=1 bind=1 drop=1 errors=0 table-empty=true" <<<"$output" ;;
      create) grep -Fq "real-sockets passed protocol=${protocol} failure=create result=0 create=1 bind=0 drop=0 errors=1 table-empty=true" <<<"$output" ;;
      bind) grep -Fq "real-sockets passed protocol=${protocol} failure=bind result=2 create=1 bind=1 drop=1 errors=1 table-empty=true" <<<"$output" ;;
    esac
  done
done

printf 'D2 real socket TCP/UDP loopback smoke passed\n'
