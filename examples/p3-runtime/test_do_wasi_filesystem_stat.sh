#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools=${WASM_TOOLS:-wasm-tools}
fixture="$repo_root/src/build/test/compile_ok/498_wasi_filesystem_stat_component.do"
template="$repo_root/src/build/wasi_filesystem_stat_component_template.wat"
clock_wit="$repo_root/examples/p3-runtime/wit/wasi-clocks-wall-clock.wit"
expected_generated_wit_sha256=4a2e5055c2ec06c772660b211c3e3ab3e3e15d8b5931c8e7def804e56d5175da
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-stat-compiler.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

command -v "$wasm_tools" >/dev/null || {
  printf 'missing executable: %s\n' "$wasm_tools" >&2
  exit 1
}

generated_wit="$tmp_dir/generated.wit"
generated_core_wat="$tmp_dir/generated.core.wat"
generated_core_wasm="$tmp_dir/generated.core.wasm"
embedded="$tmp_dir/generated.embedded.wasm"
component="$tmp_dir/generated.component.wasm"
component_wat="$tmp_dir/generated.component.wat"
component_wit="$tmp_dir/generated.component.wit"
wit_dir="$tmp_dir/wit"
mkdir -p "$wit_dir/deps/clocks"
cp "$clock_wit" "$wit_dir/deps/clocks/wall-clock.wit"

if "$repo_root/bin/do" build "$fixture" -o "$tmp_dir/default.wat" >"$tmp_dir/default.out" 2>"$tmp_dir/default.err"; then
  printf 'default build unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'AsyncLoweringUnavailable' "$tmp_dir/default.err"
[[ ! -e "$tmp_dir/default.wat" ]] || {
  printf 'default build produced WAT despite unsupported lowering\n' >&2
  exit 1
}

"$repo_root/bin/do" build "$fixture" \
  --p3-wasi-filesystem-stat-component --p3-wit-output "$generated_wit" \
  -o "$generated_core_wat"
cmp -s "$generated_core_wat" "$template" || {
  printf 'generated Core WAT differs from the canonical stat template\n' >&2
  exit 1
}
cp "$generated_wit" "$wit_dir/generated.wit"

[[ "$(sha256sum "$generated_wit" | awk '{print $1}')" == "$expected_generated_wit_sha256" ]] || {
  printf 'generated WIT hash changed\n' >&2
  exit 1
}

grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$generated_wit"
grep -Fq 'record descriptor-stat' "$generated_wit"
grep -Fq 'stat: async func() -> result<descriptor-stat, error-code>;' "$generated_wit"
grep -Fq 'run: async func(file: own<descriptor>) -> result<descriptor-stat, error-code>;' "$generated_wit"
[[ $(grep -cF 'stat: async func' "$generated_wit") -eq 1 ]] || {
  printf 'unexpected stat method count in generated WIT\n' >&2
  exit 1
}
[[ $(grep -cF 'resource descriptor' "$generated_wit") -eq 1 ]] || {
  printf 'unexpected descriptor resource count in generated WIT\n' >&2
  exit 1
}

"$wasm_tools" parse "$generated_core_wat" -o "$generated_core_wasm"
"$wasm_tools" component embed "$wit_dir" "$generated_core_wasm" \
  --world stat-probe --features cm-async,cm-more-async-builtins -o "$embedded"
"$wasm_tools" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"
"$wasm_tools" print "$component" >"$component_wat"
"$wasm_tools" component wit "$component" >"$component_wit"

for fragment in \
  '"[async-lower][method]descriptor.stat"' \
  '"[resource-drop]descriptor"' \
  '"[task-return]run"' \
  'result $descriptor-stat (error $error-code)'; do
  grep -Fq "$fragment" "$component_wat" || {
    printf 'missing generated Component marker: %s\n' "$fragment" >&2
    exit 1
  }
done
grep -Fq 'record descriptor-stat' "$component_wit"
grep -Fq 'enum error-code' "$component_wit"
grep -Fq 'stat: async func() -> result<descriptor-stat, error-code>;' "$component_wit"
grep -Fq 'run: async func(file: descriptor) -> result<descriptor-stat, error-code>;' "$component_wit"
for forbidden in \
  'descriptor.get-type' 'descriptor.get-flags' 'descriptor.sync' \
  'descriptor.read' 'descriptor.write' 'future<borrow' 'stream<'; do
  if grep -Fq "$forbidden" "$component_wat"; then
    printf 'unexpected generated Component import: %s\n' "$forbidden" >&2
    exit 1
  fi
done

expected_cases=(
  499_wasi_filesystem_stat_unregistered
  500_wasi_filesystem_stat_wrong_version
  501_wasi_filesystem_stat_wrong_result
  502_wasi_filesystem_stat_missing_datetime
  503_wasi_filesystem_stat_wrong_field_type
  504_wasi_filesystem_stat_borrowed_result
  505_wasi_filesystem_stat_second_await
  506_wasi_filesystem_stat_branch
  507_wasi_filesystem_stat_loop
  508_wasi_filesystem_stat_extra_host
  509_wasi_filesystem_stat_wrong_resource
  510_wasi_filesystem_stat_async_root
)
for name in "${expected_cases[@]}"; do
  expect="$repo_root/src/build/test/compile_err/$name.expect"
  source="$repo_root/src/build/test/compile_err/$name.do"
  output="$tmp_dir/$name.wat"
  stderr="$tmp_dir/$name.err"
  expected=$(sed -n '2p' "$expect")
  if "$repo_root/bin/do" build "$source" \
      --p3-wasi-filesystem-stat-component -o "$output" \
      >"$tmp_dir/$name.out" 2>"$stderr"; then
    printf '%s unexpectedly compiled\n' "$name" >&2
    exit 1
  fi
  grep -Fq "$expected" "$stderr" || {
    printf '%s missing expected diagnostic: %s\n' "$name" "$expected" >&2
    cat "$stderr" >&2
    exit 1
  }
  [[ ! -e "$output" ]] || {
    printf '%s produced WAT after rejection\n' "$name" >&2
    exit 1
  }
done

printf 'D2 filesystem descriptor.stat Do compiler Component gate passed\n'
printf 'generated-core-sha256=%s generated-wit-sha256=%s\n' \
  "$(sha256sum "$generated_core_wat" | awk '{print $1}')" \
  "$(sha256sum "$generated_wit" | awk '{print $1}')"
