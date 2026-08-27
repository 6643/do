#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
fixtures=(
  "$repo_root/src/build/test/compile_err/702_g6_2_parameterized_pair_wrong_arity.do"
  "$repo_root/src/build/test/compile_err/703_g6_2_parameterized_pair_seed_order.do"
  "$repo_root/src/build/test/compile_err/704_g6_2_parameterized_pair_non_u32_seed.do"
  "$repo_root/src/build/test/compile_err/705_g6_2_parameterized_pair_renamed_binding.do"
  "$repo_root/src/build/test/compile_err/706_g6_2_parameterized_pair_borrowed_field.do"
  "$repo_root/src/build/test/compile_err/707_g6_2_parameterized_pair_extra_field.do"
  "$repo_root/src/build/test/compile_err/708_g6_2_parameterized_pair_wrong_binding.do"
  "$repo_root/src/build/test/compile_err/709_g6_2_parameterized_pair_async_intrinsic.do"
  "$repo_root/src/build/test/compile_err/710_g6_2_parameterized_pair_old_descriptor.do"
  "$repo_root/src/build/test/compile_err/711_g6_2_parameterized_pair_unregistered_descriptor.do"
)
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-pair-parameterized-negative.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

test -x "$do_bin"
stderr="$tmp_dir/stderr"
wat="$tmp_dir/rejected.wat"
for fixture in "${fixtures[@]}"; do
  expected="${fixture%.do}.expect"
  test -f "$fixture"
  test -f "$expected"
  rm -f "$wat"
  if DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
      --p3-async-component -o "$wat" >"$tmp_dir/stdout" 2>"$stderr"; then
    printf 'parameterized pair negative fixture unexpectedly compiled: %s\n' "$fixture" >&2
    exit 1
  fi
  while IFS= read -r expected_line; do
    [[ -z "$expected_line" || "$expected_line" == \#* ]] && continue
    grep -Fq "$expected_line" "$stderr" || {
      printf 'missing expected diagnostic %s for %s\n' "$expected_line" "$fixture" >&2
      cat "$stderr" >&2
      exit 1
    }
  done <"$expected"
  if [[ -e "$wat" ]]; then
    printf 'parameterized pair negative fixture emitted WAT: %s\n' "$fixture" >&2
    exit 1
  fi
done

printf 'G6.2 parameterized owned-record pair negative gate passed fixtures=%d diagnostics=expect emission=none\n' "${#fixtures[@]}"
