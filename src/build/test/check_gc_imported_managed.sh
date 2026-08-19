#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
zig_bin=${ZIG_BIN:-zig}

"$zig_bin" test "$repo_root/src/build/codegen_pipeline.zig" \
  --test-filter 'GC route lowers a reachable imported managed'

printf 'GC imported managed sync route passed\n'
