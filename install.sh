#!/usr/bin/env bash
# Installs plasma-arrange for the current user: builds the translations, links
# ~/.local/share/plasma/plasmoids/org.kde.desktopcontainment to our package
# (it then replaces the system desktop package), and reloads the desktop.
# The system is never modified. Run it again after moving or renaming the
# folder (the link holds an absolute path). Uninstall: ./uninstall.sh
set -euo pipefail

LINK=$HOME/.local/share/plasma/plasmoids/org.kde.desktopcontainment

cd "$(dirname "$0")"
package=$(pwd)/package

for tool in xgettext msgmerge msgcat msgunfmt msgfmt; do
    if ! command -v "$tool" > /dev/null; then
        echo "Missing $tool: install gettext first." >&2
        exit 1
    fi
done

# A real folder there is another copy of the package: do not overwrite it
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
    echo "$LINK exists and is not a link (another copy of the desktop package?)." >&2
    echo "Move it away first." >&2
    exit 1
fi

# A link to another place (another project, or this folder before it was moved)
if [ -L "$LINK" ] && [ "$(readlink "$LINK")" != "$package" ]; then
    echo "Replacing the link to $(readlink "$LINK")"
fi

./build-translations.sh
mkdir -p "$(dirname "$LINK")"
ln -sfn "$package" "$LINK"
echo "Installed: $LINK -> $package"
systemctl --user restart plasma-plasmashell
echo "Desktop reloaded."
