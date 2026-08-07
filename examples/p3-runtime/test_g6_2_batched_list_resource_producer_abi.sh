#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
wat="$repo_root/examples/p3-runtime/g6-2-batched-list-resource-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-batched-list-resource-producer.wit"
runner="$runner_dir/src/bin/g6_2_batched_list_resource_producer_abi.rs"

for path in "$wat" "$runner"; do
  if [[ ! -f "$path" ]]; then
    printf 'missing probe artifact: %s\n' "$path" >&2
    exit 1
  fi
done

if [[ ! -f "$wit" ]]; then
  printf 'missing WIT source: %s\n' "$wit" >&2
  exit 1
fi

printf 'probe artifacts are present; continue with pinned assembly and runtime gates\n'
