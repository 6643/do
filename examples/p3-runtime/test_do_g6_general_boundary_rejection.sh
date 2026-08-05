#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-general-boundary.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

expect_unsupported() {
  local fixture="$1"
  local label="$2"
  local stderr_file="$tmp_dir/${label}.stderr"

  if DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
    --p3-async-component "$repo_root/examples/p3-runtime/$fixture" \
    -o "$tmp_dir/${label}.wat" >"$tmp_dir/${label}.stdout" 2>"$stderr_file"; then
    echo "$label unexpectedly lowered" >&2
    exit 1
  fi
  grep -Fq 'UnsupportedP3AsyncComponent' "$stderr_file"
}

expect_unsupported stream-probe-guest-producer-sixth-forwarding.do sixth-forwarding
expect_unsupported stream-probe-guest-producer-arbitrary.do arbitrary-producer
printf 'G6.2 general producer boundary rejection passed sixth-forwarding/arbitrary-producer\n'
