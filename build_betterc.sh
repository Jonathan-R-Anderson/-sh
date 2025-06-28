set -e

# Modules that use unsupported features (exceptions or std library)
unsupported=$(grep -lE '\b(Exception|import std|try|catch|throw)\b' src/*.d | tr '\n' ' ')

modules=""
for f in src/*.d; do
    base=$(basename "$f")
    # Skip modules flagged as unsupported
    if [[ " $unsupported " == *" $f "* ]]; then
        continue
    fi
    # Skip demonstration program which depends on unsupported modules
    if [[ "$base" == "example.d" ]]; then
        continue
    fi
    modules+="$f "
done

# Always include the interpreter even if it was flagged as unsupported
modules+="src/interpreter.d"

echo "Compiling modules:" $modules
# Add the src directory to the import path so the compiler can locate
# modules such as `dircolors` which live under src/ while declaring
# a simple module name.
ldc2 -betterC --nodefaultlib -I=. -Isrc -mtriple=x86_64-pc-linux-gnu $modules -of=interpreter
