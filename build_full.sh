#!/usr/bin/env bash
set -e

# Determine target system from the first argument or SYSTEM env var
system=${1:-${SYSTEM:-custom}}

# Compile all modules using the full D compiler.
modules=$(ls src/*.d | tr '\n' ' ')

echo "Compiling modules:" $modules

# Use the Linux system compiler when targeting a Linux host
if [[ "$system" == "linux" ]]; then
    dmd_cmd=${DC:-dmd}
else
    dmd_cmd=${DC:-anonymos-dmd}
fi

"$dmd_cmd" -I=. -Isrc $modules -of=interpreter
