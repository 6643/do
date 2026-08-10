#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
fixture="$repo_root/src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.do"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at-cancel.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-metadata-hash-at.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-metadata-hash-at-cancel.core.wat"
runner_source="$runner_dir/src/bin/wasi_filesystem_metadata_hash_at.rs"
wasm_tools=${WASM_TOOLS:-wasm-tools}
expected_wasm_tools='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
expected_wasm_tools_sha256=6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013
expected_wit_sha256=95e24b70eeed89407706c18a6e4cd13a8bc4dce72d1e56638436b03287d23412
expected_cancel_wit_sha256=aca9c5933786a00a2dd20b1ad1ddbb6d0a79ab5b3bdbd5bd61e14b100a3b6e0a
expected_core_wat_sha256=44e5d94d13676bf25326fc04969cfd758e01b6d77061829136f1c9f869e2e536
expected_cancel_core_wat_sha256=c9681e8d68f17f06409cc423c24bc4c051c39263cecb2c5976e2f8385c0e9caa

command -v "$wasm_tools" >/dev/null || {
    printf 'missing executable: %s\n' "$wasm_tools" >&2
    exit 1
}
[[ "$($wasm_tools --version)" == "$expected_wasm_tools" ]] || {
    printf 'wasm-tools version mismatch\n' >&2
    exit 1
}
[[ "$(sha256sum "$(command -v "$wasm_tools")" | awk '{print $1}')" == "$expected_wasm_tools_sha256" ]] || {
    printf 'wasm-tools hash mismatch\n' >&2
    exit 1
}

check_sha() {
    local path=$1
    local expected=$2
    local actual
    actual=$(sha256sum "$path" | awk '{print $1}')
    [[ "$actual" == "$expected" ]] || {
        printf 'sha256 mismatch for %s: expected %s got %s\n' "$path" "$expected" "$actual" >&2
        exit 1
    }
}

for path in "$fixture" "$repo_root/bin/do" "$wit" "$cancel_wit" "$core_wat" "$cancel_core_wat" "$runner_source"; do
    [[ -f "$path" ]] || {
        printf 'missing metadata-hash-at runtime input: %s\n' "$path" >&2
        exit 1
    }
done
check_sha "$wit" "$expected_wit_sha256"
check_sha "$cancel_wit" "$expected_cancel_wit_sha256"
check_sha "$core_wat" "$expected_core_wat_sha256"
check_sha "$cancel_core_wat" "$expected_cancel_core_wat_sha256"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-metadata-hash-at-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/regular" "$tmp_dir/cancel" "$tmp_dir/root"
cp "$wit" "$tmp_dir/regular/wasi-filesystem-metadata-hash-at.wit"
cp "$cancel_wit" "$tmp_dir/cancel/wasi-filesystem-metadata-hash-at-cancel.wit"
generated_wit="$tmp_dir/generated.wit"
generated_core_wat="$tmp_dir/generated.core.wat"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" \
    --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_core_wat" >/dev/null
grep -Fq 'metadata-hash-at: async func(path-flags: path-flags, path: string)' "$generated_wit"
grep -Fq 'run: async func(file: own<descriptor>, path-flags: path-flags, path: string)' "$generated_wit"
grep -Fq '(type $method (func (param i32 i32 i32 i32 i32) (result i32)))' "$generated_core_wat"
grep -Fq '(type $task-return-metadata-hash-at (func (param i32 i64 i64)))' "$generated_core_wat"
grep -Fq '[metadata-hash-at-result-area]' "$generated_core_wat"
grep -Fq '[descriptor-drop]' "$generated_core_wat"
test "$(grep -Fc 'call $metadata-hash-at' "$generated_core_wat")" -eq 1
probe_path=$'probe-utf8-\u6587\u4ef6'
printf 'd2-metadata-hash-at\n' >"$tmp_dir/root/$probe_path"

build_component() {
    local input_dir=$1
    local world=$2
    local wat=$3
    local name=$4
    local core="$tmp_dir/$name.core.wasm"
    local embedded="$tmp_dir/$name.embedded.wasm"
    local component="$tmp_dir/$name.component.wasm"
    "$wasm_tools" parse "$wat" -o "$core"
    "$wasm_tools" component embed "$input_dir" "$core" --world "$world" \
        --features cm-async,cm-more-async-builtins -o "$embedded"
    "$wasm_tools" component new --skip-validation "$embedded" -o "$component"
    "$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"
    printf '%s\n' "$component"
}

component=$(build_component "$generated_wit" metadata-hash-at-probe "$generated_core_wat" generated)
cancel_component=$(build_component "$tmp_dir/cancel" metadata-hash-at-cancel-probe "$cancel_core_wat" cancel)

rustfmt --edition 2024 --check "$runner_source"

runner_env=(
    DO_D2_FILESYSTEM_ROOT="$tmp_dir/root"
    DO_D2_FILESYSTEM_PATH="$probe_path"
    CC="$runner_dir/zig-cc.sh"
    CXX="$runner_dir/zig-cc.sh"
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

run_runner() {
    local component_path=$1
    local mode=$2
    (cd "$runner_dir" && env "${runner_env[@]}" timeout 60s \
        cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
        --bin wasi_filesystem_metadata_hash_at -- "$component_path" "$mode")
}

ready=$(run_runner "$component" ready)
pending=$(run_runner "$component" pending)
error=$(run_runner "$component" error)
cancel=$(run_runner "$cancel_component" cancel)
early_drop=$(run_runner "$component" early-drop)
repeat=$(run_runner "$component" repeat)

expected_path="observed-path=$probe_path"
grep -Fq "mode=ready result=Ok lower=72623859790382856 upper=1230066625199609624 host-calls=1 path-copies=1 observed-flags=1 $expected_path completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true" <<<"$ready"
grep -Fq "mode=pending result=Ok lower=72623859790382856 upper=1230066625199609624 host-calls=1 path-copies=1 observed-flags=1 $expected_path completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true" <<<"$pending"
grep -Fq "mode=error result=Err(no-entry) host-calls=1 path-copies=1 observed-flags=1 $expected_path completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true" <<<"$error"
grep -Fq "mode=cancel result=cancelled host-calls=1 path-copies=1 observed-flags=0 observed-path=<none> completion-polls=1 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=1 table-empty=true" <<<"$cancel"
grep -Fq "mode=early-drop result=store-discarded host-calls=1 path-copies=1 observed-flags=0 observed-path=<none>" <<<"$early_drop"
grep -Fq 'pending-future-drops=1 descriptor-drops=0 table-empty=not-applicable' <<<"$early_drop"
grep -Fq "mode=repeat results=Ok,Ok host-calls=2 path-copies=2 observed-flags=1 $expected_path completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 table-empty=true" <<<"$repeat"

printf 'D2 filesystem descriptor.metadata-hash-at Rust/Wasmtime runtime passed\n'
printf 'modes=ready,pending,error,cancel,early-drop,repeat path-copy=owned-rust-string cleanup=exactly-once\n'
