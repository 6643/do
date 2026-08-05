#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-wait-for-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

bash "$repo_root/examples/p3-runtime/test_async_template.sh"

for fixture in \
  "$repo_root/examples/p3-runtime/wait-for-component.do" \
  "$repo_root/examples/p3-runtime/wait-for-component-alias.do" \
  "$repo_root/examples/p3-runtime/wait-until-component.do"; do
  fixture_name=$(basename "$fixture" .do)
  case "$fixture_name" in
    wait-for-component|wait-for-component-alias) async_import='[async-lower]wait-for' ;;
    wait-until-component) async_import='[async-lower]wait-until' ;;
    *) printf 'missing expected async import for %s\n' "$fixture_name" >&2; exit 1 ;;
  esac
  core_path="$tmp_dir/$fixture_name.wat"
  wit_path="$tmp_dir/$fixture_name.wit"
  embedded_path="$tmp_dir/$fixture_name.embedded.wasm"
  component_path="$tmp_dir/$fixture_name.component.wasm"

  DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" \
    --p3-async-component --p3-wit-output "$wit_path" -o "$core_path"

  if grep -Fq '(component' "$core_path"; then
    printf 'pinned wait-for target must emit Core WAT for component assembly\n' >&2
    exit 1
  fi
  if ! grep -Fq "$async_import" "$core_path" || \
     ! grep -Fq '[callback][async-lift]run' "$core_path"; then
    printf 'pinned wait-for target is missing legacy Core async ABI state\n' >&2
    exit 1
  fi
  if grep -Fq 'component-type' "$core_path"; then
    printf 'pinned wait-for target must leave WIT metadata to component assembly\n' >&2
    exit 1
  fi

  wasm-tools component embed "$wit_path" "$core_path" --world probe -o "$embedded_path"
  wasm-tools component new "$embedded_path" -o "$component_path"

  DO_P3_COMPONENT="$component_path" "$repo_root/examples/p3-runtime/test_rust_wait_for.sh"
done
