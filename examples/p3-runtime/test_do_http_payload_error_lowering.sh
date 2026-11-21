#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
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

rg -Fq ';; [error-variant:internal-error]' "$core_wat"
rg -Fq 'i32.const 16' "$core_wat"
rg -Fq 'i32.const 20' "$core_wat"
rg -Fq 'i32.const 24' "$core_wat"
if rg -U -q 'i32\.const 38\n\s*i32\.eq\n\s*if unreachable end' "$core_wat"; then
  printf 'generated InternalError lowering still traps\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_dir" "$core_wasm" service -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

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
    rg -Fq "compiler-gate=green delivery=$delivery case=$case_name observation=$expected" <<<"$output"
    rg -Fq 'request-consumed=1' <<<"$output"
    rg -Fq 'response-created=0' <<<"$output"
    rg -Fq 'table-empty=true' <<<"$output"
  done
fi

if [[ "$delivery_mode" == pending || "$delivery_mode" == all ]]; then
  output=$(cd "$runner_dir" && \
    CC="$PWD/zig-cc.sh" \
    CXX="$PWD/zig-cc.sh" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
    timeout 30s cargo run --quiet --bin do-p3-http-payload-error-abi-host-runner -- \
      "$component" compiler-service dns-error pending)
  rg -Fq 'compiler-gate=green delivery=pending case=dns-error observation=DnsError(rcode=Some("EAI"),info-code=Some(7))' <<<"$output"
  rg -Fq 'request-consumed=1' <<<"$output"
  rg -Fq 'response-created=0' <<<"$output"
  rg -Fq 'table-empty=true' <<<"$output"
fi

if [[ "$delivery_mode" == ready || "$delivery_mode" == all ]]; then
  output=$(cd "$runner_dir" && \
    CC="$PWD/zig-cc.sh" \
    CXX="$PWD/zig-cc.sh" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
    timeout 30s cargo run --quiet --bin do-p3-http-payload-error-abi-host-runner -- \
      "$component" compiler-service dns-error ready)
  rg -Fq 'compiler-gate=green delivery=ready case=dns-error observation=DnsError(rcode=Some("EAI"),info-code=Some(7))' <<<"$output"
  rg -Fq 'request-consumed=1' <<<"$output"
  rg -Fq 'response-created=0' <<<"$output"
  rg -Fq 'table-empty=true' <<<"$output"
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
    rg -Fq "compiler-gate=green delivery=$delivery case=$case_name observation=$expected" <<<"$output"
    rg -Fq 'request-consumed=1' <<<"$output"
    rg -Fq 'response-created=0' <<<"$output"
    rg -Fq 'table-empty=true' <<<"$output"
  done
fi

if [[ "$delivery_mode" == all ]]; then
  for delivery in pending ready; do
    for case_name in \
      tls-alert-received \
      http-request-body-size \
      http-request-header-section-size \
      http-request-header-size \
      http-request-trailer-section-size \
      http-request-trailer-size \
      http-response-header-section-size \
      http-response-header-size \
      http-response-body-size \
      http-response-trailer-section-size \
      http-response-trailer-size \
      http-response-transfer-coding \
      http-response-content-coding; do
      case "$case_name" in
        tls-alert-received)
          expected='TlsAlertReceived(alert-id=Some(42),alert-message=Some("alert"))'
          ;;
        http-request-body-size)
          expected='HTTP-request-body-size(Some(1234))'
          ;;
        http-request-header-section-size)
          expected='HTTP-request-header-section-size(Some(123))'
          ;;
        http-request-header-size)
          expected='HTTP-request-header-size(field-name=Some("content-type"),field-size=Some(42))'
          ;;
        http-request-trailer-section-size)
          expected='HTTP-request-trailer-section-size(Some(123))'
          ;;
        http-request-trailer-size)
          expected='HTTP-request-trailer-size(field-name=Some("content-type"),field-size=Some(42))'
          ;;
        http-response-header-section-size)
          expected='HTTP-response-header-section-size(Some(123))'
          ;;
        http-response-header-size)
          expected='HTTP-response-header-size(field-name=Some("content-type"),field-size=Some(42))'
          ;;
        http-response-body-size)
          expected='HTTP-response-body-size(Some(1234))'
          ;;
        http-response-trailer-section-size)
          expected='HTTP-response-trailer-section-size(Some(123))'
          ;;
        http-response-trailer-size)
          expected='HTTP-response-trailer-size(field-name=Some("content-type"),field-size=Some(42))'
          ;;
        http-response-transfer-coding)
          expected='HTTP-response-transfer-coding(Some("chunked"))'
          ;;
        http-response-content-coding)
          expected='HTTP-response-content-coding(Some("gzip"))'
          ;;
      esac
      output=$(cd "$runner_dir" && \
        CC="$PWD/zig-cc.sh" \
        CXX="$PWD/zig-cc.sh" \
        CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
        timeout 30s cargo run --quiet --bin do-p3-http-payload-error-abi-host-runner -- \
          "$component" compiler-service "$case_name" "$delivery")
      rg -Fq "compiler-gate=green delivery=$delivery case=$case_name observation=$expected" <<<"$output"
      rg -Fq 'request-consumed=1' <<<"$output"
      rg -Fq 'response-created=0' <<<"$output"
      rg -Fq 'table-empty=true' <<<"$output"
    done
  done
fi

printf 'WASI HTTP payload error compiler lowering passed delivery=%s\n' "$delivery_mode"
