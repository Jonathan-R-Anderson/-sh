#!/usr/bin/env bash
set -e

# Compile all modules using the full D compiler.
modules=$(ls src/*.d | tr '\n' ' ')

echo "Compiling modules:" $modules

ldc2 -I=. -Isrc $modules -of=interpreter
