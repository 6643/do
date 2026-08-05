#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
pinned_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16"
probe_fragment="$repo_root/examples/p3-runtime/wit/http-payload-error-probe.wit"
do_bin="$repo_root/bin/do"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-http-payload-error-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
mkdir -p "$wit_dir"
cp -R "$pinned_wit/deps" "$wit_dir/"
cp "$pinned_wit/deps.toml" "$wit_dir/"
cp "$pinned_wit/deps.lock" "$wit_dir/"
cp "$pinned_wit"/*.wit "$wit_dir/"
cat "$probe_fragment" >>"$wit_dir/worlds.wit"

for candidate in canonical host-lowered; do
  core_wat="$repo_root/examples/p3-runtime/http-payload-error-$candidate.wat"
  core_wasm="$tmp_dir/$candidate.wasm"
  embedded="$tmp_dir/$candidate.embedded.wasm"
  component="$tmp_dir/$candidate.component.wasm"
  component_wit="$tmp_dir/$candidate.component.wit"

  wasm-tools parse "$core_wat" -o "$core_wasm"
  wasm-tools component embed "$wit_dir" "$core_wasm" \
    --world http-payload-error-probe -o "$embedded"
  wasm-tools component new "$embedded" -o "$component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$component"
  wasm-tools component wit "$component" >"$component_wit"

  grep -Fq 'import wasi:http/types@0.3.0-rc-2025-09-16;' "$component_wit"
  grep -Fq 'import wasi:http/client@0.3.0-rc-2025-09-16;' "$component_wit"
  grep -Fq 'export wasi:http/probe@0.3.0-rc-2025-09-16;' "$component_wit"
done

dns_error_core_wat="$repo_root/examples/p3-runtime/http-payload-error-dns-error-canonical.wat"
dns_error_core_wasm="$tmp_dir/dns-error-canonical.wasm"
dns_error_embedded="$tmp_dir/dns-error-canonical.embedded.wasm"
dns_error_component="$tmp_dir/dns-error-canonical.component.wasm"
dns_error_component_wit="$tmp_dir/dns-error-canonical.component.wit"
wasm-tools parse "$dns_error_core_wat" -o "$dns_error_core_wasm"
wasm-tools component embed "$wit_dir" "$dns_error_core_wasm" \
  --world http-payload-error-probe -o "$dns_error_embedded"
wasm-tools component new "$dns_error_embedded" -o "$dns_error_component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$dns_error_component"
wasm-tools component wit "$dns_error_component" >"$dns_error_component_wit"
grep -Fq 'export wasi:http/probe@0.3.0-rc-2025-09-16;' "$dns_error_component_wit"

if [[ ${1:-} == --assemble-only ]]; then
  printf 'WASI HTTP payload error ABI assembly passed\n'
  exit 0
fi

runner_bin="$runner_dir/target/debug/do-p3-http-payload-error-abi-host-runner"
if [[ ! -x "$runner_bin" ]]; then
  printf 'runner-not-built\n' >&2
  exit 3
fi

runtime_wit_dir="$tmp_dir/runtime-wit-package"
runtime_base_wat="$tmp_dir/runtime-base.wat"
DO_LIB_ROOT="$repo_root/lib" "$do_bin" build \
  "$repo_root/examples/p3-runtime/http-service-empty-request.do" \
  --p3-async-component --p3-wit-package-output "$runtime_wit_dir" \
  -o "$runtime_base_wat" >/dev/null
cat "$probe_fragment" >>"$runtime_wit_dir/worlds.wit"

runtime_canonical_tail='        local.get $frame-ref
        struct.get $async-frame $slot-result-ptr
        i32.const 16
        i32.add
        i32.load
        local.get $frame-ref
        struct.get $async-frame $slot-result-ptr
        i32.const 20
        i32.add
        i32.load
        i64.extend_i32_u
        local.get $frame-ref
        struct.get $async-frame $slot-result-ptr
        i32.const 24
        i32.add
        i32.load
        i32.const 0
        i32.const 0
        i32.const 0'

for candidate in control canonical host-lowered dns-error; do
  runtime_wat="$tmp_dir/runtime-$candidate.wat"
  runtime_wasm="$tmp_dir/runtime-$candidate.wasm"
  runtime_embedded="$tmp_dir/runtime-$candidate.embedded.wasm"
  runtime_component="$tmp_dir/runtime-$candidate.component.wasm"
  cp "$runtime_base_wat" "$runtime_wat"
  if [[ "$candidate" == canonical ]]; then
    RUNTIME_CANONICAL_TAIL="$runtime_canonical_tail" perl -0pi -e \
      's/        i32\.const 0\n        i64\.const 0\n        i32\.const 0\n        i32\.const 0\n        i32\.const 0\n        i32\.const 0/$ENV{RUNTIME_CANONICAL_TAIL}/' "$runtime_wat"
  fi
  wasm-tools parse "$runtime_wat" -o "$runtime_wasm"
  wasm-tools component embed "$runtime_wit_dir" "$runtime_wasm" \
    --world http-payload-error-probe -o "$runtime_embedded"
  wasm-tools component new "$runtime_embedded" -o "$runtime_component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$runtime_component"
done

run_component_case() {
  local component_path=$1
  local candidate=$2
  local case_name=$3
  local expected_status=$4
  local expected_observation=$5
  local output
  output=$(cd "$runner_dir" && \
    CC="$PWD/zig-cc.sh" CXX="$PWD/zig-cc.sh" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
    cargo run --quiet --bin do-p3-http-payload-error-abi-host-runner -- \
      "$component_path" "$candidate" "$case_name")
  if ! grep -Fq \
    "payload-gate=$expected_status candidate=$candidate case=$case_name observation=$expected_observation" \
    <<<"$output"; then
    printf 'unexpected payload ABI observation for %s/%s:\n%s\n' \
      "$candidate" "$case_name" "$output" >&2
    exit 1
  fi
  if ! grep -Fq 'table-empty=true' <<<"$output"; then
    printf 'payload ABI runner leaked a resource for %s/%s:\n%s\n' \
      "$candidate" "$case_name" "$output" >&2
    exit 1
  fi
  case "$output" in
    *"unknown handle index"*)
      printf 'payload ABI runner exposed an invalid resource handle for %s/%s:\n%s\n' \
        "$candidate" "$case_name" "$output" >&2
      exit 1
      ;;
  esac
  printf '%s\n' "$output"
}

run_case() {
  local candidate=$1
  shift
  run_component_case "$tmp_dir/runtime-$candidate.component.wasm" "$candidate" "$@"
}

run_static_case() {
  local candidate=$1
  shift
  run_component_case "$tmp_dir/$candidate.component.wasm" "$candidate" "$@"
}

# The hand-authored candidates are the ABI control: canonical preserves the
# optional payload, while host-lowered intentionally demonstrates the rejected
# Some -> None mapping. The compiler-generated runtime candidates below are a
# separate gate and must not inherit that rejected fixture label.
run_static_case canonical internal-error-some green 'InternalError(Some("x"))'
run_static_case host-lowered internal-error-some blocked 'InternalError(None)'

run_case control dns-timeout green DNS-timeout
run_case control internal-error-none green 'InternalError(None)'
run_case canonical internal-error-none green 'InternalError(None)'
run_case canonical internal-error-some green 'InternalError(Some("x"))'
run_case dns-error dns-error green 'DnsError(rcode=Some("EAI"),info-code=Some(7))'
run_component_case "$tmp_dir/canonical.component.wasm" direct internal-error-some green 'InternalError(Some("x"))'
run_component_case "$tmp_dir/dns-error-canonical.component.wasm" direct-dns-error dns-error green \
  'DnsError(rcode=Some("EAI"),info-code=Some(7))'
