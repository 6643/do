#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$repo_root/examples/p3-runtime/owned-error-resource-probe.do"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/owned-error-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$fixture" --p3-async-component \
  --p3-wit-output "$tmp_dir/owned-error-result.wit" \
  -o "$tmp_dir/owned-error-result.wat"

grep -Fq '[async-lower]send' "$tmp_dir/owned-error-result.wat"
grep -Fq '[resource-drop]request' "$tmp_dir/owned-error-result.wat"
grep -Fq '[resource-drop]response' "$tmp_dir/owned-error-result.wat"
grep -Fq '[resource-drop]error-resource' "$tmp_dir/owned-error-result.wat"
grep -Fq ';; [resource-owned-error-result]' "$tmp_dir/owned-error-result.wat"
grep -Fq 'world owned-error-result-probe' "$tmp_dir/owned-error-result.wit"

wasm-tools parse "$tmp_dir/owned-error-result.wat" \
  -o "$tmp_dir/owned-error-result.wasm"
wasm-tools component embed "$tmp_dir/owned-error-result.wit" \
  "$tmp_dir/owned-error-result.wasm" \
  --world owned-error-result-probe \
  -o "$tmp_dir/owned-error-result.embedded.wasm"
wasm-tools component new "$tmp_dir/owned-error-result.embedded.wasm" \
  -o "$tmp_dir/owned-error-result.component.wasm"
wasm-tools validate --features cm-async,cm-more-async-builtins \
  "$tmp_dir/owned-error-result.component.wasm"

cancel_core="$tmp_dir/owned-error-cancel.wat"
cancel_wit="$tmp_dir/owned-error-cancel.wit"
cancel_wasm="$tmp_dir/owned-error-cancel.wasm"
cancel_embedded="$tmp_dir/owned-error-cancel.embedded.wasm"
cancel_component="$tmp_dir/owned-error-cancel.component.wasm"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/owned-error-resource-cancel-component.do" \
  --p3-async-component --p3-wit-output "$cancel_wit" -o "$cancel_core"
cmp "$repo_root/src/build/p3_async_resource_owned_error_cancel_probe.wit" "$cancel_wit"
grep -Fq '(import "do:resource-probe-owned-error/http@0.1.0" "[async-lower]send"' "$cancel_core"
grep -Fq '[resource-drop]error-resource' "$cancel_core"
grep -Fq '[resource-result-cancel]' "$cancel_core"
if grep -Fq 'do:resource-probe/http@0.1.0' "$cancel_core"; then
  printf 'owned-error cancellation retained the old resource package\n' >&2
  exit 1
fi
wasm-tools parse "$cancel_core" -o "$cancel_wasm"
wasm-tools component embed "$cancel_wit" "$cancel_wasm" \
  --world owned-error-resource-cancel-probe -o "$cancel_embedded"
wasm-tools component new "$cancel_embedded" -o "$cancel_component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$cancel_component"

expect_rejected() {
  local fixture="$1"
  local expected="$2"
  local label
  label=$(basename "$fixture" .do)
  local stderr_path="$tmp_dir/$label.stderr"
  if DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
    "$repo_root/examples/p3-runtime/$fixture" --p3-async-component \
    -o "$tmp_dir/$label.wat" >"$tmp_dir/$label.stdout" 2>"$stderr_path"; then
    printf 'owned-error negative fixture unexpectedly lowered: %s\n' "$fixture" >&2
    exit 1
  fi
  grep -Fq "$expected" "$stderr_path"
}

expect_rejected owned-error-resource-request-consumed-twice.do ResourceAlreadyConsumed
expect_rejected owned-error-resource-unregistered-error.do P3AsyncHostSignatureMismatch
expect_rejected owned-error-resource-double-drop.do ResourceAlreadyConsumed
expect_rejected owned-error-resource-implicit-cancel.do FutureDropped

printf 'owned-error resource Result lowering and Component assembly verified\n'
