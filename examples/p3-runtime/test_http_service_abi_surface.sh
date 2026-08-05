#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit_dir="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16"
minimal_core_wat="$repo_root/examples/p3-runtime/http-service-minimal-async.wat"
do_bin="$repo_root/bin/do"
http_service_source="$repo_root/examples/p3-runtime/http-service.do"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-http-service-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/service.wat"
core_wasm="$tmp_dir/service.wasm"
component_wasm="$tmp_dir/service.component.wasm"
component_wit="$tmp_dir/service.component.wit"
minimal_core_wasm="$tmp_dir/service-minimal.wasm"
minimal_component_wasm="$tmp_dir/service-minimal.component.wasm"
minimal_component_wit="$tmp_dir/service-minimal.component.wit"
generated_wit_dir="$tmp_dir/service-generated.wit-package"
generated_core_wat="$tmp_dir/service-generated.wat"
generated_core_wasm="$tmp_dir/service-generated.wasm"
generated_component_wasm="$tmp_dir/service-generated.component.wasm"

wasm-tools component embed "$wit_dir" --world service --dummy-names legacy \
  --async-callback -t -o "$core_wat"

grep -Fq '"wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]response"' "$core_wat"
grep -Eq '\(type \([^)]*\) \(func \(param i32 i32 i32 i64 i32 i32 i32 i32\)\)\)' "$core_wat"
grep -Fq '"[task-return]handle"' "$core_wat"

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component new "$core_wasm" -o "$component_wasm"
wasm-tools validate "$component_wasm"
wasm-tools component wit "$component_wasm" > "$component_wit"

grep -Fq 'import wasi:http/types@0.3.0-rc-2025-09-16;' "$component_wit"
grep -Fq 'import wasi:http/client@0.3.0-rc-2025-09-16;' "$component_wit"
grep -Fq 'export wasi:http/handler@0.3.0-rc-2025-09-16;' "$component_wit"

wasm-tools parse "$minimal_core_wat" -o "$minimal_core_wasm"
wasm-tools component embed "$wit_dir" "$minimal_core_wasm" --world service \
  -o "$tmp_dir/service-minimal.embedded.wasm"
wasm-tools component new "$tmp_dir/service-minimal.embedded.wasm" -o "$minimal_component_wasm"
wasm-tools validate "$minimal_component_wasm"
wasm-tools component wit "$minimal_component_wasm" > "$minimal_component_wit"

grep -Fq 'import wasi:http/types@0.3.0-rc-2025-09-16;' "$minimal_component_wit"
grep -Fq 'import wasi:http/client@0.3.0-rc-2025-09-16;' "$minimal_component_wit"
grep -Fq 'export wasi:http/handler@0.3.0-rc-2025-09-16;' "$minimal_component_wit"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$http_service_source" \
  --p3-async-component --p3-wit-package-output "$generated_wit_dir" -o "$generated_core_wat"
wasm-tools parse "$generated_core_wat" -o "$generated_core_wasm"
wasm-tools component embed "$generated_wit_dir" "$generated_core_wasm" --world service \
  -o "$tmp_dir/service-generated.embedded.wasm"
wasm-tools component new "$tmp_dir/service-generated.embedded.wasm" -o "$generated_component_wasm"
wasm-tools validate "$generated_component_wasm"

output=$(cd "$runner_dir" && \
  CC="$runner_dir/zig-cc.sh" \
  CXX="$runner_dir/zig-cc.sh" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh" \
  cargo run --quiet --bin do-p3-http-service-host-runner -- "$generated_component_wasm")
case "$output" in
  *"Rust P3 HTTP service adapter passed"*) ;;
  *)
    printf 'missing HTTP service runtime verification marker\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

printf 'WASI HTTP service async ABI surface verified\n'
