#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/future-owned-component.do"
wit_snapshot="$repo_root/examples/p3-runtime/future-owned-component.wit"
current_wasm_tools=${WASM_TOOLS:-wasm-tools}
legacy_wasm_tools=${LEGACY_WASM_TOOLS:-/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools}
expected_version=${WASM_TOOLS_EXPECT_VERSION:-1.255.0}

test -x "$do_bin"
test -f "$source"
test -f "$wit_snapshot"
test -x "$legacy_wasm_tools"

actual_version=$($current_wasm_tools --version)
case "$actual_version" in
  "wasm-tools $expected_version"*) ;;
  *)
    printf 'expected wasm-tools %s, got: %s\n' "$expected_version" "$actual_version" >&2
    exit 1
    ;;
esac

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-future-owned-component.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/future-owned.wat"
wit="$tmp_dir/future-owned.wit"
core_wasm="$tmp_dir/future-owned.core.wasm"
legacy_core_wasm="$tmp_dir/future-owned.legacy.core.wasm"
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

"$current_wasm_tools" parse "$core_wat" -o "$core_wasm"
"$legacy_wasm_tools" parse "$core_wat" -o "$legacy_core_wasm"
WASM_TOOLS="$legacy_wasm_tools" bash "$repo_root/examples/p3-runtime/assemble_wasmtime_p3_legacy.sh" \
  "$wit" "$legacy_core_wasm" future-owned-canonical "$component"
"$current_wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"
component_wit=$tmp_dir/component.wit
"$current_wasm_tools" component wit "$component" >"$component_wit"
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
