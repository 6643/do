#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
fixtures=(
  "$repo_root/src/build/test/compile_err/762_g6_2_mixed_owned_record_producer_missing_code.do"
  "$repo_root/src/build/test/compile_err/763_g6_2_mixed_owned_record_producer_reordered_fields.do"
  "$repo_root/src/build/test/compile_err/764_g6_2_mixed_owned_record_producer_borrowed_ticket.do"
  "$repo_root/src/build/test/compile_err/765_g6_2_mixed_owned_record_producer_wrong_marker.do"
  "$repo_root/src/build/test/compile_err/766_g6_2_mixed_owned_record_producer_wrong_source.do"
  "$repo_root/src/build/test/compile_err/767_g6_2_mixed_owned_record_producer_wrong_body.do"
  "$repo_root/src/build/test/compile_err/768_g6_2_mixed_owned_record_producer_nested_payload.do"
  "$repo_root/src/build/test/compile_err/769_g6_2_mixed_owned_record_producer_wrong_capacity.do"
  "$repo_root/src/build/test/compile_err/770_g6_2_mixed_owned_record_producer_extra_binding.do"
)

tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-mixed-producer-negative.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

test -x "$do_bin"
for fixture in "${fixtures[@]}"; do
  expected="${fixture%.do}.expect"
  name=$(basename "$fixture" .do)
  stderr="$tmp_dir/$name.stderr"
  stdout="$tmp_dir/$name.stdout"
  wat="$tmp_dir/$name.wat"
  test -f "$fixture"
  test -f "$expected"

  build_args=()
  while IFS= read -r expected_line || [[ -n "$expected_line" ]]; do
    case "$expected_line" in
      '# build-arg: '*) build_args+=("${expected_line#\# build-arg: }");;
    esac
  done <"$expected"

  if DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" "${build_args[@]}" -o "$wat" \
    >"$stdout" 2>"$stderr"; then
    printf 'mixed producer negative fixture unexpectedly compiled: %s\n' "$fixture" >&2
    exit 1
  fi
  while IFS= read -r expected_line || [[ -n "$expected_line" ]]; do
    [[ -z "$expected_line" || "$expected_line" == \#* ]] && continue
    grep -Fq "$expected_line" "$stderr" || {
      printf 'missing expected diagnostic %s for %s\n' "$expected_line" "$fixture" >&2
      cat "$stderr" >&2
      exit 1
    }
  done <"$expected"
  if [[ -e "$wat" ]]; then
    printf 'mixed producer negative fixture emitted WAT: %s\n' "$fixture" >&2
    exit 1
  fi
done

printf 'G6.2 mixed owned-record producer negative gate passed fixtures=%d diagnostics=expected emission=none\n' "${#fixtures[@]}"
