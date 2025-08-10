#!/usr/bin/env bash
set -euo pipefail
DC="${DC:-dmd}"

./build_full.sh
install -m 0755 ./interpreter /usr/local/bin/dshell

# ensure login shell list
grep -qxF "/usr/local/bin/dshell" /etc/shells || echo "/usr/local/bin/dshell" | sudo tee -a /etc/shells
echo "Installed /usr/local/bin/dshell"
