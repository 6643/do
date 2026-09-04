#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
template="$repo_root/examples/p3-runtime/wit/async-template.wit"
output=$("$toolchain_bin" embed-component-template "$template" probe)

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
