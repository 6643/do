#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/resource-probe.wit"

output=$(wasm-tools component wit "$wit")
case "$output" in
  *"resource ticket"*) ;;
  *)
    printf 'resource probe WIT did not retain ticket resource\n' >&2
    exit 1
    ;;
esac
