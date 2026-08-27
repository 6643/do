#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
fixtures=(
  "$repo_root/src/build/test/compile_err/700_g6_2_owned_record_pair_producer_extra_field.do"
  "$repo_root/src/build/test/compile_err/701_g6_2_owned_record_pair_producer_renamed_binding.do"
)
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-pair-producer-negative.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

stderr="$tmp_dir/stderr"
wat="$tmp_dir/rejected.wat"

test -x "$do_bin"
for fixture in "${fixtures[@]}"; do
  expected="${fixture%.do}.expect"
  test -f "$fixture"
  test -f "$expected"
  rm -f "$wat"

  if DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" --p3-async-component -o "$wat" \
    >"$tmp_dir/stdout" 2>"$stderr"; then
    printf 'pair producer negative fixture unexpectedly compiled: %s\n' "$fixture" >&2
    exit 1
  fi
  while IFS= read -r expected_line; do
    [[ -z "$expected_line" || "$expected_line" == \#* ]] && continue
    grep -Fq "$expected_line" "$stderr" || {
      printf 'missing expected diagnostic %s for %s\n' "$expected_line" "$fixture" >&2
      exit 1
    }
  done <"$expected"
  if [[ -e "$wat" ]]; then
    printf 'pair producer negative fixture emitted WAT despite rejection: %s\n' "$fixture" >&2
    exit 1
  fi
done

printf 'G6.2 owned-record pair producer negative gate passed fixtures=%d diagnostics=expect emission=none\n' "${#fixtures[@]}"
