#!/bin/bash
set -e

# Modules that use unsupported features (exceptions or std library)
unsupported=$(grep -lE '\b(Exception|import std|try|catch|throw)\b' src/*.d | tr '\n' ' ')

modules=""
for f in src/*.d; do
    base=$(basename "$f")
    if [[ " $unsupported " != *" $f "* ]]; then
        modules+="$f "
    fi
done

# Always include the interpreter even if it was flagged as unsupported
modules+="src/interpreter.d"

echo "Compiling modules:" $modules
ldc2 -betterC --nodefaultlib -I=. -mtriple=x86_64-pc-linux-gnu $modules -of=interpreter
