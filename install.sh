#!/usr/bin/env bash
# Installs plasma-arrange for the current user: builds the translations, copies
# our package to ~/.local/share/plasma/plasmoids/org.kde.desktopcontainment
# (it then replaces the system desktop package), and reloads the desktop.
# The system is never modified. Run it again after each change to package/.
# Uninstall: ./uninstall.sh
set -euo pipefail

SYSTEM_PACKAGE=/usr/share/plasma/plasmoids/org.kde.desktopcontainment
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

# A merge of a new Plasma version is not finished (conflicts): the package would
# break the desktop
if git rev-parse --quiet --verify MERGE_HEAD > /dev/null || [ -n "$(git ls-files --unmerged)" ]; then
    echo "A merge is in progress: resolve the conflicts and commit first (see git status)." >&2
    exit 1
fi

# System package changed since ours was last merged with it (Plasma update, even
# without a new version number): update first (update-plasma.sh merges the new
# system package, then runs this script again)
upstream=$(mktemp -d)
trap 'rm -rf "$upstream"' EXIT
git archive upstream package | tar -x -C "$upstream"
if ! diff -rq "$upstream/package" "$SYSTEM_PACKAGE" > /dev/null; then
    echo "The system desktop package has changed: running ./update-plasma.sh first."
    rm -rf "$upstream"
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
