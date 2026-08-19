#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
wit="$repo_root/examples/gc-p3-runtime/marshal-record-lower-assembly.wit"
probe="$repo_root/src/gc_marshal_record_probe_main.zig"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-lower-component.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

tool_version=$($wasm_tools_bin --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac

run_checked() {
  local stderr_file=$1
  shift
  if "$@" 2>"$stderr_file"; then
    return 0
  fi
  cat "$stderr_file" >&2
  return 1
}

run_checked "$tmp_dir/generate.stderr" "$zig_bin" run "$probe" -- "$wit" "$tmp_dir/core.wat" --lower-host
run_checked "$tmp_dir/parse.stderr" "$wasm_tools_bin" parse "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"

if grep -E '^[[:space:]]*\(import .*(\(param|\(result).*\(ref' "$tmp_dir/core.wat" >"$tmp_dir/gc-import.stderr"; then
  cat "$tmp_dir/gc-import.stderr" >&2
  exit 1
fi
grep -Fq '(type $canonical_lower (func (param i32 i32)))' "$tmp_dir/core.wat"
grep -Fq 'struct.get $do_record $field0' "$tmp_dir/core.wat"
grep -Fq 'struct.get $do_record $field1' "$tmp_dir/core.wat"
if grep -Fq 'cabi_realloc' "$tmp_dir/core.wat"; then
  printf 'scalar record lower unexpectedly allocated linear memory\n' >&2
  exit 1
fi

run_checked "$tmp_dir/embed.stderr" "$wasm_tools_bin" component embed "$wit" "$tmp_dir/core.wasm" --world probe -o "$tmp_dir/embedded.wasm"
run_checked "$tmp_dir/new.stderr" "$wasm_tools_bin" component new "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
run_checked "$tmp_dir/validate.stderr" "$wasm_tools_bin" validate "$tmp_dir/component.wasm"
run_checked "$tmp_dir/wit.stderr" "$wasm_tools_bin" component wit "$tmp_dir/component.wasm" >"$tmp_dir/component.wit"
grep -Fq 'write: func(value: writing)' "$tmp_dir/component.wit"
grep -Fq 'run: func() -> u32' "$tmp_dir/component.wit"

sed 's/write:/renamed:/' "$wit" >"$tmp_dir/renamed.wit"
run_checked "$tmp_dir/renamed-embed.stderr" "$wasm_tools_bin" component embed "$tmp_dir/renamed.wit" "$tmp_dir/core.wasm" --world probe -o "$tmp_dir/renamed-embedded.wasm"
if "$wasm_tools_bin" component new "$tmp_dir/renamed-embedded.wasm" -o "$tmp_dir/renamed.component.wasm" 2>"$tmp_dir/renamed-new.stderr"; then
  printf 'altered WIT member unexpectedly assembled\n' >&2
  exit 1
fi
grep -Fq 'missing function `write`' "$tmp_dir/renamed-new.stderr"

sed 's/(func \$canonical_call (type \$canonical_lower))/(func \$canonical_call (param (ref null \$do_record)))/' "$tmp_dir/core.wat" >"$tmp_dir/gc-import.wat"
if grep -E '^[[:space:]]*\(import .*(\(param|\(result).*\(ref' "$tmp_dir/gc-import.wat"; then
  :
else
  printf 'GC reference import negative probe did not detect the injected boundary ref\n' >&2
  exit 1
fi

printf 'parser-backed scalar record lower Component assembly passed\n'
