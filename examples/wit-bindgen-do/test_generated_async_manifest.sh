#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../.." && pwd -P)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source_wit="$script_dir/async-world.wit"
source_main="$script_dir/project/async_main.do"
tmp_dir=$(mktemp -d "$repo_root/.tmp/wit-async-manifest.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/wit/src"
cp "$source_wit" "$tmp_dir/wit/src/async-world.wit"
cp "$source_main" "$tmp_dir/async_main.do"

"$do_bin" wit bind "$tmp_dir/wit/src" --world probe --out "$tmp_dir/wit"
"$do_bin" check "$tmp_dir/async_main.do"
"$do_bin" wit check "$tmp_dir/wit/src" --world probe --manifest "$tmp_dir/wit/manifest.json"

# A generated module is not admitted by path shape alone. Its sibling
# manifest is the source of the async/future effect contract.
mv "$tmp_dir/wit/manifest.json" "$tmp_dir/wit/manifest.json.saved"
if "$do_bin" check "$tmp_dir/async_main.do" >"$tmp_dir/missing.stdout" 2>"$tmp_dir/missing.stderr"; then
    printf 'expected generated manifest discovery to fail closed\n' >&2
    exit 1
fi
grep -Fq 'GeneratedWitManifestMissing' "$tmp_dir/missing.stderr"
mv "$tmp_dir/wit/manifest.json.saved" "$tmp_dir/wit/manifest.json"

# Changing only the generated async effect must also invalidate caller
# admission; module bytes alone do not define the Future contract.
cp "$tmp_dir/wit/manifest.json" "$tmp_dir/wit/manifest.json.original"
sed -i 's/"effect":"async","async":true/"effect":"sync","async":false/' \
    "$tmp_dir/wit/manifest.json"
if "$do_bin" check "$tmp_dir/async_main.do" >"$tmp_dir/effect-caller.stdout" 2>"$tmp_dir/effect-caller.stderr"; then
    printf 'expected caller admission to reject manifest effect drift\n' >&2
    exit 1
fi
grep -Fq 'GeneratedWitManifestMismatch' "$tmp_dir/effect-caller.stderr"
mv "$tmp_dir/wit/manifest.json.original" "$tmp_dir/wit/manifest.json"

if "$do_bin" build "$tmp_dir/async_main.do" -o "$tmp_dir/async_main.wat" >"$tmp_dir/build.stdout" 2>"$tmp_dir/build.stderr"; then
    printf 'expected colorless async lowering to remain guarded\n' >&2
    exit 1
fi
grep -Fq 'AsyncLoweringUnavailable' "$tmp_dir/build.stderr"

# A generated member changing from Future<T> to T must invalidate the binding
# before any caller is allowed to rely on its async metadata.
sed -i 's/) -> Future<Response | ApiError>)/) -> Response | ApiError)/' \
    "$tmp_dir/wit/do_bindgen_probe__api__probe.do"
if "$do_bin" wit check "$tmp_dir/wit/src" --world probe --manifest "$tmp_dir/wit/manifest.json" >"$tmp_dir/mismatch.stdout" 2>"$tmp_dir/mismatch.stderr"; then
    printf 'expected generated module mismatch to fail\n' >&2
    exit 1
fi
grep -Fq 'ManifestGeneratedModuleMismatch' "$tmp_dir/mismatch.stderr"
if "$do_bin" check "$tmp_dir/async_main.do" >"$tmp_dir/caller-mismatch.stdout" 2>"$tmp_dir/caller-mismatch.stderr"; then
    printf 'expected caller admission to reject generated module drift\n' >&2
    exit 1
fi
grep -Fq 'GeneratedWitManifestMismatch' "$tmp_dir/caller-mismatch.stderr"

# A WIT effect changing from async to sync must also invalidate the manifest.
sed 's/async func send/func send/' "$source_wit" >"$tmp_dir/wit/src/drifted.wit"
if "$do_bin" wit check "$tmp_dir/wit/src/drifted.wit" --world probe --manifest "$tmp_dir/wit/manifest.json" >"$tmp_dir/effect.stdout" 2>"$tmp_dir/effect.stderr"; then
    printf 'expected WIT effect mismatch to fail\n' >&2
    exit 1
fi
grep -Fq 'ManifestBindingMismatch' "$tmp_dir/effect.stderr"

printf 'generated colorless async manifest: PASS\n'
