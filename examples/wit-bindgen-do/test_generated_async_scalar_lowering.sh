#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../.." && pwd -P)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source_wit="$repo_root/examples/p3-runtime/wit/generic-async-scalar-probe.wit"
source_main="$script_dir/project/scalar_async_main.do"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "$repo_root/.tmp/wit-generated-async-scalar.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/wit"
cp "$source_main" "$tmp_dir/scalar_async_main.do"

"$do_bin" wit check "$source_wit" --world probe
"$do_bin" wit bind "$source_wit" --world probe --out "$tmp_dir/wit"
"$do_bin" wit check "$source_wit" --world probe --manifest "$tmp_dir/wit/manifest.json"
"$do_bin" build "$tmp_dir/scalar_async_main.do" \
  --p3-async-component --p3-wit-output "$tmp_dir/generated.wit" \
  -o "$tmp_dir/runtime.wat"

cmp "$source_wit" "$tmp_dir/generated.wit"

for marker in \
  'do:generic-async-scalar-probe/host@0.1.0' \
  '[async-lower][future-read-0]completion' \
  '[async-lower][future-cancel-read-0]completion' \
  '[future-drop-readable-0]completion' \
  '[scalar-payload] offset=12 byte-size=4 alignment=4 encoding=core-u32' \
  'call $future-read' \
  'call $future-cancel-read' \
  'call $future-drop-readable' \
  'call $waitable-set-drop' \
  'call $task-return'; do
  grep -Fq "$marker" "$tmp_dir/runtime.wat"
done

core_wasm="$tmp_dir/runtime.core.wasm"
embedded="$tmp_dir/runtime.embedded.wasm"
component="$tmp_dir/runtime.component.wasm"
wasm-tools parse "$tmp_dir/runtime.wat" -o "$core_wasm"
wasm-tools component embed "$source_wit" "$core_wasm" --world probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

cargo_bin=${CARGO_BIN:-cargo}
if ! command -v cc >/dev/null && command -v zig >/dev/null; then
  export CC="$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$CC"
fi

run_runner() {
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-generated-async-scalar-host-runner -- "$component"
}

ready_output=$(DO_GENERIC_ASYNC_SCALAR_MODE=ready run_runner)
grep -Fq 'mode=ready value=42 polls=2 wakes=0 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true' <<<"$ready_output"

pending_output=$(DO_GENERIC_ASYNC_SCALAR_MODE=pending run_runner)
grep -Fq 'mode=pending value=42 polls=3 wakes=1 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true' <<<"$pending_output"

cancel_output=$(DO_GENERIC_ASYNC_SCALAR_MODE=cancel run_runner)
grep -Fq 'mode=cancel value=42 polls=3 wakes=0 completions=1 future-drops=2 pending-future-drops=1 frame-drops=1 table-empty=true' <<<"$cancel_output"

manifest="$tmp_dir/wit/manifest.json"
expect_manifest_rejection() {
  local name=$1
  local output="$tmp_dir/$name.wat"
  local stderr="$tmp_dir/$name.stderr"
  cp "$manifest" "$tmp_dir/manifest.original"
  case "$name" in
    module-hash)
      sed -i '0,/"sha256":"[0-9a-f]\{64\}"/s//"sha256":"0000000000000000000000000000000000000000000000000000000000000000"/' "$manifest"
      ;;
    wit-hash)
      sed -i 's/"wit_sha256":"[0-9a-f]\{64\}"/"wit_sha256":"0000000000000000000000000000000000000000000000000000000000000000"/' "$manifest"
      ;;
    payload-offset)
      sed -i 's/"offset":12/"offset":16/' "$manifest"
      ;;
    source-signature)
      sed -i 's/() -> Future<u32>/() -> Future<i64>/' "$manifest"
      ;;
    async-import-name)
      sed -i 's/\[async-lower\]\[future-read-0\]completion/[async-lower][future-read-0]wrong/' "$manifest"
      ;;
    completion)
      sed -i 's/"completion":"completion"/"completion":"wrong"/' "$manifest"
      ;;
    *)
      printf 'unknown manifest mutation %s\n' "$name" >&2
      exit 1
      ;;
  esac
  if "$do_bin" build "$tmp_dir/scalar_async_main.do" \
      --p3-async-component --p3-wit-output "$tmp_dir/$name.wit" \
      -o "$output" >"$tmp_dir/$name.stdout" 2>"$stderr"; then
    printf 'expected manifest mutation %s to fail closed\n' "$name" >&2
    exit 1
  fi
  if [ -e "$output" ]; then
    printf 'manifest mutation %s emitted WAT before rejection\n' "$name" >&2
    exit 1
  fi
  grep -Fq 'GeneratedWitManifestMismatch' "$stderr"
  mv "$tmp_dir/manifest.original" "$manifest"
}

expect_manifest_rejection module-hash
expect_manifest_rejection wit-hash
expect_manifest_rejection payload-offset
expect_manifest_rejection source-signature
expect_manifest_rejection async-import-name
expect_manifest_rejection completion

printf 'generated async scalar Component/Rust/Wasmtime gate: PASS\n'
