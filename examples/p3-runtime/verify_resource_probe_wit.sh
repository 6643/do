#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
wit="$repo_root/examples/p3-runtime/wit/resource-probe.wit"

test -x "$toolchain_bin"
output=$("$toolchain_bin" component-wit "$wit")
case "$output" in
  *"resource ticket"*) ;;
  *)
    printf 'resource probe WIT did not retain ticket resource\n' >&2
    exit 1
    ;;
esac
