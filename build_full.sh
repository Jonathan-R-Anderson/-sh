#!/usr/bin/env bash
set -euo pipefail

# Compiler (override with: DC=ldc2 ./build_full.sh)
DC="${DC:-dmd}"

# Flags for full runtime build
COMMON_FLAGS=(
  -O -inline -release
  -Isrc -Imstd         # keep if you still reference mstd during transition
)

# Collect sources
mapfile -t SOURCES < <(ls src/*.d)

echo "Building with ${DC}"
"${DC}" "${COMMON_FLAGS[@]}" "${SOURCES[@]}" -of=interpreter
echo "OK -> ./interpreter"
