#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
fixture="$repo_root/examples/p3-runtime/http-client-send.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-client-send.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/client.wat"
wit_dir="$tmp_dir/client.wit-package"
core_wasm="$tmp_dir/client.wasm"
embedded="$tmp_dir/client.embedded.wasm"
component="$tmp_dir/client.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

grep -Fq '"wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]response"' "$core_wat"
cat >>"$wit_dir/worlds.wit" <<'WIT'

interface probe {
  use types.{request, response, error-code};
  run: async func(request: request) -> result<response, error-code>;
}

world http-client-probe {
  import client;
  export probe;
}
WIT

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit_dir" "$core_wasm" --world http-client-probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate "$component"

output=$(cd "$repo_root/examples/p3-runtime/rust-host-runner" && \
  CC="$PWD/zig-cc.sh" CXX="$PWD/zig-cc.sh" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
  cargo run --quiet --bin do-p3-http-client-send-host-runner -- "$component")
for marker in 'Rust P3 HTTP client send adapter passed' 'requests=2' 'responses=1' 'drops=1'; do
  case "$output" in
    *"$marker"*) ;;
    *) printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2; exit 1 ;;
  esac
done

printf 'WASI HTTP client send lowering passed\n'
