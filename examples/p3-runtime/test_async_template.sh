#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
template="$repo_root/examples/p3-runtime/wit/async-template.wit"
output=$(wasm-tools component embed "$template" --world probe --dummy-names legacy --async-callback -t)

for expected in \
  '"[async-lower]wait-for"' \
  '"[async-lift]run"' \
  '"[callback][async-lift]run"' \
  '"[task-return]run"'; do
  case "$output" in
    *"$expected"*) ;;
    *)
      printf 'missing legacy async ABI symbol: %s\n' "$expected" >&2
      exit 1
      ;;
  esac
done

printf 'legacy async callback template verified\n'
