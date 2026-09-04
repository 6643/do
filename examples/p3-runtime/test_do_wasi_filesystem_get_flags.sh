#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
fixture="$repo_root/src/build/test/compile_ok/471_wasi_filesystem_get_flags_component.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-get-flags-compiler.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

generated_wit="$tmp_dir/generated.wit"
generated_core_wat="$tmp_dir/generated.core.wat"
generated_core_wasm="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"

"$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_core_wat"
"$toolchain_bin" parse-core "$generated_core_wat" -o "$generated_core_wasm"
"$toolchain_bin" embed-component "$generated_wit" "$generated_core_wasm" \
  get-flags-probe -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$generated_wit"
grep -Fq 'flags descriptor-flags' "$generated_wit"
grep -Fq 'get-flags: async func() -> result<descriptor-flags, error-code>;' "$generated_wit"
grep -Fq 'run: async func(directory: own<descriptor>) -> result<descriptor-flags, error-code>;' "$generated_wit"
grep -Fq '"[async-lower][method]descriptor.get-flags"' "$generated_core_wat"
grep -Fq '"[resource-drop]descriptor"' "$generated_core_wat"

for name in 472_wasi_filesystem_get_flags_unregistered 473_wasi_filesystem_get_flags_wrong_result 474_wasi_filesystem_get_flags_borrowed_payload; do
  if "$repo_root/bin/do" build "$repo_root/src/build/test/compile_err/$name.do" \
      --p3-async-component -o "$tmp_dir/$name.wat" >"$tmp_dir/$name.out" 2>"$tmp_dir/$name.err"; then
    echo "$name unexpectedly compiled" >&2
    exit 1
  fi
done
grep -Fq 'UnsupportedP3AsyncComponent' "$tmp_dir/472_wasi_filesystem_get_flags_unregistered.err"
grep -Fq 'P3AsyncHostSignatureMismatch' "$tmp_dir/473_wasi_filesystem_get_flags_wrong_result.err"
grep -Fq 'P3AsyncHostSignatureMismatch' "$tmp_dir/474_wasi_filesystem_get_flags_borrowed_payload.err"

printf 'D2 filesystem descriptor.get-flags compiler Component gate passed\n'
