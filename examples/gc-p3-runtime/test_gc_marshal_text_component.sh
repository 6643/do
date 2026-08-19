#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool_version=$(wasm-tools --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac

wit="$repo_root/examples/gc-p3-runtime/marshal-text-assembly.wit"
core_wat="$repo_root/examples/gc-p3-runtime/marshal-text-core.wat"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

run_checked() {
  local stderr_file=$1
  shift
  if "$@" 2>"$stderr_file"; then
    return 0
  fi
  cat "$stderr_file" >&2
  return 1
}

assert_no_gc_imports() {
  local file=$1
  if grep -E '^[[:space:]]*\(import .*\(ref' "$file" >"$tmp_dir/gc-import.stderr"; then
    cat "$tmp_dir/gc-import.stderr" >&2
    return 1
  fi
}

run_checked "$tmp_dir/parse.stderr" wasm-tools parse "$core_wat" -o "$tmp_dir/core.wasm"
assert_no_gc_imports "$core_wat"
run_checked "$tmp_dir/embed.stderr" wasm-tools component embed "$wit" "$tmp_dir/core.wasm" --world probe -o "$tmp_dir/embedded.wasm"
run_checked "$tmp_dir/new.stderr" wasm-tools component new "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
run_checked "$tmp_dir/validate.stderr" wasm-tools validate "$tmp_dir/component.wasm"
run_checked "$tmp_dir/wit.stderr" wasm-tools component wit "$tmp_dir/component.wasm" >"$tmp_dir/component.wit"
grep -Fq 'send: func(value: string)' "$tmp_dir/component.wit"

sed 's/send:/renamed:/' "$wit" >"$tmp_dir/renamed.wit"
run_checked "$tmp_dir/renamed-embed.stderr" wasm-tools component embed "$tmp_dir/renamed.wit" "$tmp_dir/core.wasm" --world probe -o "$tmp_dir/renamed-embedded.wasm"
if wasm-tools component new "$tmp_dir/renamed-embedded.wasm" -o "$tmp_dir/renamed.component.wasm" 2>"$tmp_dir/renamed-new.stderr"; then
  printf 'altered WIT member unexpectedly assembled\n' >&2
  exit 1
fi
grep -Fq 'missing function `send`' "$tmp_dir/renamed-new.stderr"

sed 's/(func $canonical_call/(func $canonical_call (param (ref null $do_text))/' "$core_wat" >"$tmp_dir/gc-import.wat"
if assert_no_gc_imports "$tmp_dir/gc-import.wat"; then
  printf 'GC reference import unexpectedly admitted\n' >&2
  exit 1
fi

printf 'bounded GC text marshal Component assembly passed\n'
