#!/usr/bin/env bash
set -euo pipefail

# Compatibility entrypoint. Keep existing fixtures on the pinned v1 path.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$script_dir/assemble_wasmtime_p3_legacy.sh" "$@"
