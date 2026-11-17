#!/usr/bin/env bash
# Met à jour notre copie du paquet du bureau après une mise à jour de Plasma.
#
# La branche « upstream » contient le paquet système tel quel, une version de
# Plasma par commit. Ce script y ajoute le paquet système actuel, puis le fusionne
# dans la branche courante : git réapplique ainsi nos modifications sur la
# nouvelle version, et signale les conflits s'il y en a.
set -euo pipefail

SYSTEM_PACKAGE=/usr/share/plasma/plasmoids/org.kde.desktopcontainment

cd "$(dirname "$0")"

if [ -n "$(git status --porcelain)" ]; then
    echo "Le dépôt a des modifications non commitées : commite-les d'abord." >&2
    exit 1
fi

version=$(plasmashell --version | awk '{ print $2 }')

# 1. Le paquet système actuel, commité dans la branche upstream
#    (dans un dossier de travail temporaire, sans toucher à la branche courante)
worktree=$(mktemp -d)
trap 'git worktree remove --force "$worktree"' EXIT
git worktree add --quiet "$worktree" upstream

rm -rf "$worktree/package"
cp -r "$SYSTEM_PACKAGE" "$worktree/package"
git -C "$worktree" add --all package

if git -C "$worktree" diff --cached --quiet; then
    echo "Le paquet système n'a pas changé depuis la dernière mise à jour : rien à faire."
    exit 0
fi
git -C "$worktree" commit --quiet -m "Paquet org.kde.desktopcontainment de Plasma $version (non modifié)"
git tag "plasma-$version" upstream

# 2. Nos modifications réappliquées sur la nouvelle version
if ! git merge --no-edit -m "Passage au paquet de Plasma $version" upstream; then
    echo
    echo "Conflits entre nos modifications et la nouvelle version de Plasma." >&2
    echo "Les résoudre (voir git status), puis : git commit" >&2
    echo "puis : systemctl --user restart plasma-plasmashell" >&2
    exit 1
fi

# 3. Recharger le bureau avec la nouvelle version
systemctl --user restart plasma-plasmashell
echo "Paquet mis à jour vers Plasma $version, bureau rechargé."
