#!/usr/bin/env bash
# Install the custom D-based shell as a login shell
set -e

# Determine target system and build accordingly
system=${1:-${SYSTEM:-custom}}
./build_full.sh "$system"

# Determine install destination
DEST="${PREFIX:-/usr/local/bin}"
TARGET="$DEST/dshell"

# Copy the built interpreter to the destination
sudo install -m 755 interpreter "$TARGET"

# Add the shell to /etc/shells if it is not already present
if ! grep -qx "$TARGET" /etc/shells; then
  echo "$TARGET" | sudo tee -a /etc/shells > /dev/null
fi

echo "Installed shell to $TARGET"
echo "Use 'chsh -s $TARGET' to set it as your login shell."
