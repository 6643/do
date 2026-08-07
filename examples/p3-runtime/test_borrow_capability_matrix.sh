#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/borrow-capability-matrix.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

expected_version=${WASM_TOOLS_EXPECT_VERSION:-1.255.0}
wasm_tools=${WASM_TOOLS:-wasm-tools}
tool_version=$("$wasm_tools" --version)
printf 'wasm-tools=%s\n' "$tool_version"
case "$tool_version" in
  "wasm-tools $expected_version"*) ;;
  *)
    printf 'expected wasm-tools %s, got: %s\n' "$expected_version" "$tool_version" >&2
    exit 1
    ;;
esac

printf '(module)\n' > "$tmp_dir/empty.wat"
"$wasm_tools" parse "$tmp_dir/empty.wat" -o "$tmp_dir/empty.wasm"

write_wit() {
  local shape=$1
  case "$shape" in
    direct)
      printf '%s\n' \
        'package do:borrow-capability-direct@0.1.0;' \
        '' \
        'interface api {' \
        '  resource ticket {}' \
        '  borrow-value: func(ticket: borrow<ticket>) -> u32;' \
        '}' \
        '' \
        'world borrow-direct {' \
        '  import api;' \
        '}' > "$tmp_dir/$shape.wit"
      ;;
    record)
      printf '%s\n' \
        'package do:borrow-capability-record@0.1.0;' \
        '' \
        'interface api {' \
        '  resource ticket {}' \
        '  record entry { ticket: borrow<ticket> }' \
        '  read: func(value: entry) -> u32;' \
        '}' \
        '' \
        'world borrow-record {' \
        '  import api;' \
        '}' > "$tmp_dir/$shape.wit"
      ;;
    variant)
      printf '%s\n' \
        'package do:borrow-capability-variant@0.1.0;' \
        '' \
        'interface api {' \
        '  resource ticket {}' \
        '  variant maybe-ticket { ticket(borrow<ticket>), none }' \
        '  read: func(value: maybe-ticket) -> u32;' \
        '}' \
        '' \
        'world borrow-variant {' \
        '  import api;' \
        '}' > "$tmp_dir/$shape.wit"
      ;;
    list)
      printf '%s\n' \
        'package do:borrow-capability-list@0.1.0;' \
        '' \
        'interface api {' \
        '  resource ticket {}' \
        '  read: func(value: list<borrow<ticket>>) -> u32;' \
        '}' \
        '' \
        'world borrow-list {' \
        '  import api;' \
        '}' > "$tmp_dir/$shape.wit"
      ;;
    future-owned)
      printf '%s\n' \
        'package do:borrow-capability-future-owned@0.1.0;' \
        '' \
        'interface api {' \
        '  resource ticket {}' \
        '  read: func() -> future<own<ticket>>;' \
        '}' \
        '' \
        'world borrow-future-owned {' \
        '  import api;' \
        '}' > "$tmp_dir/$shape.wit"
      ;;
    stream-owned)
      printf '%s\n' \
        'package do:borrow-capability-stream-owned@0.1.0;' \
        '' \
        'interface api {' \
        '  resource ticket {}' \
        '  record entry { ticket: own<ticket> }' \
        '  read: func() -> stream<entry>;' \
        '}' \
        '' \
        'world borrow-stream-owned {' \
        '  import api;' \
        '}' > "$tmp_dir/$shape.wit"
      ;;
    stream)
      printf '%s\n' \
        'package do:borrow-capability-stream@0.1.0;' \
        '' \
        'interface api {' \
        '  resource ticket {}' \
        '  record entry { ticket: borrow<ticket> }' \
        '  read: func() -> stream<entry>;' \
        '}' \
        '' \
        'world borrow-stream {' \
        '  import api;' \
        '}' > "$tmp_dir/$shape.wit"
      ;;
    future)
      printf '%s\n' \
        'package do:borrow-capability-future@0.1.0;' \
        '' \
        'interface api {' \
        '  resource ticket {}' \
        '  read: func() -> future<borrow<ticket>>;' \
        '}' \
        '' \
        'world borrow-future {' \
        '  import api;' \
        '}' > "$tmp_dir/$shape.wit"
      ;;
    *)
      printf 'unknown borrow capability shape: %s\n' "$shape" >&2
      exit 1
      ;;
  esac
}

check_accepted() {
  local shape=$1
  local world="borrow-$shape"
  local embedded="$tmp_dir/$shape.embedded.wasm"
  local component="$tmp_dir/$shape.component.wasm"
  write_wit "$shape"
  "$wasm_tools" component embed "$tmp_dir/$shape.wit" "$tmp_dir/empty.wasm" \
    --world "$world" -o "$embedded"
  "$wasm_tools" component new "$embedded" -o "$component"
  printf '%s=accepted\n' "$shape"
}

check_rejected() {
  local shape=$1
  local world="borrow-$shape"
  local stderr_file="$tmp_dir/$shape.stderr"
  write_wit "$shape"
  if "$wasm_tools" component embed "$tmp_dir/$shape.wit" "$tmp_dir/empty.wasm" \
    --world "$world" -o "$tmp_dir/$shape.embedded.wasm" \
    >"$tmp_dir/$shape.stdout" 2>"$stderr_file"; then
    printf '%s unexpectedly accepted\n' "$shape" >&2
    exit 1
  fi
  grep -Fq 'contains a `borrow<T>` which is not supported' "$stderr_file"
  printf '%s=rejected-at-embed\n' "$shape"
}

check_accepted direct
check_accepted record
check_accepted variant
check_accepted list
check_accepted future-owned
check_accepted stream-owned
check_rejected stream
check_rejected future
printf 'borrow capability matrix: PASS\n'
