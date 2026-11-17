#!/usr/bin/env bash
# Builds the translations of the desktop package, KDE style: po/<lang>.po
# holds our strings, po/template.pot is extracted from our QML files.
#
# Our package replaces the system one, translations included: each catalog
# built here holds the system translations of the desktop containment plus
# ours, in package/contents/locale/<lang>/LC_MESSAGES/.
set -euo pipefail

DOMAIN=plasma_applet_org.kde.desktopcontainment

cd "$(dirname "$0")"

# Template of our strings (new strings to translate)
xgettext --from-code=UTF-8 --language=JavaScript --add-comments=i18n \
    --keyword=i18n:1 --keyword=i18nc:1c,2 --keyword=i18np:1,2 --keyword=i18ncp:1c,2,3 \
    --package-name=plasma-arrange --output=po/template.pot \
    package/contents/ui/Grid*.qml

for po in po/*.po; do
    lang=$(basename "$po" .po)
    # Our translations follow the template (new strings appear untranslated)
    msgmerge --quiet --update --backup=none "$po" po/template.pot

    # System translations of the desktop containment, plus ours
    system_catalog=/usr/share/locale/$lang/LC_MESSAGES/$DOMAIN.mo
    output=package/contents/locale/$lang/LC_MESSAGES/$DOMAIN.mo
    mkdir -p "$(dirname "$output")"
    if [ -f "$system_catalog" ]; then
        msgcat --use-first "$po" <(msgunfmt "$system_catalog") | msgfmt --output-file="$output" -
    else
        msgfmt --output-file="$output" "$po"
    fi
    echo "$lang: $(msgfmt --statistics --output-file=/dev/null "$po" 2>&1)"
done
