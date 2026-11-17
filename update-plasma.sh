#!/usr/bin/env bash
# Updates our copy of the desktop package after a Plasma update.
#
# The "upstream" branch holds the system package untouched, one Plasma version
# per commit. This script commits the current system package there, then merges
# it into the current branch: git thus applies our changes again on the new
# version, and reports the conflicts if there are any.
set -euo pipefail

SYSTEM_PACKAGE=/usr/share/plasma/plasmoids/org.kde.desktopcontainment

cd "$(dirname "$0")"

if [ -n "$(git status --porcelain)" ]; then
    echo "The repository has uncommitted changes: commit them first." >&2
    exit 1
fi

version=$(plasmashell --version | awk '{ print $2 }')

# 1. The current system package, committed to the upstream branch
#    (in a temporary working tree, without touching the current branch)
worktree=$(mktemp -d)
trap 'git worktree remove --force "$worktree"' EXIT
git worktree add --quiet "$worktree" upstream

rm -rf "$worktree/package"
cp -r "$SYSTEM_PACKAGE" "$worktree/package"
git -C "$worktree" add --all package

if git -C "$worktree" diff --cached --quiet; then
    echo "The system package has not changed since the last update: nothing to do."
    exit 0
fi
git -C "$worktree" commit --quiet -m "org.kde.desktopcontainment package of Plasma $version (unmodified)"
git tag "plasma-$version" upstream

# 2. Our changes applied again on the new version
if ! git merge --no-edit -m "Update to the package of Plasma $version" upstream; then
    echo
    echo "Conflicts between our changes and the new Plasma version." >&2
    echo "Resolve them (see git status), then: git commit" >&2
    echo "then: systemctl --user restart plasma-plasmashell" >&2
    exit 1
fi

# 3. Reload the desktop with the new version
systemctl --user restart plasma-plasmashell
echo "Package updated to Plasma $version, desktop reloaded."
