#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../.." && pwd -P)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
tmp_dir=$(mktemp -d "$repo_root/.tmp/wit-manifest.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/wit"
"$do_bin" wit bind "$script_dir/async-world.wit" --world probe --out "$tmp_dir/wit" >/dev/null
"$do_bin" wit check "$script_dir/async-world.wit" --world probe --manifest "$tmp_dir/wit/manifest.json" >/dev/null

sed -i 's/"async":true/"async":false/' "$tmp_dir/wit/manifest.json"
if "$do_bin" wit check "$script_dir/async-world.wit" --world probe --manifest "$tmp_dir/wit/manifest.json" >/dev/null 2>&1; then
    printf 'expected manifest mismatch to fail\n' >&2
    exit 1
fi

printf 'wit manifest contract: PASS\n'
