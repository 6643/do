#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
fixtures=(
  "$repo_root/src/build/test/compile_err/725_g6_2_nested_unregistered_descriptor.do"
  "$repo_root/src/build/test/compile_err/726_g6_2_nested_wrong_stream_element.do"
  "$repo_root/src/build/test/compile_err/727_g6_2_nested_wrong_sink_marker.do"
  "$repo_root/src/build/test/compile_err/728_g6_2_nested_renamed_source.do"
  "$repo_root/src/build/test/compile_err/729_g6_2_nested_renamed_sink.do"
  "$repo_root/src/build/test/compile_err/730_g6_2_nested_direct_leaf.do"
  "$repo_root/src/build/test/compile_err/731_g6_2_nested_borrowed_leaf.do"
  "$repo_root/src/build/test/compile_err/732_g6_2_nested_non_resource_leaf.do"
  "$repo_root/src/build/test/compile_err/733_g6_2_nested_extra_field.do"
  "$repo_root/src/build/test/compile_err/734_g6_2_nested_third_record.do"
  "$repo_root/src/build/test/compile_err/735_g6_2_nested_list_field.do"
  "$repo_root/src/build/test/compile_err/736_g6_2_nested_variant_field.do"
  "$repo_root/src/build/test/compile_err/737_g6_2_nested_wrong_source_module.do"
  "$repo_root/src/build/test/compile_err/738_g6_2_nested_wrong_source_arity.do"
  "$repo_root/src/build/test/compile_err/739_g6_2_nested_wrong_mode_type.do"
  "$repo_root/src/build/test/compile_err/740_g6_2_nested_wrong_producer_body.do"
  "$repo_root/src/build/test/compile_err/741_g6_2_nested_extra_host_binding.do"
  "$repo_root/src/build/test/compile_err/742_g6_2_nested_wrong_result.do"
  "$repo_root/src/build/test/compile_err/743_g6_2_nested_async_intrinsic.do"
  "$repo_root/src/build/test/compile_err/744_g6_2_nested_wrong_source_marker.do"
  "$repo_root/src/build/test/compile_err/745_g6_2_nested_wrong_record_field_name.do"
)

tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-nested-negative.XXXXXX")
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
    printf 'nested producer negative fixture unexpectedly compiled: %s\n' "$fixture" >&2
    exit 1
  fi
  while IFS= read -r expected_line || [[ -n "$expected_line" ]]; do
    [[ -z "$expected_line" || "$expected_line" == \#* ]] && continue
    grep -Fq "$expected_line" "$stderr" || {
      printf 'missing expected diagnostic %s for %s\n' "$expected_line" "$fixture" >&2
      exit 1
    }
  done <"$expected"
  if [[ -e "$wat" ]]; then
    printf 'nested producer negative fixture emitted WAT: %s\n' "$fixture" >&2
    exit 1
  fi
done

(cd "$repo_root/src" && \
  TMPDIR="${TMPDIR:-../.tmp/do-tmp}" \
  ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-../.tmp/zig-cache}" \
  ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-../.tmp/zig-gcache}" \
  zig test build/p3_async_manifest.zig >/dev/null)

printf 'G6.2 owned-record nested producer negative gate passed fixtures=%d diagnostics=expected emission=none manifest=fail-closed\n' "${#fixtures[@]}"
