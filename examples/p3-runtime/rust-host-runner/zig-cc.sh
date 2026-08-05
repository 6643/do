#!/usr/bin/env bash
set -euo pipefail

args=()
for arg in "$@"; do
  case "$arg" in
    --target=x86_64-unknown-linux-gnu) ;;
    *) args+=("$arg") ;;
  esac
done

exec "${ZIG_BIN:-zig}" cc "${args[@]}"
