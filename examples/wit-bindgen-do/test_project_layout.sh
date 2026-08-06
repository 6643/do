#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../.." && pwd -P)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source_wit="$script_dir/async-world.wit"
tmp_dir=$(mktemp -d "$repo_root/.tmp/wit-layout.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/wit/src"
cp "$source_wit" "$tmp_dir/wit/src/async-world.wit"
printf '%s\n' 'project marker' >"$tmp_dir/wit/README.md"

"$do_bin" wit bind "$tmp_dir/wit/src" --world probe --out "$tmp_dir/wit"
test -f "$tmp_dir/wit/src/async-world.wit"
test -f "$tmp_dir/wit/README.md"
test -f "$tmp_dir/wit/do_bindgen_probe__api__probe.do"
test -f "$tmp_dir/wit/manifest.json"
test -f "$tmp_dir/wit/wit.lock"
"$do_bin" wit check "$tmp_dir/wit/src" --world probe --manifest "$tmp_dir/wit/manifest.json"

printf '%s\n' 'package do:broken@1.0.0' >"$tmp_dir/broken.wit"
if "$do_bin" wit bind "$tmp_dir/broken.wit" --world probe --out "$tmp_dir/wit"; then
    printf 'expected invalid bind to fail\n' >&2
    exit 1
fi
test -f "$tmp_dir/wit/src/async-world.wit"
test -f "$tmp_dir/wit/README.md"
test -f "$tmp_dir/wit/do_bindgen_probe__api__probe.do"

printf 'wit project layout: PASS\n'
