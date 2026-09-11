#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
fixtures=()
for number in {783..795}; do
  fixtures+=("$repo_root/src/build/test/compile_err/${number}_g6_2_two_list_owned_record_producer_")
done

tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-two-list-owned-record-producer-negative.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

test -x "$do_bin"
for prefix in "${fixtures[@]}"; do
  fixture=$(printf '%s\n' "$prefix"*.do)
  expected="${fixture%.do}.expect"
  name=$(basename "$fixture" .do)
  stderr="$tmp_dir/$name.stderr"
  stdout="$tmp_dir/$name.stdout"
  wat="$tmp_dir/$name.wat"
  wit="$tmp_dir/$name.wit"
  test -f "$fixture"
  test -f "$expected"

  build_args=()
  while IFS= read -r expected_line || [[ -n "$expected_line" ]]; do
    case "$expected_line" in
      '# build-arg: '*) build_args+=("${expected_line#\# build-arg: }");;
    esac
  done <"$expected"

  if DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" "${build_args[@]}" \
    --p3-wit-output "$wit" -o "$wat" >"$stdout" 2>"$stderr"; then
    printf 'two-list owned-record negative fixture unexpectedly compiled: %s\n' "$fixture" >&2
    exit 1
  fi
  while IFS= read -r expected_line || [[ -n "$expected_line" ]]; do
    [[ -z "$expected_line" || "$expected_line" == \#* ]] && continue
    grep -Fq "$expected_line" "$stderr" || {
      printf 'missing expected diagnostic %s for %s\n' "$expected_line" "$fixture" >&2
      exit 1
    }
  done <"$expected"
  if [[ -e "$wat" || -e "$wit" ]]; then
    printf 'two-list owned-record negative fixture emitted output despite rejection: %s\n' "$fixture" >&2
    exit 1
  fi
  if grep -Eq 'record_resource_list_owned_record_stream_producer|do:g6-2-owned-record-list-producer@0\.1\.0|producer-record-values-pointer-offset' "$stdout" "$stderr"; then
    printf 'two-list owned-record negative fixture fell back to the old one-list route: %s\n' "$fixture" >&2
    exit 1
  fi
done

printf 'G6.2 two-list owned-record producer negative gate passed fixtures=%d diagnostics=expect emission=none fallback=none\n' "${#fixtures[@]}"
