#!/usr/bin/env bash
# Renders the pictures of the README (in the folder above this one, on the
# "assets" branch) from the scenes of this folder, offscreen, with the real
# GridPanel.qml and GridLines.qml of a checkout of the main branch.
# Needs qml6 and Python with Pillow.
# Usage: scenes/render.sh <path of plasma-arrange, main branch>
set -euo pipefail

REPO=$(realpath "${1:?usage: $0 <path of plasma-arrange, main branch>}")
cd "$(dirname "$0")"
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

UI=$REPO/package/contents/ui
cp desktop.qml panel.qml fake.js "$BUILD/"
cp "$UI/GridLines.qml" "$BUILD/"
# The panel without Plasma: fake settings, no translation
sed -e '/^import org.kde.plasma.plasmoid$/c import "fake.js" as Fake' \
    -e 's/Plasmoid\.configuration/Fake.configuration/g' \
    -e 's/i18nc(/Fake.i18nc(/g' \
    "$UI/GridPanel.qml" > "$BUILD/GridPanel.qml"

# Wallpaper of the desktop (Plasma's default, Next), and blurred around it
python3 - "$BUILD" <<'EOF'
import sys
from PIL import Image, ImageFilter, ImageEnhance
build = sys.argv[1]
image = Image.open("/usr/share/wallpapers/Next/contents/images_dark/5120x2880.png").convert("RGB")
image = image.resize((1920, 1080), Image.LANCZOS)
image.save(f"{build}/wallpaper.png")
blurred = image.filter(ImageFilter.GaussianBlur(40))
ImageEnhance.Brightness(blurred).enhance(0.55).save(f"{build}/wallpaper-blurred.png")
EOF

export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=kde
render() { # scene, output, extra arguments
    qml6 "$BUILD/$1" -- "$BUILD/$2" "${@:3}" 2>&1 | grep -v '^qml: ' || true
}
render desktop.qml shortcuts.png shortcuts
render desktop.qml plasmoids.png plasmoids
QT_SCALE_FACTOR=2 render panel.qml panel.png

python3 - "$BUILD" <<'EOF'
import sys
from PIL import Image
build = sys.argv[1]
for name in ("shortcuts", "plasmoids"):
    Image.open(f"{build}/{name}.png").convert("RGB").save(f"../desktop-{name}.jpg", quality=90)
Image.open(f"{build}/panel.png").save("../panel.png")
EOF
echo "Rendered: desktop-shortcuts.jpg, desktop-plasmoids.jpg, panel.png"
