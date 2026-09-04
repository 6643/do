#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
source="$repo_root/examples/p3-runtime/future-owned-component.do"
wit_snapshot="$repo_root/examples/p3-runtime/future-owned-component.wit"

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$source"
test -f "$wit_snapshot"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-future-owned-component.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/future-owned.wat"
wit="$tmp_dir/future-owned.wit"
core_wasm="$tmp_dir/future-owned.core.wasm"
component="$tmp_dir/future-owned.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-owned-future-component --p3-wit-output "$wit" -o "$core_wat"
cmp "$wit_snapshot" "$wit"

for marker in \
    '[future-owned-payload]' \
    '[future-owned-ticket-present]' \
    '[future-owned-transfer]' \
    '[future-owned-resource-drop]' \
    '[future-owned-cancel]' \
    '[task-return]run' \
    '[resource-drop]ticket'; do
  grep -Fq "$marker" "$core_wat"
done
if grep -Fq '[task-return]helper' "$core_wat" ||
    grep -Fq '[async-lift]helper' "$core_wat" ||
    grep -Fq 'future<borrow<' "$core_wat"; then
  printf 'future-owned target emitted an unsupported helper or borrowed future\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
  "$wit" "$core_wasm" future-owned-canonical "$component"
"$toolchain_bin" validate-component "$component"
component_wit=$tmp_dir/component.wit
"$toolchain_bin" component-wit "$component" >"$component_wit"
grep -Fq 'read: func() -> future<ticket>' "$component_wit"
grep -Fq 'run: async func(mode: u32)' "$component_wit"

bash "$repo_root/examples/p3-runtime/test_rust_future_owned_component.sh" "$component"

run_isolation() {
  local name="$1"
  shift
  local wat="$tmp_dir/$name.wat"
  local output="$tmp_dir/$name.stdout"
  local stderr="$tmp_dir/$name.stderr"
  set +e
  DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" "$@" -o "$wat" >"$output" 2>"$stderr"
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    if grep -Fq '[future-owned-' "$wat"; then
      printf '%s target emitted future-owned markers\n' "$name" >&2
      exit 1
    fi
    printf '%s-isolation=accepted-without-future-owned-markers\n' "$name"
  else
    if ! grep -Eq 'UnsupportedP3|UnsupportedGenericAbiV2Promotion' "$stderr"; then
      cat "$stderr" >&2
      exit 1
    fi
    printf '%s-isolation=rejected-before-wat\n' "$name"
  fi
}

run_isolation v1 --p3-async-component
run_isolation v2 --p3-async-component-v2

for conflicting_flag in --component-core --host-export; do
  conflict_name=${conflicting_flag#--}
  stderr="$tmp_dir/$conflict_name.stderr"
  set +e
  DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
    --p3-owned-future-component "$conflicting_flag" \
    -o "$tmp_dir/conflict.wat" >"$tmp_dir/conflict.stdout" 2>"$stderr"
  status=$?
  set -e
  test "$status" -ne 0
  grep -Fq 'UnexpectedCliArg' "$stderr"
done

printf 'do future<own<ticket>> compiler Component gate passed\n'
