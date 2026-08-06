#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/generic-async-scalar-probe.wit"
core_wat="$repo_root/examples/p3-runtime/generic-async-scalar-probe.core.wat"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-generic-async-scalar.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wasm="$tmp_dir/generic-async-scalar-probe.core.wasm"
embedded="$tmp_dir/generic-async-scalar-probe.embedded.wasm"
component="$tmp_dir/generic-async-scalar-probe.component.wasm"

test -f "$wit"
test -f "$core_wat"

expected='package do:generic-async-scalar-probe@0.1.0;

interface host {
  completion: func() -> future<u32>;
}

world probe {
  import host;
  export run: async func();
}
'
actual=$(<"$wit")
if [[ "$actual"$'\n' != "$expected" ]]; then
  printf 'scalar probe WIT shape drifted\n' >&2
  diff -u <(printf '%s' "$expected") <(printf '%s\n' "$actual") >&2 || true
  exit 1
fi

grep -Fq 'future<u32>' "$wit"
grep -Fq 'completion: func()' "$wit"
grep -Fq 'export run: async func();' "$wit"

for marker in \
  '"do:generic-async-scalar-probe/host@0.1.0" "completion"' \
  '"[async-lower][future-read-0]completion"' \
  '"[async-lower][future-cancel-read-0]completion"' \
  '"[future-drop-readable-0]completion"' \
  '"[task-return]run"' \
  '"[async-lift]run"' \
  '"[callback][async-lift]run"' \
  '[scalar-payload] offset=12 byte-size=4 alignment=4 encoding=core-u32'; do
  grep -Fq "$marker" "$core_wat"
done
if grep -Fq '"[async-lower]completion"' "$core_wat"; then
  printf 'scalar probe incorrectly async-lowered the future-returning completion import\n' >&2
  exit 1
fi

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" --world probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"
component_text="$tmp_dir/component.txt"
wasm-tools print "$component" > "$component_text"
grep -Fq '(type (;0;) (future u32))' "$component_text"
grep -Fq '"[async-lower][future-read-0]completion"' "$component_text"
grep -Fq '"[async-lower][future-cancel-read-0]completion"' "$component_text"

cargo_bin=${CARGO_BIN:-cargo}
zig_cc="$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh"

run_runner() {
  CC="$zig_cc" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$zig_cc" \
    "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
      --bin do-p3-generic-async-scalar-probe-host-runner -- "$component"
}

ready_output=$(DO_GENERIC_ASYNC_SCALAR_MODE=ready run_runner)
grep -Fq 'mode=ready value=42 polls=2 wakes=0 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true' <<<"$ready_output"

pending_output=$(DO_GENERIC_ASYNC_SCALAR_MODE=pending run_runner)
grep -Fq 'mode=pending value=42 polls=3 wakes=1 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true' <<<"$pending_output"

cancel_output=$(DO_GENERIC_ASYNC_SCALAR_MODE=cancel run_runner)
grep -Fq 'mode=cancel value=42 polls=3 wakes=0 completions=1 future-drops=2 pending-future-drops=1 frame-drops=1 table-empty=true' <<<"$cancel_output"

printf 'generic async scalar probe passed payload-offset=12 byte-size=4 alignment=4 encoding=core-u32\n'
