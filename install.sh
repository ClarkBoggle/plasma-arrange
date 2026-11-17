#!/usr/bin/env bash
# Installs plasma-arrange for the current user: builds the translations, links
# ~/.local/share/plasma/plasmoids/org.kde.desktopcontainment to our package
# (it then replaces the system desktop package), and reloads the desktop.
# The system is never modified.
#
#   ./install.sh             install (or repair the link after moving the folder)
#   ./install.sh --uninstall remove the link: Plasma uses the system package again
set -euo pipefail

LINK=$HOME/.local/share/plasma/plasmoids/org.kde.desktopcontainment

cd "$(dirname "$0")"
package=$(pwd)/package

reload() {
    systemctl --user restart plasma-plasmashell
    echo "Desktop reloaded."
}

if [ "${1:-}" = "--uninstall" ]; then
    if [ -L "$LINK" ]; then
        rm "$LINK"
        echo "Uninstalled: Plasma uses the system desktop package again."
        reload
    else
        echo "Not installed (no link at $LINK)."
    fi
    exit 0
fi

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
reload
