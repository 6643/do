#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATE="$ROOT_DIR/src/build/test/check_toolchain_adapter.sh"

[[ -x "$GATE" ]] || {
    printf '[FAIL] missing executable toolchain adapter gate: %s\n' "$GATE" >&2
    exit 1
}

root_output="$($GATE)"
grep -Fq '[PASS] toolchain adapter active gate' <<<"$root_output"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/do-toolchain-adapter-test.XXXXXX")"
negative_fixture=""
tmp_fixture=""
trap 'rm -f -- "$negative_fixture" "$tmp_fixture"; rm -rf -- "$tmp_dir"' EXIT
tmp_output="$(cd "$tmp_dir" && "$GATE")"
grep -Fq '[PASS] toolchain adapter active gate' <<<"$tmp_output"

negative_fixture="$(mktemp "$ROOT_DIR/src/build/test/check_toolchain_adapter_negative_fixture.XXXXXX.sh")"
negative_commands=(
    '"${WASM_TOOLS_BIN}" strip input.wasm -o output.wasm'
    '"$WASM_TOOLS" embed-component input.wit input.wat imports -o output.wat'
    '"$wasm_tools" parse input.wat -o output.wasm'
    'wasm-tools validate input.wasm'
    'wasm-tools --version'
    '/opt/legacy/wasm-tools parse input.wat -o output.wasm'
    '"$old_tool" parse input.wat -o output.wasm'
)
for direct_command in "${negative_commands[@]}"; do
    if [[ "$direct_command" == '"$old_tool" parse input.wat -o output.wasm' ]]; then
        printf '%s\n' 'old_tool="/opt/legacy/wasm-tools"' "$direct_command" >"$negative_fixture"
    else
        printf '%s\n' "$direct_command" >"$negative_fixture"
    fi
    if "$GATE" >"$tmp_dir/negative.stdout" 2>"$tmp_dir/negative.stderr"; then
        printf '[FAIL] direct tool scan accepted: %s\n' "$direct_command" >&2
        exit 1
    fi
    grep -Eq 'active shell invokes wasm-tools (directly|through an alias)' "$tmp_dir/negative.stderr"
done
printf '%s\n' \
    'old_tool="$(command -v wasm-tools)"' \
    '"$old_tool" --version' >"$negative_fixture"
if "$GATE" >"$tmp_dir/alias.stdout" 2>"$tmp_dir/alias.stderr"; then
    printf '[FAIL] alias scan accepted a command lookup alias\n' >&2
    exit 1
fi
grep -Fq 'active shell invokes wasm-tools through an alias' "$tmp_dir/alias.stderr"
rm -f -- "$negative_fixture"

printf '%s\n' \
    'PREFIX=1 old_tool="$(command -v wasm-tools)"' \
    '"$old_tool" parse input.wat -o output.wasm' >"$negative_fixture"
if "$GATE" >"$tmp_dir/multi_alias.stdout" 2>"$tmp_dir/multi_alias.stderr"; then
    printf '[FAIL] alias scan accepted a multi-assignment command lookup alias\n' >&2
    exit 1
fi
grep -Fq 'active shell invokes wasm-tools through an alias' "$tmp_dir/multi_alias.stderr"
rm -f -- "$negative_fixture"

tmp_fixture="$(mktemp "$ROOT_DIR/src/build/test/tmp/check_toolchain_adapter_tmp_fixture.XXXXXX.sh")"
printf '%s\n' \
    'tmp_tool="/opt/legacy/wasm-tools"' \
    '"$tmp_tool" parse input.wat -o output.wasm' >"$tmp_fixture"
tmp_output="$($GATE)"
grep -Fq '[PASS] toolchain adapter active gate' <<<"$tmp_output"
rm -f -- "$tmp_fixture"
tmp_fixture=""

printf '%s\n' '# pinned wasm-tools 1.255.0 reference' >"$negative_fixture"
if "$GATE" >"$tmp_dir/legacy.stdout" 2>"$tmp_dir/legacy.stderr"; then
    printf '[FAIL] legacy toolchain reference was accepted\n' >&2
    exit 1
fi
grep -Fq 'active shell contains legacy toolchain references' "$tmp_dir/legacy.stderr"
rm -f -- "$negative_fixture"

find_bin="$tmp_dir/find-bin"
mkdir -p "$find_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 2' >"$find_bin/find"
chmod +x "$find_bin/find"
if PATH="$find_bin:$PATH" "$GATE" >"$tmp_dir/find.stdout" 2>"$tmp_dir/find.stderr"; then
    printf '[FAIL] adapter gate swallowed a find execution failure\n' >&2
    exit 1
fi
grep -Fq 'alias file scan failed' "$tmp_dir/find.stderr"

fake_bin="$tmp_dir/fake-bin"
mkdir -p "$fake_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 2' >"$fake_bin/rg"
chmod +x "$fake_bin/rg"
if PATH="$fake_bin:$PATH" "$GATE" >"$tmp_dir/rg.stdout" 2>"$tmp_dir/rg.stderr"; then
    printf '[FAIL] adapter gate swallowed an rg execution failure\n' >&2
    exit 1
fi
grep -Fq 'raw command scan failed' "$tmp_dir/rg.stderr"

printf '[PASS] toolchain adapter gate test\n'
