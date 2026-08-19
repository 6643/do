#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-evidence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

cat > "$tmp_dir/verified.md" <<'EOF'
Verification Status: verified
EOF
cat > "$tmp_dir/unverified.md" <<'EOF'
Evidence exists but has no verification marker.
EOF
cat > "$tmp_dir/verified.sh" <<'EOF'
#!/usr/bin/env bash
# Verification Status: verified
EOF
cat > "$tmp_dir/unverified.txt" <<'EOF'
Verification Status: verified
EOF

bash "$ROOT/src/build/test/check_gc_migration_inventory.sh" --check-evidence "$tmp_dir/verified.md"
if bash "$ROOT/src/build/test/check_gc_migration_inventory.sh" --check-evidence "$tmp_dir/unverified.md"; then
    printf 'expected unverified markdown evidence to fail\n' >&2
    exit 1
fi
bash "$ROOT/src/build/test/check_gc_migration_inventory.sh" --check-evidence "$tmp_dir/verified.sh"
if bash "$ROOT/src/build/test/check_gc_migration_inventory.sh" --check-evidence "$tmp_dir/unverified.txt"; then
    printf 'expected unsupported evidence extension to fail\n' >&2
    exit 1
fi
printf 'GC migration evidence validation tests passed\n'
