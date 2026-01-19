#!/bin/bash
set -e

EXE=do/bin/do
mkdir -p $(dirname $EXE)

zig build-exe zig/main.zig \
  -femit-bin=$EXE \
  -O ReleaseSmall \
  -fstrip \
  -fsingle-threaded

echo "Build successful: $EXE"