#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../.." && pwd -P)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source_wit="$script_dir/generic-async-runtime.wit"
source_main="$script_dir/project/generic_async_main.do"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "$repo_root/.tmp/wit-generated-async.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/wit"
cp "$source_main" "$tmp_dir/generic_async_main.do"

"$do_bin" wit check "$source_wit" --world probe
"$do_bin" wit bind "$source_wit" --world probe --out "$tmp_dir/wit"
"$do_bin" wit check "$source_wit" --world probe \
  --manifest "$tmp_dir/wit/manifest.json"
"$do_bin" build "$tmp_dir/generic_async_main.do" \
  --p3-async-component --p3-wit-output "$tmp_dir/generated.wit" \
  -o "$tmp_dir/runtime.wat"

cmp "$source_wit" "$tmp_dir/generated.wit"

for marker in \
  'do:generic-async-runtime-probe/host@0.1.0' \
  '[async-lower]work' \
  'call $host-work' \
  'call $subtask-cancel' \
  'call $subtask-drop' \
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
    --bin do-p3-generic-async-runtime-host-runner -- "$component"
}

pending_output=$(DO_GENERIC_ASYNC_RUNTIME_MODE=pending run_runner)
grep -Fq 'pending external-wakes=2 completions=2 drops=1' <<<"$pending_output"

immediate_output=$(DO_GENERIC_ASYNC_RUNTIME_MODE=immediate run_runner)
grep -Fq 'immediate external-wakes=0 completions=3 drops=0' <<<"$immediate_output"

cancel_output=$(DO_GENERIC_ASYNC_RUNTIME_MODE=cancel run_runner)
grep -Fq 'cancel cancel-before-completion=1 completions=2' <<<"$cancel_output"

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
    source-signature)
      sed -i 's/() -> Future<nil>/() -> Future<u32>/' "$manifest"
      ;;
    async-import-name)
      sed -i 's/\[async-lower\]work/\[async-lower\]wrong/' "$manifest"
      ;;
    completion)
      sed -i 's/task-return/wrong-return/' "$manifest"
      ;;
    capability)
      sed -i 's/component-async-unit-v1/unknown-capability/' "$manifest"
      ;;
    *)
      printf 'unknown manifest mutation %s\n' "$name" >&2
      exit 1
      ;;
  esac
  if "$do_bin" build "$tmp_dir/generic_async_main.do" \
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
expect_manifest_rejection source-signature
expect_manifest_rejection async-import-name
expect_manifest_rejection completion
expect_manifest_rejection capability

printf 'generated async Component/Rust/Wasmtime gate: PASS\n'
