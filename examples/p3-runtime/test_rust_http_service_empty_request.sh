#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-service-empty-request.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/service.wat"
core_wasm="$tmp_dir/service.wasm"
embedded="$tmp_dir/service.embedded.wasm"
component="$tmp_dir/service.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/http-service-empty-request.do" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[constructor]fields"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[static]request.new"' "$core_wat"
grep -Fq '"wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request"' "$core_wat"

cat >>"$wit_dir/worlds.wit" <<'WIT'

interface probe {
  use types.{response, error-code};
  run: async func() -> result<response, error-code>;
}

world http-request-empty-service-probe {
  import types;
  import client;
  export probe;
}
WIT

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world http-request-empty-service-probe \
  --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

output=$(cd "$runner_dir" && \
  CC="$PWD/zig-cc.sh" \
  CXX="$PWD/zig-cc.sh" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
  timeout 30s cargo run --quiet --bin do-p3-http-service-empty-request-host-runner -- "$component")
for marker in \
  'Rust P3 HTTP empty request service adapter passed' \
  'requests=2' \
  'responses=1' \
  'request-drops=0' \
  'response-drops=1' \
  'transmission-future-drops=2' \
  'trailers-future-drops=2' \
  'table-empty=true'; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2
      exit 1
      ;;
  esac
done

printf 'WASI HTTP empty request client.send runtime passed\n'
