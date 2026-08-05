#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$repo_root/examples/p3-runtime/test_rust_http_payload_cancellation.sh" "$@"
