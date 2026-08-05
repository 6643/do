#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

bash "$repo_root/examples/p3-runtime/test_do_resource_probe_lowering.sh"
"$repo_root/bin/do" build "$repo_root/examples/p3-runtime/resource-probe.do" \
  --p3-resource-probe-component \
  --p3-wit-output "$tmp_dir/probe.wit" \
  -o "$tmp_dir/probe.wat" >/dev/null
wasm-tools parse "$tmp_dir/probe.wat" -o "$tmp_dir/probe.wasm"
wasm-tools component embed "$tmp_dir/probe.wit" --world probe -o "$tmp_dir/probe.embedded.wasm" "$tmp_dir/probe.wasm"
wasm-tools component new -o "$tmp_dir/probe.component.wasm" "$tmp_dir/probe.embedded.wasm"

output=$(cd "$repo_root/examples/p3-runtime/rust-host-runner" && CC="$PWD/zig-cc.sh" CXX="$PWD/zig-cc.sh" CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" cargo run --quiet --bin do-p3-resource-probe-host-runner -- "$tmp_dir/probe.component.wasm")
for marker in 'Rust P3 resource adapter passed' 'ticket create=2' 'ticket borrow=2' 'ticket consume=1' 'ticket drop=1'; do
  case "$output" in *"$marker"*) ;; *) printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2; exit 1;; esac
done
