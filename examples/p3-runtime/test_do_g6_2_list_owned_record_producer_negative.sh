#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
fixtures=()
for number in {772..781}; do
  fixtures+=("$repo_root/src/build/test/compile_err/${number}_g6_2_list_owned_record_producer_")
done

tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-list-owned-record-producer-negative.XXXXXX")
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
    printf 'list-owned-record negative fixture unexpectedly compiled: %s\n' "$fixture" >&2
    exit 1
  fi
  grep -Fq 'UnknownP3AsyncHostDescriptor' "$stderr"
  test ! -e "$wat"
done

printf 'G6.2 list-owned-record producer negative RED gate passed fixtures=%d emission=none\n' "${#fixtures[@]}"
