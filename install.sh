#!/usr/bin/env bash
# Installs plasma-arrange for the current user: builds the translations, copies
# our package to ~/.local/share/plasma/plasmoids/org.kde.desktopcontainment
# (it then replaces the system desktop package), and reloads the desktop.
# The system is never modified. Run it again after each change to package/.
# Uninstall: ./uninstall.sh
set -euo pipefail

TARGET=$HOME/.local/share/plasma/plasmoids/org.kde.desktopcontainment
# File only found in our package: tells our installed copy from another one
OURS=contents/ui/GridArrange.qml

cd "$(dirname "$0")"

for tool in xgettext msgmerge msgcat msgunfmt msgfmt; do
    if ! command -v "$tool" > /dev/null; then
        echo "Missing $tool: install gettext first." >&2
        exit 1
    fi
done

# Another copy of the desktop package (not ours): do not overwrite it
if [ -d "$TARGET" ] && [ ! -L "$TARGET" ] && [ ! -f "$TARGET/$OURS" ]; then
    echo "$TARGET holds another copy of the desktop package: move it away first." >&2
    exit 1
fi

# Plasma updated since our package was last merged with the system one: update
# first (update-plasma.sh merges the new system package, then runs this script again)
version=$(plasmashell --version | awk '{ print $2 }')
if ! git rev-parse --quiet --verify "refs/tags/plasma-$version" > /dev/null; then
    echo "Plasma $version is not merged yet: running ./update-plasma.sh first."
    exec ./update-plasma.sh
fi

./build-translations.sh

# New copy next to the old one, then swapped (old copy or old link removed)
mkdir -p "$(dirname "$TARGET")"
rm -rf "$TARGET.new"
cp -r package "$TARGET.new"
rm -rf "$TARGET"
mv "$TARGET.new" "$TARGET"
echo "Installed in $TARGET"

# Start limit of the service (3 per minute) reset: several installs in a row
# would otherwise leave the desktop stopped
systemctl --user reset-failed plasma-plasmashell 2> /dev/null || true
systemctl --user restart plasma-plasmashell
echo "Desktop reloaded."
