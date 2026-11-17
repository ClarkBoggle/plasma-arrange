#!/usr/bin/env bash
# Uninstalls plasma-arrange: removes the link made by install.sh, so Plasma
# uses the system desktop package again, and reloads the desktop.
# Widget positions and grid settings stay in the Plasma configuration.
set -euo pipefail

LINK=$HOME/.local/share/plasma/plasmoids/org.kde.desktopcontainment

if [ -L "$LINK" ]; then
    rm "$LINK"
    systemctl --user restart plasma-plasmashell
    echo "Uninstalled: Plasma uses the system desktop package again (desktop reloaded)."
elif [ -e "$LINK" ]; then
    echo "$LINK is not a link made by install.sh: left untouched." >&2
    exit 1
else
    echo "Not installed (no link at $LINK)."
fi
