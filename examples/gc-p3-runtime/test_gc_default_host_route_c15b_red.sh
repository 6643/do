#!/usr/bin/env bash
set -euo pipefail

# Historical entrypoint retained for local scripts. C15-B is now expected
# green after the manifest-backed default route is admitted.
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$repo_root/examples/gc-p3-runtime/test_gc_default_host_route_c15b.sh" "$@"
