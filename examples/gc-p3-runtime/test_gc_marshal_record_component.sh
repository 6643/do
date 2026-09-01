#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin=${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
zig_bin=${ZIG_BIN:-zig}
wit="$repo_root/examples/gc-p3-runtime/marshal-record-assembly.wit"
probe="$repo_root/src/gc_marshal_record_probe_main.zig"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-component.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi

run_checked() {
  local stderr_file=$1
  shift
  if "$@" 2>"$stderr_file"; then
    return 0
  fi
  cat "$stderr_file" >&2
  return 1
}

run_checked "$tmp_dir/generate.stderr" "$zig_bin" run "$probe" -- "$wit" "$tmp_dir/core.wat"
run_checked "$tmp_dir/parse.stderr" "$toolchain_bin" parse-core "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"

if grep -E '^[[:space:]]*\(import .*(\(param|\(result).*\(ref' "$tmp_dir/core.wat" >"$tmp_dir/gc-import.stderr"; then
  cat "$tmp_dir/gc-import.stderr" >&2
  exit 1
fi

run_checked "$tmp_dir/embed.stderr" "$toolchain_bin" embed-component "$wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
run_checked "$tmp_dir/new.stderr" "$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
run_checked "$tmp_dir/validate.stderr" "$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none
run_checked "$tmp_dir/wit.stderr" "$toolchain_bin" component-wit "$tmp_dir/component.wasm" >"$tmp_dir/component.wit"
grep -Fq 'read: func() -> reading' "$tmp_dir/component.wit"
grep -Fq '(type $canonical_lift (func (param i32)))' "$tmp_dir/core.wat"
grep -Fq '(type $do_record (struct' "$tmp_dir/core.wat"

sed 's/read:/renamed:/' "$wit" >"$tmp_dir/renamed.wit"
run_checked "$tmp_dir/renamed-embed.stderr" "$toolchain_bin" embed-component "$tmp_dir/renamed.wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/renamed-embedded.wasm"
if "$toolchain_bin" new-component "$tmp_dir/renamed-embedded.wasm" -o "$tmp_dir/renamed.component.wasm" 2>"$tmp_dir/renamed-new.stderr"; then
  printf 'altered WIT member unexpectedly assembled\n' >&2
  exit 1
fi
grep -Fq 'missing function `read`' "$tmp_dir/renamed-new.stderr"

sed 's/(func \$canonical_call (type \$canonical_lift))/(func \$canonical_call (param (ref null \$do_record)))/' "$tmp_dir/core.wat" >"$tmp_dir/gc-import.wat"
if grep -E '^[[:space:]]*\(import .*(\(param|\(result).*\(ref' "$tmp_dir/gc-import.wat"; then
  :
else
  printf 'GC reference import negative probe did not detect the injected boundary ref\n' >&2
  exit 1
fi

printf 'parser-backed scalar record Component assembly passed\n'
