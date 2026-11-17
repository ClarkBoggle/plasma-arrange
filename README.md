# plasma-arrange

Arrange the widgets of the KDE Plasma desktop on grids.

In desktop edit mode, a grid is drawn and an **Arrange Desktop** panel appears:

- **Shortcuts** tab: shortcuts (*Icon* widgets) snap to a grid of cells, all with
  the same icon size, their icons aligned along each row.
- **Plasmoids** tab: the other widgets snap to their own grid, when moved or
  resized; *Snap to Grid* aligns all of them at once.
- **Save** keeps the changes; **Cancel** puts every widget and setting back as
  they were when entering edit mode.

## Requirements

- KDE Plasma 6.8 (made and tested with 6.8.2, on Wayland)
- `gettext` (to build the translations)
- Plasma started by systemd (`plasma-plasmashell` user service, the default)

## Installation

```sh
git clone https://github.com/ClarkBoggle/plasma-arrange.git
cd plasma-arrange
./install.sh
```

`install.sh` builds the translations, copies `package/` to
`~/.local/share/plasma/plasmoids/org.kde.desktopcontainment` and reloads the
desktop. Nothing is changed outside your home folder.

This copy **replaces the system desktop package** (`org.kde.desktopcontainment`,
the *Desktop* layout) for your user only: it is the full Plasma package with the
grid arrangement added. Folder View desktops are not affected by the grids.

Run `./install.sh` again after any change to `package/`.

## Uninstallation

```sh
./uninstall.sh
```

Removes the installed copy and reloads the desktop: Plasma uses its own package
again. Widget positions and grid settings stay in the Plasma configuration.

Both scripts leave alone any other copy of the desktop package found in
`~/.local/share/plasma/plasmoids/` (they recognize theirs by
`contents/ui/GridArrange.qml`).

## After a Plasma update

Since the package is a modified copy of Plasma's, it must follow Plasma's
updates. After updating Plasma, from the cloned repository:

```sh
./update-plasma.sh
```

It takes the new system package, applies our changes to it again (git merge
from the `upstream` branch, which holds the unmodified Plasma packages) and
reinstalls. If our changes conflict with the new version, it stops: resolve the
conflicts, `git commit`, then `./install.sh`.

## Files

`package/` is a copy of `/usr/share/plasma/plasmoids/org.kde.desktopcontainment`
from Plasma 6.8.2 (tag `plasma-6.8.2`). Compared to it:

**Added**

| File | Role |
|---|---|
| `package/contents/ui/GridArrange.qml` | Grid logic: snapping, shortcut sizes, saving and restoring the layout; draws the grid |
| `package/contents/ui/GridPanel.qml` | The *Arrange Desktop* panel |
| `package/contents/ui/GridLines.qml` | Drawing of a grid |
| `po/template.pot`, `po/fr.po` | Strings to translate, French translation |
| `install.sh`, `uninstall.sh` | Installation, uninstallation |
| `build-translations.sh` | Builds the translations (called by `install.sh`) |
| `update-plasma.sh` | Update after a Plasma update |

**Modified**

| File | Change |
|---|---|
| `package/contents/ui/main.qml` | About 60 lines, marked *Grid arrangement*: 1 px layout cells (the snapping is done by `GridArrange`), hooks on the widget containers (move, resize, lock), the `GridArrange` and `GridPanel` instances |
| `package/contents/config/main.xml` | The `grid*` settings |

**Generated** (not in git): `package/contents/locale/`, the translation
catalogs, holding Plasma's desktop translations plus ours.

All the other files of `package/` are Plasma's, unchanged.

To see every change: `git diff plasma-6.8.2 main -- package`

## License

The package is derived from Plasma's desktop containment, licensed under the
GPL (version 2 or later).
