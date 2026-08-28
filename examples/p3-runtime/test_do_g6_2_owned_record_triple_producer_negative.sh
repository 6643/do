#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
fixtures=(
  "$repo_root/src/build/test/compile_err/712_g6_2_triple_wrong_arity.do"
  "$repo_root/src/build/test/compile_err/713_g6_2_triple_seed_order.do"
  "$repo_root/src/build/test/compile_err/714_g6_2_triple_non_u32_seed.do"
  "$repo_root/src/build/test/compile_err/715_g6_2_triple_renamed_source.do"
  "$repo_root/src/build/test/compile_err/716_g6_2_triple_renamed_sink.do"
  "$repo_root/src/build/test/compile_err/717_g6_2_triple_borrowed_field.do"
  "$repo_root/src/build/test/compile_err/718_g6_2_triple_extra_field.do"
  "$repo_root/src/build/test/compile_err/719_g6_2_triple_reordered_field.do"
  "$repo_root/src/build/test/compile_err/720_g6_2_triple_wrong_marker.do"
  "$repo_root/src/build/test/compile_err/721_g6_2_triple_wrong_result.do"
  "$repo_root/src/build/test/compile_err/722_g6_2_triple_async_intrinsic.do"
  "$repo_root/src/build/test/compile_err/723_g6_2_triple_unregistered_descriptor.do"
  "$repo_root/src/build/test/compile_err/724_g6_2_triple_old_descriptor.do"
)
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-triple-producer-negative.XXXXXX")
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
    printf 'triple producer negative fixture unexpectedly compiled: %s\n' "$fixture" >&2
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
    printf 'triple producer negative fixture emitted WAT despite rejection: %s\n' "$fixture" >&2
    exit 1
  fi
done

printf 'G6.2 owned-record triple producer negative gate passed fixtures=%d diagnostics=expect emission=none\n' "${#fixtures[@]}"
