#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
fixture="$repo_root/examples/p3-runtime/http-service.do"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
delivery_mode="${1:-pending}"
case "$delivery_mode" in
  pending|ready|all) ;;
  *)
    printf 'usage: %s [pending|ready|all]\n' "$0" >&2
    exit 2
    ;;
esac
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-http-payload-error-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/http-service.wat"
core_wasm="$tmp_dir/http-service.wasm"
embedded="$tmp_dir/http-service.embedded.wasm"
component="$tmp_dir/http-service.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

grep -Fq ';; [error-variant:internal-error]' "$core_wat"
grep -Fq 'i32.const 16' "$core_wat"
grep -Fq 'i32.const 20' "$core_wat"
grep -Fq 'i32.const 24' "$core_wat"
if rg -U -q 'i32\.const 38\n\s*i32\.eq\n\s*if unreachable end' "$core_wat"; then
  printf 'generated InternalError lowering still traps\n' >&2
  exit 1
fi

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit_dir" "$core_wasm" --world service -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

if [[ "$delivery_mode" == pending || "$delivery_mode" == all ]]; then
  delivery=pending
  for case_name in internal-error-none internal-error-some; do
    output=$(cd "$runner_dir" && \
      CC="$PWD/zig-cc.sh" \
      CXX="$PWD/zig-cc.sh" \
      CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
      timeout 30s cargo run --quiet --bin do-p3-http-payload-error-abi-host-runner -- \
        "$component" compiler-service "$case_name" "$delivery")
    expected='InternalError(None)'
    if [[ "$case_name" == internal-error-some ]]; then
      expected='InternalError(Some("x"))'
    fi
    grep -Fq "compiler-gate=green delivery=$delivery case=$case_name observation=$expected" <<<"$output"
    grep -Fq 'request-consumed=1' <<<"$output"
    grep -Fq 'response-created=0' <<<"$output"
    grep -Fq 'table-empty=true' <<<"$output"
  done
fi

if [[ "$delivery_mode" == pending || "$delivery_mode" == all ]]; then
  output=$(cd "$runner_dir" && \
    CC="$PWD/zig-cc.sh" \
    CXX="$PWD/zig-cc.sh" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
    timeout 30s cargo run --quiet --bin do-p3-http-payload-error-abi-host-runner -- \
      "$component" compiler-service dns-error pending)
  grep -Fq 'compiler-gate=green delivery=pending case=dns-error observation=DnsError(rcode=Some("EAI"),info-code=Some(7))' <<<"$output"
  grep -Fq 'request-consumed=1' <<<"$output"
  grep -Fq 'response-created=0' <<<"$output"
  grep -Fq 'table-empty=true' <<<"$output"
fi

if [[ "$delivery_mode" == ready || "$delivery_mode" == all ]]; then
  delivery=ready
  for case_name in internal-error-none internal-error-some; do
    output=$(cd "$runner_dir" && \
      CC="$PWD/zig-cc.sh" \
      CXX="$PWD/zig-cc.sh" \
      CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
      timeout 30s cargo run --quiet --bin do-p3-http-payload-error-abi-host-runner -- \
        "$component" compiler-service "$case_name" "$delivery")
    expected='InternalError(None)'
    if [[ "$case_name" == internal-error-some ]]; then
      expected='InternalError(Some("x"))'
    fi
    grep -Fq "compiler-gate=green delivery=$delivery case=$case_name observation=$expected" <<<"$output"
    grep -Fq 'request-consumed=1' <<<"$output"
    grep -Fq 'response-created=0' <<<"$output"
    grep -Fq 'table-empty=true' <<<"$output"
  done
fi

printf 'WASI HTTP payload error compiler lowering passed delivery=%s\n' "$delivery_mode"
