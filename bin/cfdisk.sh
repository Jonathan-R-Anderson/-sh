#!/usr/bin/env sh
DIR="$(dirname "$0")/.."
exec "$DIR/interpreter" "cfdisk $*"
