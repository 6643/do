#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
"$repo_root/examples/p3-runtime/verify_p3_wit.sh"
wasm-tools component wit "$repo_root/examples/p3-runtime/probe.wit" >/dev/null
output=$("$repo_root/examples/p3-runtime/build_and_run.sh")

"$repo_root/examples/p3-runtime/test_c_api_host_drive_queue.sh"

case "$output" in
  *"generic component async probe passed"*) ;;
  *)
    printf 'missing generic component async success marker\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"generic component async GC probe passed"*) ;;
  *)
    printf 'missing generic component async GC success marker\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"P3 wait-for component ABI probe: blocked"*) ;;
  *)
    printf 'missing P3 wait-for component ABI blocker marker\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

"$repo_root/examples/p3-runtime/test_rust_cancel_wait_for.sh"
