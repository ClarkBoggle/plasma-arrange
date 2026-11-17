/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import org.kde.plasma.private.containmentlayoutmanager as ContainmentLayoutManager

// Arranging the desktop widgets on grids, while the desktop is in edit mode.
//
// - Shortcuts (Icon widgets) snap to the shortcut grid: as wide as a cell, with
//   a fixed icon size, centered in their cell.
// - The other widgets (plasmoids) snap to the plasmoid grid and keep their size.
// - Only the kind of widget of the tab shown in the grid panel can be moved.
//
// The applets layout cannot do this itself: it rounds positions and sizes to
// whole cells and ignores screen edges. So it is given 1 px cells (see main.qml)
// and all the snapping is done here, through the hooks called by the applet
// containers. This item also draws the grid, behind the widgets.
Item {
    id: grid

    required property ContainmentLayoutManager.AppletsLayout appletsLayout

    // Grid mode: the desktop is in edit mode
    property bool active: false
    // The Plasmoids tab is shown in the grid panel (otherwise the Shortcuts tab)
    property bool plasmoidsTab: false

    // A widget is being moved (the applets layout then uses huge cells, see main.qml)
    readonly property bool movingWidget: draggedItem !== null

    readonly property var config: Plasmoid.configuration

    // Grid of the tab shown
    GridLines {
        anchors.fill: parent
        visible: grid.active
        cellWidth: grid.plasmoidsTab ? grid.config.gridPlasmoidCellWidth : grid.config.gridCellWidth
        cellHeight: grid.plasmoidsTab ? grid.config.gridPlasmoidCellHeight : grid.config.gridCellHeight
    }

    // --- Widgets ---------------------------------------------------------

    // The applet containers of the layout (its other children are the placeholder,
    // the folder view layer and this item)
    function widgets(): var {
        return Array.from(appletsLayout.children).filter(item => item.applet);
    }

    function isShortcut(item: Item): bool {
        return item.applet?.plasmoid.pluginName === "org.kde.plasma.icon";
    }

    // In grid mode, the widgets of the other tab are locked: no handles, no clicks
    function isLocked(item: Item): bool {
        return active && isShortcut(item) === plasmoidsTab;
    }

    function setGeometry(item: Item, geometry: rect): void {
        item.x = geometry.x;
        item.y = geometry.y;
        item.width = geometry.width;
        item.height = geometry.height;
    }

    // Shows the placeholder exactly there (showPlaceHolderAt() would round it to whole cells)
    function showPlaceHolder(geometry: rect): void {
        setGeometry(appletsLayout.placeHolder, geometry);
        appletsLayout.placeHolder.opacity = 1;
    }

    // Saves the widgets geometry once the move animations are over
    function saveLater(): void {
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: Kirigami.Units.longDuration
        onTriggered: grid.appletsLayout.save()
    }

    // Nearest grid line (shifted by offset), or the right/bottom edge (max) if it
    // is closer. The grid starts at the left/top edge, so no snapping is needed there.
    function snap(position: real, offset: real, cellSize: real, max: real): real {
        const onGrid = Math.round((position - offset) / cellSize) * cellSize + offset;
        if (config.gridSnapToEdges && max - position < Math.abs(position - onGrid)) {
            return max;
        }
        return Math.max(0, Math.min(onGrid, max));
    }

    // --- Shortcuts -------------------------------------------------------

    // The Icon widget gives its icon the frame width × (frame height minus the name).
    // A frame exactly as tall as the icon plus its own name keeps the icon at the
    // chosen size, centered, whatever the frame width and the name length.
    function shortcutSize(title: string, width: real, iconSize: real): size {
        nameMeasure.width = width;
        nameMeasure.text = title;
        return Qt.size(width, iconSize + nameMeasure.implicitHeight);
    }

    // Horizontal offset of a shortcut of this width, centered on its cell
    // (negative if the shortcut is wider than the cell: it overflows on both sides)
    function shortcutOffsetX(width: real, cellWidth: real): real {
        return Math.round((cellWidth - width) / 2);
    }

    // Vertical offset of a shortcut, centered on its cell as if its name took 2 lines:
    // the same for every shortcut, so that all icons of a row are aligned
    function shortcutOffsetY(iconSize: real, cellHeight: real): real {
        return Math.round((cellHeight - iconSize - twoLinesName.implicitHeight) / 2);
    }

    // Hidden labels, set like the shortcut name: to measure a name at a given width,
    // and the height of a 2 lines name
    PlasmaExtras.ShadowedLabel {
        id: nameMeasure
        visible: false
        maximumLineCount: 2
    }

    PlasmaExtras.ShadowedLabel {
        id: twoLinesName
        visible: false
        text: "X\nX"
    }

    // Changes the shortcut grid and icon size. Every shortcut takes its new size,
    // staying centered in the same column and row.
    // Shortcuts stuck to the right or bottom screen edge stay stuck to it.
    function setShortcutGrid(cellWidth: int, cellHeight: int, iconSize: int): void {
        const oldCellWidth = config.gridCellWidth;
        const oldCellHeight = config.gridCellHeight;
        const oldIconSize = config.gridIconSize;

        config.gridCellWidth = cellWidth;
        config.gridCellHeight = cellHeight;
        config.gridIconSize = iconSize;

        for (const item of widgets().filter(isShortcut)) {
            const onRightEdge = Math.abs(item.x + item.width - appletsLayout.width) < 1;
            const onBottomEdge = Math.abs(item.y + item.height - appletsLayout.height) < 1;
            const column = Math.round((item.x - shortcutOffsetX(item.width, oldCellWidth)) / oldCellWidth);
            const row = Math.round((item.y - shortcutOffsetY(oldIconSize, oldCellHeight)) / oldCellHeight);
            const size = shortcutSize(item.applet.plasmoid.title, cellWidth, iconSize);

            const maxX = appletsLayout.width - size.width;
            const maxY = appletsLayout.height - size.height;
            const x = onRightEdge ? maxX : Math.max(0, Math.min(column * cellWidth + shortcutOffsetX(size.width, cellWidth), maxX));
            const y = onBottomEdge ? maxY : Math.max(0, Math.min(row * cellHeight + shortcutOffsetY(iconSize, cellHeight), maxY));
            setGeometry(item, Qt.rect(x, y, size.width, size.height));
        }
        saveLater();
    }

    // Every shortcut gets its size again, centered in its cell
    function refitShortcuts(): void {
        setShortcutGrid(config.gridCellWidth, config.gridCellHeight, config.gridIconSize);
    }

    // After a shortcut drop: once the drop animation is over, as positions are read
    // from the shortcuts
    Timer {
        id: refitTimer
        interval: Kirigami.Units.longDuration
        onTriggered: grid.refitShortcuts()
    }

    // Largest icon size keeping every shortcut inside its cell: not wider than the
    // cell, and not taller than the cell with the tallest name (at the cell width)
    function largestIconSize(cellWidth: real, cellHeight: real): int {
        let nameHeight = 0;
        for (const item of widgets().filter(isShortcut)) {
            nameHeight = Math.max(nameHeight, shortcutSize(item.applet.plasmoid.title, cellWidth, 0).height);
        }
        return Math.floor(Math.min(cellWidth, cellHeight - nameHeight));
    }

    // Height of the tallest shortcut: the shortcut cells cannot be lower
    function tallestShortcutHeight(): real {
        return Math.max(0, ...widgets().filter(isShortcut).map(item => item.height));
    }

    // --- Plasmoids -------------------------------------------------------

    // Geometry of a plasmoid with its edges snapped to the plasmoid grid
    // (or to the right/bottom screen edge), at least one cell large
    function snappedPlasmoidGeometry(item: Item): rect {
        const cellWidth = config.gridPlasmoidCellWidth;
        const cellHeight = config.gridPlasmoidCellHeight;
        const left = snap(item.x, 0, cellWidth, appletsLayout.width);
        const top = snap(item.y, 0, cellHeight, appletsLayout.height);
        const right = Math.max(left + cellWidth, snap(item.x + item.width, 0, cellWidth, appletsLayout.width));
        const bottom = Math.max(top + cellHeight, snap(item.y + item.height, 0, cellHeight, appletsLayout.height));
        return Qt.rect(left, top, right - left, bottom - top);
    }

    function snapAllPlasmoids(): void {
        for (const item of widgets().filter(item => !isShortcut(item))) {
            setGeometry(item, snappedPlasmoidGeometry(item));
        }
        saveLater();
    }

    // --- Moving a widget (hooks called by the applet containers) ---------

    property Item draggedItem: null
    property size sizeBeforeDrag
    property point dragPosition // position while dragged, before any snapping
    property bool dragged: false

    // Where a widget dropped at this position goes: shortcuts get the shortcut size,
    // centered on the nearest cell; plasmoids keep their size, on the nearest
    // plasmoid grid lines; both stick to the right/bottom edge if it is closer
    function dropGeometry(item: Item, position: point): rect {
        if (isShortcut(item)) {
            const size = shortcutSize(item.applet.plasmoid.title, config.gridCellWidth, config.gridIconSize);
            const x = snap(position.x, shortcutOffsetX(size.width, config.gridCellWidth),
                           config.gridCellWidth, appletsLayout.width - size.width);
            const y = snap(position.y, shortcutOffsetY(config.gridIconSize, config.gridCellHeight),
                           config.gridCellHeight, appletsLayout.height - size.height);
            return Qt.rect(x, y, size.width, size.height);
        }
        const x = snap(position.x, 0, config.gridPlasmoidCellWidth, appletsLayout.width - sizeBeforeDrag.width);
        const y = snap(position.y, 0, config.gridPlasmoidCellHeight, appletsLayout.height - sizeBeforeDrag.height);
        return Qt.rect(x, y, sizeBeforeDrag.width, sizeBeforeDrag.height);
    }

    function widgetDragActiveChanged(item: Item): void {
        if (item.dragActive) {
            if (active) {
                draggedItem = item;
                sizeBeforeDrag = Qt.size(item.width, item.height);
                dragged = false;
            }
            return;
        }
        if (item !== draggedItem) {
            return;
        }
        // The layout has just placed the widget: put it where the placeholder showed
        if (dragged) {
            setGeometry(item, dropGeometry(item, dragPosition));
            saveLater();
            if (isShortcut(item)) {
                refitTimer.restart();
            }
        }
        draggedItem = null;
    }

    function widgetMoved(item: Item, position: point): void {
        if (item !== draggedItem) {
            return;
        }
        dragPosition = position;
        dragged = true;
        showPlaceHolder(dropGeometry(item, position));
    }

    // --- Resizing a plasmoid with its handles ------------------------------
    // The placeholder shows the snapped size during the resize, and the snapped size
    // is applied once, when the handle is released: snapping at every mouse move
    // would resize the plasmoid twice per move, which is slow and jerky.

    property Item resizedItem: null

    function widgetResized(item: Item): void {
        if (!active || isShortcut(item) || item.dragActive || !item.editMode || !resizeHandlePressed(item)) {
            return;
        }
        resizedItem = item;
        showPlaceHolder(snappedPlasmoidGeometry(item));
        resizeEndTimer.start();
    }

    function resizeHandlePressed(item: Item): bool {
        return (item.configOverlayItem?.children ?? []).some(child => child.resizeCorner !== undefined && child.pressed);
    }

    // Waits for the handle to be released
    Timer {
        id: resizeEndTimer
        interval: 50
        repeat: true
        onTriggered: {
            const item = grid.resizedItem;
            if (item && grid.resizeHandlePressed(item)) {
                return;
            }
            stop();
            if (item) {
                grid.setGeometry(item, grid.snappedPlasmoidGeometry(item));
                grid.appletsLayout.hidePlaceHolder();
                grid.saveLater();
            }
            grid.resizedItem = null;
        }
    }

    // --- Cancel ----------------------------------------------------------

    // Layout when grid mode started: geometry of every widget (by applet id) and grid settings
    property var savedLayout: null
    readonly property var savedSettings: ["gridCellWidth", "gridCellHeight", "gridIconSize",
                                          "gridPlasmoidCellWidth", "gridPlasmoidCellHeight"]

    onActiveChanged: {
        if (!active) {
            return;
        }
        const geometries = {};
        for (const item of widgets()) {
            geometries[item.applet.plasmoid.id] = Qt.rect(item.x, item.y, item.width, item.height);
        }
        const settings = {};
        for (const key of savedSettings) {
            settings[key] = config[key];
        }
        savedLayout = { geometries, settings };
    }

    // Puts every widget back where it was when grid mode started, with the grid
    // settings of that time
    function restoreSavedLayout(): void {
        if (!savedLayout) {
            return;
        }
        for (const item of widgets()) {
            const geometry = savedLayout.geometries[item.applet.plasmoid.id];
            if (geometry) {
                setGeometry(item, geometry);
            }
        }
        for (const key in savedLayout.settings) {
            config[key] = savedLayout.settings[key];
        }
        saveLater();
    }
}
