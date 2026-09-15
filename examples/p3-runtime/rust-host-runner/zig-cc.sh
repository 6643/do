#!/usr/bin/env bash
set -euo pipefail

zig_cache_root="${DO_ZIG_CC_CACHE_ROOT:-${TMPDIR:-/tmp}/do-rust-zig-cc-cache}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$zig_cache_root/local}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$zig_cache_root/global}"
mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"

args=()
for arg in "$@"; do
  case "$arg" in
    --target=x86_64-unknown-linux-gnu) ;;
    *) args+=("$arg") ;;
  esac
done

exec "${ZIG_BIN:-zig}" cc "${args[@]}"
