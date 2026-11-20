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

# Shallow clone: the whole history is needed to merge
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    git fetch --quiet --unshallow origin
fi
# Fresh, shallow or single-branch clone (e.g. git clone --depth 1): the local
# upstream branch is created, fetched if needed
if ! git rev-parse --quiet --verify refs/heads/upstream > /dev/null; then
    if git rev-parse --quiet --verify refs/remotes/origin/upstream > /dev/null; then
        git branch --quiet --track upstream origin/upstream
    else
        git fetch --quiet origin "refs/heads/upstream:refs/heads/upstream" "refs/tags/plasma-*:refs/tags/plasma-*"
    fi
fi

# No git identity configured: the commits of the update are made under a
# neutral name (git would refuse them otherwise)
if ! git var GIT_AUTHOR_IDENT > /dev/null 2>&1; then
    export GIT_AUTHOR_NAME="plasma-arrange update" GIT_AUTHOR_EMAIL="plasma-arrange@localhost"
    export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
    commit="git -c user.name='$GIT_AUTHOR_NAME' -c user.email=$GIT_AUTHOR_EMAIL commit"
else
    commit="git commit"
fi

# 1. The current system package, committed to the upstream branch
#    (in a temporary working tree, without touching the current branch)
worktree=$(mktemp -d)
trap 'git worktree remove --force "$worktree"' EXIT
git worktree add --quiet "$worktree" upstream

rm -rf "$worktree/package"
cp -r "$SYSTEM_PACKAGE" "$worktree/package"
git -C "$worktree" add --all package

if git -C "$worktree" diff --cached --quiet; then
    echo "The system package has not changed since the last update: nothing to merge."
    # (a new Plasma version with the same package is tagged too)
    git tag --force "plasma-$version" upstream > /dev/null
    exit 0
fi
git -C "$worktree" commit --quiet -m "org.kde.desktopcontainment package of Plasma $version (unmodified)"
# (--force: the package can change without a new version number)
git tag --force "plasma-$version" upstream > /dev/null

# 2. Our changes applied again on the new version
if ! git merge --no-edit -m "Update to the package of Plasma $version" upstream; then
    # The installed copy is made for the previous Plasma version: removed, so
    # that Plasma uses its own, up to date, package until the conflicts are resolved
    echo
    echo "Conflicts between our changes and the new Plasma version." >&2
    ./uninstall.sh || true
    echo "Resolve the conflicts (see git status), then: $commit" >&2
    echo "then: ./install.sh" >&2
    exit 1
fi

# 3. Installed again: translations rebuilt with the new system catalogs,
#    package copied, desktop reloaded
./install.sh
echo "Package updated to Plasma $version."
