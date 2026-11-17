#!/usr/bin/env bash
# Uninstalls plasma-arrange: removes the copy made by install.sh, so Plasma
# uses the system desktop package again, and reloads the desktop.
# Widget positions and grid settings stay in the Plasma configuration.
set -euo pipefail

TARGET=$HOME/.local/share/plasma/plasmoids/org.kde.desktopcontainment
OURS=contents/ui/GridArrange.qml

if [ -L "$TARGET" ] || [ -f "$TARGET/$OURS" ]; then
    rm -rf "$TARGET"
    systemctl --user restart plasma-plasmashell
    echo "Uninstalled: Plasma uses the system desktop package again (desktop reloaded)."
elif [ -e "$TARGET" ]; then
    echo "$TARGET is another copy of the desktop package, not ours: left untouched." >&2
    exit 1
else
    echo "Not installed (nothing at $TARGET)."
fi
