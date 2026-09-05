#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
do_bin="${DO_BIN:-$repo_root/bin/do}"
fixture="$repo_root/examples/p3-runtime/two-await-component.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-root-liveness.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

test -x "$do_bin"
test -f "$fixture"

wat="$tmp_dir/two-await.wat"
"$do_bin" build "$fixture" --p3-wait-for-component -o "$wat"

for marker in \
  '[gc-root][suspend_frame]' \
  '[gc-root][resume_frame]' \
  '[gc-root][cancel_frame]' \
  '[gc-root][terminal]' \
  '[resource-drop-exactly-once]'; do
  grep -Fq "$marker" "$wat"
done

if grep -Fq '__arc_' "$wat"; then
  printf 'normal GC frame emitted ARC marker\n' >&2
  exit 1
fi

printf 'gc root liveness gate passed\n'
