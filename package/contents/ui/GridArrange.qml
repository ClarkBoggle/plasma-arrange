/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.draganddrop as DragDrop

import org.kde.plasma.private.containmentlayoutmanager as ContainmentLayoutManager

import "GridDrag.js" as GridDrag
import "GridMath.js" as GridMath

// Arranging the desktop widgets on grids, while the desktop is in edit mode.
//
// - Shortcuts (Icon widgets) snap to the shortcut grid: as wide as a cell, with
//   a fixed icon size, centered in their cell.
// - The other widgets (plasmoids) snap to the plasmoid grid and keep their size.
// - Shortcuts cannot be resized by hand (they have the size of the grid);
//   plasmoids can, their edges snapped to their grid.
// - Shortcuts do not overlap each other, nor plasmoids each other.
// - Only the kind of widget of the tab shown in the grid panel can be moved;
//   a click on a widget of the other kind shows its tab.
// - Widgets moved to another screen are snapped to the grids of that screen.
// - Only a click selects a widget (shows its handles), not the mouse over it.
// - Moved widgets show no handles, shortcuts no tooltip.
// - Cancel puts back the desktops of all screens.
//
// The applets layout cannot do this itself: it rounds positions and sizes to
// whole cells and ignores screen edges. So it is given 1 px cells (see main.qml)
// and all the snapping is done here, connected to the applet containers.
// This item also draws the grid, behind the widgets.
Item {
    id: grid

    required property ContainmentLayoutManager.AppletsLayout appletsLayout

    // Grid mode: the desktop is in edit mode
    property bool active: false
    // The "Arrange Desktop" panel of this desktop
    required property GridPanel panel
    // The Plasmoids tab is shown in the panel (otherwise the Shortcuts tab)
    readonly property bool plasmoidsTab: panel.plasmoidsTab

    // A widget is being moved, here or from another screen over this desktop
    // (the applets layout then uses huge cells, see main.qml)
    readonly property bool movingWidget: draggedItem !== null || incomingDrag

    readonly property var config: Plasmoid.configuration

    // The panel asks, this item does
    Connections {
        target: grid.panel
        function onShortcutGridChangeRequested(cellWidth: int, cellHeight: int, iconSize: int): void {
            grid.setShortcutGrid(cellWidth, cellHeight, iconSize);
        }
        function onSnapPlasmoidsRequested(): void {
            grid.snapAllPlasmoids();
        }
        function onSnapShortcutsRequested(): void {
            grid.refitShortcuts();
        }
        function onSaveRequested(): void {
            Plasmoid.containment.corona.editMode = false;
        }
        function onCancelRequested(): void {
            grid.restoreSavedLayout();
            Plasmoid.containment.corona.editMode = false;
        }
    }

    Component.onCompleted: {
        panel.tallestShortcutHeight = tallestShortcutHeight;
        panel.largestIconSize = largestIconSize;
        watchWidgets();
        GridDrag.desktops.push(grid);
    }

    Component.onDestruction: {
        GridDrag.desktops = GridDrag.desktops.filter(item => item && item !== grid);
    }

    // Plasmoid grid cell of this desktop if it is the one shown on the screen
    // named screenName, otherwise null. For the panels of plasma-pannel, which
    // size the popups of their widgets on it (see GridDrag.desktops).
    function plasmoidCellOn(screenName: string): var {
        if (Plasmoid.pluginName !== "org.kde.desktopcontainment" || !Plasmoid.isContainment
                || !grid.Window.window || !grid.visible || grid.Screen.name !== screenName) {
            return null;
        }
        return { width: config.gridPlasmoidCellWidth, height: config.gridPlasmoidCellHeight };
    }

    // Grid of the tab shown
    GridLines {
        anchors.fill: parent
        visible: grid.active
        cellWidth: grid.plasmoidsTab ? grid.config.gridPlasmoidCellWidth : grid.config.gridCellWidth
        cellHeight: grid.plasmoidsTab ? grid.config.gridPlasmoidCellHeight : grid.config.gridCellHeight
    }

    // --- Widgets ---------------------------------------------------------

    // The applet containers of the layout that have their applet (its other children
    // are the placeholder, the folder view layer, this item and hoverBlocker)
    function widgets(): var {
        return Array.from(appletsLayout.children).filter(item => item.applet);
    }

    function isShortcut(item: Item): bool {
        return item.applet?.plasmoid.pluginName === "org.kde.plasma.icon";
    }

    // In grid mode, the widgets of the other tab are locked: hoverBlocker takes
    // their clicks, so they are never selected nor moved
    function isLocked(item: Item): bool {
        return active && isShortcut(item) === plasmoidsTab;
    }

    // Each widget tells when it is selected, moved or resized, and when it gets its
    // handles (connected once per widget). All the applet containers are watched,
    // even without their applet yet: a widget coming from another screen gets its
    // container added to the layout first, and its applet only after (no new
    // childrenChanged then).
    property var watchedWidgets: []

    function watchWidgets(): void {
        watchedWidgets = watchedWidgets.filter(item => item); // (destroyed: null)
        const containers = Array.from(appletsLayout.children).filter(item => item.applet !== undefined);
        for (const item of containers) {
            if (!watchedWidgets.includes(item)) {
                watchedWidgets.push(item);
                item.editModeChanged.connect(() => grid.widgetEditModeChanged(item));
                item.dragActiveChanged.connect(() => grid.widgetMovingChanged(item, item.dragActive));
                item.configOverlayItemChanged.connect(() => grid.widgetHandlesChanged(item));
                item.widthChanged.connect(() => grid.widgetResized(item));
                item.heightChanged.connect(() => grid.widgetResized(item));
                item.Drag.dragFinished.connect(action => grid.widgetDragFinished(action));
            }
        }
    }

    Connections {
        target: grid.appletsLayout
        function onChildrenChanged(): void {
            grid.watchWidgets();
        }
    }

    // (also used for the placeholder)
    function setGeometry(item: Item, geometry: rect): void {
        item.x = geometry.x;
        item.y = geometry.y;
        item.width = geometry.width;
        item.height = geometry.height;
        const sliding = putGeometries.filter(put => put.item !== item && isSliding(put));
        sliding.push({ item: item, geometry: geometry, time: Date.now() });
        putGeometries = sliding;
    }

    // A widget slides to the place it is put at (animation in main.qml): its x and
    // y are not there yet. So the geometry it was last put at is kept for the time
    // of the slide ({ item, geometry, time }), and read from here.
    property var putGeometries: []

    function isSliding(put: var): bool {
        return Date.now() - put.time < Kirigami.Units.longDuration;
    }

    function geometryOf(item: Item): rect {
        const put = putGeometries.find(put => put.item === item);
        return put && isSliding(put) ? put.geometry : Qt.rect(item.x, item.y, item.width, item.height);
    }

    // Shows the placeholder on the cells of a widget of this geometry, filling them
    // (showPlaceHolderAt() would round it to whole layout cells): the cell of a
    // shortcut (the one of its center), or the plasmoid grid cells a plasmoid covers
    // (it can end inside a cell, as it keeps its size), within the screen.
    function showPlaceHolder(geometry: rect, shortcut: bool): void {
        let cells;
        if (shortcut) {
            const cellWidth = config.gridCellWidth;
            const cellHeight = config.gridCellHeight;
            const column = Math.floor((geometry.x + geometry.width / 2) / cellWidth);
            const row = Math.floor((geometry.y + geometry.height / 2) / cellHeight);
            cells = Qt.rect(column * cellWidth, row * cellHeight, cellWidth, cellHeight);
        } else {
            const cellWidth = config.gridPlasmoidCellWidth;
            const cellHeight = config.gridPlasmoidCellHeight;
            const left = Math.floor(geometry.x / cellWidth) * cellWidth;
            const top = Math.floor(geometry.y / cellHeight) * cellHeight;
            const right = Math.ceil((geometry.x + geometry.width) / cellWidth) * cellWidth;
            const bottom = Math.ceil((geometry.y + geometry.height) / cellHeight) * cellHeight;
            cells = Qt.rect(left, top, right - left, bottom - top);
        }
        const x = Math.max(0, cells.x);
        const y = Math.max(0, cells.y);
        const width = Math.min(cells.x + cells.width, appletsLayout.width) - x;
        const height = Math.min(cells.y + cells.height, appletsLayout.height) - y;
        setGeometry(appletsLayout.placeHolder, Qt.rect(x, y, width, height));
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
        return GridMath.snap(position, offset, cellSize, max, config.gridSnapToEdges);
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
    // the same for every shortcut, so that all icons of a row are aligned.
    // Never negative: in a cell too low for 2 lines (then every name takes 1 line,
    // the cell being at least as tall as the tallest shortcut), shortcuts start at
    // the top of the cell instead of overflowing above it.
    function shortcutOffsetY(iconSize: real, cellHeight: real): real {
        return Math.max(0, Math.round((cellHeight - iconSize - twoLinesName.implicitHeight) / 2));
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
    // One that would then overlap another goes to the nearest free cell.
    function setShortcutGrid(cellWidth: int, cellHeight: int, iconSize: int): void {
        const oldCellWidth = config.gridCellWidth;
        const oldCellHeight = config.gridCellHeight;
        const oldIconSize = config.gridIconSize;

        config.gridCellWidth = cellWidth;
        config.gridCellHeight = cellHeight;
        config.gridIconSize = iconSize;

        const shortcuts = widgets().filter(isShortcut);
        const geometries = shortcuts.map(item => {
            const old = geometryOf(item);
            const onRightEdge = Math.abs(old.x + old.width - appletsLayout.width) < 1;
            const onBottomEdge = Math.abs(old.y + old.height - appletsLayout.height) < 1;
            const column = Math.round((old.x - shortcutOffsetX(old.width, oldCellWidth)) / oldCellWidth);
            const row = Math.round((old.y - shortcutOffsetY(oldIconSize, oldCellHeight)) / oldCellHeight);
            const size = shortcutSize(item.applet.plasmoid.title, cellWidth, iconSize);

            const maxX = appletsLayout.width - size.width;
            const maxY = appletsLayout.height - size.height;
            const x = onRightEdge ? maxX
                : GridMath.clamp(column * cellWidth + shortcutOffsetX(size.width, cellWidth), maxX);
            const y = onBottomEdge ? maxY
                : GridMath.clamp(row * cellHeight + shortcutOffsetY(iconSize, cellHeight), maxY);
            return Qt.rect(x, y, size.width, size.height);
        });
        // (shortcuts of cells that no longer fit in the screen are all on the last
        // one; a shortcut is as wide as its cell: no horizontal offset)
        const separated = separatedGeometries(geometries, 0, cellWidth,
                                              shortcutOffsetY(iconSize, cellHeight), cellHeight);
        shortcuts.forEach((item, i) => setGeometry(item, separated[i]));
        saveLater();
    }

    // Every shortcut gets its size again, centered in its cell
    function refitShortcuts(): void {
        setShortcutGrid(config.gridCellWidth, config.gridCellHeight, config.gridIconSize);
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

    // Minimum widget size of Plasma's layout, lowered to 16 px for small shortcuts
    // (see main.qml), kept for plasmoids. A new widget gets the size it asks for if
    // larger than the minimum, otherwise the default size: with 16 px, some
    // plasmoids asked for 27 px and stayed that small.
    readonly property real plasmaMinimumItemSize: Kirigami.Units.gridUnit * 3

    // Geometry of a plasmoid with its edges snapped to the plasmoid grid
    // (or to the right/bottom screen edge), at least one cell large
    function snappedPlasmoidGeometry(geometry: rect): rect {
        const cellWidth = config.gridPlasmoidCellWidth;
        const cellHeight = config.gridPlasmoidCellHeight;
        const left = snap(geometry.x, 0, cellWidth, appletsLayout.width);
        const top = snap(geometry.y, 0, cellHeight, appletsLayout.height);
        const right = Math.max(left + cellWidth,
                               snap(geometry.x + geometry.width, 0, cellWidth, appletsLayout.width));
        const bottom = Math.max(top + cellHeight,
                                snap(geometry.y + geometry.height, 0, cellHeight, appletsLayout.height));
        return Qt.rect(left, top, right - left, bottom - top);
    }

    // "Snap to Grid": snaps every plasmoid. One that would then overlap another
    // (rounding can make two plasmoids side by side overlap by a cell) goes to the
    // nearest free place.
    function snapAllPlasmoids(): void {
        const plasmoids = widgets().filter(item => !isShortcut(item));
        const geometries = plasmoids.map(item => snappedPlasmoidGeometry(geometryOf(item)));
        const separated = separatedGeometries(geometries, 0, config.gridPlasmoidCellWidth,
                                              0, config.gridPlasmoidCellHeight);
        plasmoids.forEach((item, i) => setGeometry(item, separated[i]));
        saveLater();
    }

    // --- Moving a widget (main.qml calls widgetMoved()) --------------------

    property Item draggedItem: null
    property size sizeBeforeDrag
    property point dragPosition // position while dragged, before any snapping
    property bool dragged: false // it really moved (not only clicked)
    property bool leaving: false // it is over another screen: main.qml takes it there

    // A widget is moved by a press and hold on it (dragActive) or by the move bar
    // of its handles (see watchMoveBar())
    function widgetMovingChanged(item: Item, moving: bool): void {
        if (moving && active) {
            moveStarted(item);
        } else if (!moving && item === draggedItem) {
            moveEnded(item);
        }
    }

    function moveStarted(item: Item): void {
        draggedItem = item;
        sizeBeforeDrag = Qt.size(item.width, item.height);
        dragged = false;
        leaving = false;
        // For the desktop of another screen, if it is dragged there
        GridDrag.widget = {
            shortcut: isShortcut(item),
            title: item.applet.plasmoid.title,
            width: item.width,
            height: item.height,
            rotation: item.rotation,
            grabX: item.width / 2,
            grabY: item.height / 2,
        };
    }

    // grab: where the mouse holds the widget, in the widget
    function widgetMoved(item: Item, position: point, grab: point): void {
        if (item !== draggedItem) {
            return;
        }
        dragPosition = position;
        dragged = true;
        // (as main.qml finds the desktop under the widget, right after)
        const desktop = appletsLayout.containmentItem;
        const center = item.mapToItem(desktop.parent, grab.x, grab.y);
        const desktopUnder = desktop.containmentItemAt(center.x, center.y);
        leaving = desktopUnder ? desktopUnder.plasmoid !== Plasmoid : false;
        showPlaceHolder(dropGeometry(item, position), isShortcut(item));
        setHandlesShown(item, false);

        // When it reaches another screen, main.qml replaces the widget by its image,
        // held by default by its top left corner: held where it is grabbed instead.
        // The image is taken at the scale of this screen (1.7 on the 4K one) but
        // shown at a scale of 1: brought back to the size of the widget.
        item.Drag.hotSpot = grab;
        item.Drag.imageSourceSize = Qt.size(item.width, item.height);
        if (GridDrag.widget) {
            GridDrag.widget.grabX = grab.x;
            GridDrag.widget.grabY = grab.y;
        }
    }

    function moveEnded(item: Item): void {
        draggedItem = null;
        setHandlesShown(item, true);
        // If it leaves for another screen, main.qml unselects it right after
        moveEndedWidget = item;
        Qt.callLater(() => grid.moveEndedWidget = null);

        if (leaving) {
            return; // (GridDrag.widget is for the desktop it reaches)
        }
        GridDrag.widget = null;
        if (!dragged) {
            return;
        }
        // The layout has just placed it: put where the placeholder showed
        putBack(item, dropGeometry(item, dragPosition));
    }

    // The drag to another screen ended (action: Qt.MoveAction if it was dropped on
    // a desktop, which then cleared GridDrag.widget itself)
    function widgetDragFinished(action: int): void {
        if (action !== Qt.MoveAction) {
            GridDrag.widget = null;
        }
    }

    // Where a widget dropped at this position goes: shortcuts get the shortcut size,
    // centered on the nearest cell; plasmoids keep their size, on the nearest
    // plasmoid grid lines; both stick to the right/bottom edge if it is closer, and
    // do not go over a widget of their kind (see freeGeometry())
    function dropGeometry(item: Item, position: point): rect {
        return dropGeometryOf(isShortcut(item), item.applet.plasmoid.title, sizeBeforeDrag, position, item);
    }

    // The same for a widget known by its kind, its name (shortcut) and its size
    // (plasmoid): a widget coming from another screen (moved: null)
    function dropGeometryOf(shortcut: bool, title: string, plasmoidSize: size, position: point,
                            moved: Item): rect {
        if (shortcut) {
            const size = shortcutSize(title, config.gridCellWidth, config.gridIconSize);
            const offsetX = shortcutOffsetX(size.width, config.gridCellWidth);
            const offsetY = shortcutOffsetY(config.gridIconSize, config.gridCellHeight);
            const x = snap(position.x, offsetX, config.gridCellWidth, appletsLayout.width - size.width);
            const y = snap(position.y, offsetY, config.gridCellHeight, appletsLayout.height - size.height);
            return freeGeometry(Qt.rect(x, y, size.width, size.height), otherWidgets(true, moved),
                                offsetX, config.gridCellWidth, offsetY, config.gridCellHeight);
        }
        const x = snap(position.x, 0, config.gridPlasmoidCellWidth, appletsLayout.width - plasmoidSize.width);
        const y = snap(position.y, 0, config.gridPlasmoidCellHeight, appletsLayout.height - plasmoidSize.height);
        return freeGeometry(Qt.rect(x, y, plasmoidSize.width, plasmoidSize.height), otherWidgets(false, moved),
                            0, config.gridPlasmoidCellWidth, 0, config.gridPlasmoidCellHeight);
    }

    // Widgets of a kind do not overlap: a widget over another one goes to the
    // nearest place on its grid (lines shifted by the offsets), or on the
    // right/bottom edge, where it overlaps none of the others. It stays where it is
    // if it overlaps none, or if there is no such place.
    function freeGeometry(geometry: rect, others: var, offsetX: real, cellWidth: real,
                          offsetY: real, cellHeight: real): rect {
        if (!GridMath.overlapsAny(geometry, others)) {
            return geometry;
        }
        const toEdges = config.gridSnapToEdges;
        const xs = GridMath.gridLines(offsetX, cellWidth, appletsLayout.width - geometry.width, toEdges);
        const ys = GridMath.gridLines(offsetY, cellHeight, appletsLayout.height - geometry.height, toEdges);
        const free = GridMath.nearestFree(geometry, others, xs, ys);
        return free ? Qt.rect(free.x, free.y, geometry.width, geometry.height) : geometry;
    }

    // These geometries, moved so that none overlaps another: of two overlapping
    // ones, the first stays and the other goes to the nearest free place
    function separatedGeometries(geometries: var, offsetX: real, cellWidth: real,
                                 offsetY: real, cellHeight: real): var {
        const placed = [];
        const staying = geometries.map(geometry => {
            const stays = !GridMath.overlapsAny(geometry, placed);
            if (stays) {
                placed.push(geometry);
            }
            return stays;
        });
        return geometries.map((geometry, i) => {
            if (staying[i]) {
                return geometry;
            }
            const free = freeGeometry(geometry, placed, offsetX, cellWidth, offsetY, cellHeight);
            placed.push(free);
            return free;
        });
    }

    // Geometries of the shortcuts or of the plasmoids, but this widget (moved: the
    // widget itself if it is on this desktop, otherwise null). A rotated widget
    // counts for the rectangle around it.
    function otherWidgets(shortcuts: bool, moved: Item): var {
        return widgets().filter(item => isShortcut(item) === shortcuts && item !== moved)
            .map(item => item.rotation === 0 ? geometryOf(item)
                : appletsLayout.mapFromItem(item, Qt.rect(0, 0, item.width, item.height)));
    }

    // A dropped widget slides to its place (animation in main.qml), and the layout
    // places it once more during the slide, elsewhere if it sees no free space there.
    // So it is put at its place now, and again once the slide is over. The same
    // after a plasmoid resize.
    property Item droppedWidget: null
    property rect droppedGeometry

    function putBack(item: Item, geometry: rect): void {
        if (droppedWidget && droppedWidget !== item) {
            setGeometry(droppedWidget, droppedGeometry); // (not waiting for its slide)
        }
        setGeometry(item, geometry);
        droppedWidget = item;
        droppedGeometry = geometry;
        dropEndTimer.restart();
        saveLater();
    }

    Timer {
        id: dropEndTimer
        interval: Kirigami.Units.longDuration
        onTriggered: {
            if (grid.droppedWidget) {
                grid.setGeometry(grid.droppedWidget, grid.droppedGeometry);
                grid.saveLater();
            }
            grid.droppedWidget = null;
        }
    }

    // --- Handles -----------------------------------------------------------
    // Shown around the selected widget: resize handles, and a bar with buttons
    // (rotate, configure, remove) and an area to move the widget.

    // The handles of a widget are created when it is first selected
    function widgetHandlesChanged(item: Item): void {
        removeResizeHandles(item);
        watchResizeHandles(item);
        watchMoveBar(item);
    }

    // The bar next to the handles also moves the widget (a MouseArea dragging it,
    // calling userDrag but without dragActive): the move starts and ends with it.
    // pressedChanged comes after Plasma's onReleased, which places the widget.
    function watchMoveBar(item: Item): void {
        const bar = findMoveBar(item.configOverlayItem, item);
        if (!bar) {
            return;
        }
        bar.pressedChanged.connect(() => grid.widgetMovingChanged(item, bar.pressed));
    }

    // The MouseArea dragging this widget, among the descendants of its handles
    function findMoveBar(handles: Item, item: Item): Item {
        for (const child of handles?.children ?? []) {
            if (child.drag?.target === item) {
                return child;
            }
            const bar = findMoveBar(child, item);
            if (bar) {
                return bar;
            }
        }
        return null;
    }

    // A plasmoid resized with its handles: the placeholder shows its edges snapped
    // to the grid, applied when the handle is released (snapping at every mouse
    // move would be jerky). The handle tells it is released before the layout
    // places the plasmoid: put back after it (see putBack()).
    property Item resizedPlasmoid: null
    property rect geometryBeforeResize

    function watchResizeHandles(item: Item): void {
        for (const handle of item.configOverlayItem?.children ?? []) {
            if (handle.resizeCorner !== undefined) {
                handle.pressedChanged.connect(() => grid.resizeHandlePressedChanged(item, handle.pressed));
            }
        }
    }

    function resizeHandlePressedChanged(item: Item, pressed: bool): void {
        if (!active || isShortcut(item)) {
            return;
        }
        if (pressed) {
            resizedPlasmoid = item;
            geometryBeforeResize = Qt.rect(item.x, item.y, item.width, item.height);
            return;
        }
        resizedPlasmoid = null;
        appletsLayout.hidePlaceHolder();
        const geometry = resizedGeometry(item);
        Qt.callLater(grid.putBack, item, geometry);
    }

    function widgetResized(item: Item): void {
        if (item === resizedPlasmoid) {
            showPlaceHolder(resizedGeometry(item), false);
        }
    }

    // Geometry a plasmoid being resized will get: its edges snapped to the grid,
    // not smaller than Plasma's minimum size (in whole cells), and not over another
    // plasmoid: the edges that were moved come back, cell by cell, until it
    // overlaps none (at worst, to the geometry before the resize).
    function resizedGeometry(item: Item): rect {
        const cellWidth = config.gridPlasmoidCellWidth;
        const cellHeight = config.gridPlasmoidCellHeight;
        const before = geometryBeforeResize;
        const snapped = snappedPlasmoidGeometry(Qt.rect(item.x, item.y, item.width, item.height));
        let left = snapped.x;
        let top = snapped.y;
        let right = snapped.x + snapped.width;
        let bottom = snapped.y + snapped.height;
        // (the handle moves the left or the right edge, the top or the bottom one)
        const leftMoved = Math.abs(item.x - before.x) > 0.5;
        const topMoved = Math.abs(item.y - before.y) > 0.5;

        const minimumWidth = Math.ceil(plasmaMinimumItemSize / cellWidth) * cellWidth;
        const minimumHeight = Math.ceil(plasmaMinimumItemSize / cellHeight) * cellHeight;
        if (right - left < minimumWidth) {
            if (leftMoved) {
                left = right - minimumWidth;
            } else {
                right = left + minimumWidth;
            }
        }
        if (bottom - top < minimumHeight) {
            if (topMoved) {
                top = bottom - minimumHeight;
            } else {
                bottom = top + minimumHeight;
            }
        }

        // Every edge that went outwards comes back by a cell, not further than
        // where it was
        const others = otherWidgets(false, item);
        const beforeRight = before.x + before.width;
        const beforeBottom = before.y + before.height;
        while (GridMath.overlapsAny(Qt.rect(left, top, right - left, bottom - top), others)) {
            if (left >= before.x && top >= before.y && right <= beforeRight && bottom <= beforeBottom) {
                return before; // nothing left to bring back
            }
            if (left < before.x) {
                left = Math.min(before.x, left + cellWidth);
            }
            if (top < before.y) {
                top = Math.min(before.y, top + cellHeight);
            }
            if (right > beforeRight) {
                right = Math.max(beforeRight, right - cellWidth);
            }
            if (bottom > beforeBottom) {
                bottom = Math.max(beforeBottom, bottom - cellHeight);
            }
        }
        return Qt.rect(left, top, right - left, bottom - top);
    }

    // Shortcuts have the size of the shortcut grid: no resize handles
    function removeResizeHandles(item: Item): void {
        if (!isShortcut(item)) {
            return;
        }
        for (const child of item.configOverlayItem?.children ?? []) {
            if (child.resizeCorner !== undefined) {
                child.visible = false;
                child.enabled = false;
            }
        }
    }

    // Handles are hidden while the widget moves
    function setHandlesShown(item: Item, shown: bool): void {
        if (item.configOverlayItem) {
            item.configOverlayItem.opacity = shown ? 1 : 0;
        }
    }

    // --- Moving a widget to another screen ---------------------------------
    // main.qml moves it with a drag and drop: it is removed from the desktop of its
    // screen and added to the other one. That one only gets its applet id, and its
    // placeholder is a small square under the mouse. So the desktop it leaves
    // describes it in GridDrag, and the desktop it reaches shows where it will go,
    // as for a move on the same screen, then puts it there.

    // A widget from another screen is dragged over this desktop (huge layout cells,
    // see movingWidget), and where it would go
    property bool incomingDrag: false
    property var incomingGeometry: null

    function isWidgetDrag(event: var): bool {
        return active && GridDrag.widget !== null
            && event.mimeData.formats.indexOf("text/x-plasmoidinstanceid") !== -1;
    }

    // Shows where the widget from another screen would go (incomingGeometry)
    function incomingDragMoved(event: var): void {
        if (!isWidgetDrag(event)) {
            return;
        }
        const widget = GridDrag.widget;
        // Held by the mouse at the same point as its image (in proportion for a
        // shortcut, which takes the shortcut size of this desktop)
        const size = widget.shortcut
            ? shortcutSize(widget.title, config.gridCellWidth, config.gridIconSize)
            : Qt.size(widget.width, widget.height);
        const position = Qt.point(event.x - widget.grabX * size.width / widget.width,
                                  event.y - widget.grabY * size.height / widget.height);
        incomingGeometry = dropGeometryOf(widget.shortcut, widget.title, size, position, null);
        showPlaceHolder(incomingGeometry, widget.shortcut);
        // Only the kind of widget of the tab shown can be dropped
        panel.showTab(!widget.shortcut);
    }

    // Drop area of the desktop (called after main.qml's handlers)
    Connections {
        target: grid.appletsLayout.parent

        // Over a shortcut (it has its own drop area), each mouse move gives a
        // dragLeave and a dragEnter, no dragMove
        function onDragEnter(event: var): void {
            grid.incomingDrag = grid.isWidgetDrag(event);
            grid.incomingGeometry = null;
            grid.incomingDragMoved(event);
        }

        function onDragMove(event: var): void {
            grid.incomingDragMoved(event);
        }

        // (incomingGeometry is used when the widget is added, right after)
        function onDrop(event: var): void {
            grid.incomingDrag = false;
        }

        // The drag also leaves the desktop when it goes over a shortcut (its own
        // drop area): incomingGeometry is kept, as it can still be dropped there
        function onDragLeave(event: var): void {
            grid.incomingDrag = false;
        }
    }

    Connections {
        target: Plasmoid

        // (the layout creates its container right after)
        function onAppletAdded(applet: var): void {
            GridDrag.desktopOf[applet.id] = Plasmoid.id; // for Cancel
            if (grid.active) {
                // (incomingGeometry may be left from a drag that went elsewhere)
                Qt.callLater(grid.placeAddedWidget, applet.id,
                             GridDrag.widget ? grid.incomingGeometry : null,
                             GridDrag.widget?.rotation ?? 0);
            }
            grid.incomingDrag = false;
            grid.incomingGeometry = null;
            GridDrag.widget = null;
        }
    }

    // A widget added in grid mode is placed by the layout where it was dropped,
    // off the grid. From another screen, it is put where the placeholder showed
    // (geometry), with the rotation it had (its new container has none).
    // Otherwise (created by a drop, for instance), a shortcut gets the shortcut size
    // on the nearest cell, a plasmoid the nearest grid lines, with the size Plasma
    // would give it with its own minimum size (see plasmaMinimumItemSize).
    function placeAddedWidget(appletId: int, geometry: var, rotation: real): void {
        const item = widgets().find(item => item.applet.plasmoid.id === appletId);
        if (!item) {
            return;
        }
        if (geometry) {
            setGeometry(item, geometry);
            item.rotation = rotation;
            // It arrives selected but without its handles, and would ignore clicks:
            // selected again once in place
            item.editMode = false;
            arrivedWidget = item;
            arrivalTimer.restart();
        } else if (isShortcut(item)) {
            // Centered where it was dropped
            const size = shortcutSize(item.applet.plasmoid.title, config.gridCellWidth, config.gridIconSize);
            const position = Qt.point(item.x + (item.width - size.width) / 2,
                                      item.y + (item.height - size.height) / 2);
            setGeometry(item, dropGeometry(item, position));
        } else {
            const size = item.initialSize.width > plasmaMinimumItemSize
                      && item.initialSize.height > plasmaMinimumItemSize
                ? item.initialSize
                : Qt.size(appletsLayout.defaultItemWidth, appletsLayout.defaultItemHeight);
            setGeometry(item, dropGeometryOf(false, "", size, Qt.point(item.x, item.y), item));
        }
        saveLater();
    }

    property Item arrivedWidget: null

    Timer {
        id: arrivalTimer
        interval: Kirigami.Units.longDuration
        onTriggered: {
            if (grid.active) {
                grid.select(grid.arrivedWidget);
            }
            grid.arrivedWidget = null;
        }
    }

    // --- Selection ---------------------------------------------------------
    // In edit mode, Plasma selects (shows the handles of) the widget under the
    // mouse, and unselects it half a second after the mouse left it. Here only a
    // click selects, and the selection stays until another widget or the desktop
    // is clicked:
    // - a mouse area above the widgets takes their hover events (no tooltips
    //   either) and lets the clicks through;
    // - the selected widget is put above it, so that its handles still change
    //   the mouse cursor; when the mouse leaves it, Plasma unselects it: it is
    //   selected again;
    // - Plasma selects a clicked widget, but does not unselect the previous one.

    property Item selectedWidget: null
    // Widget whose move has just ended (see moveEnded())
    property Item moveEndedWidget: null

    // Selects this widget only (none if null)
    function select(item: Item): void {
        const previous = selectedWidget;
        selectedWidget = item;
        if (previous && previous !== item) {
            previous.editMode = false;
            previous.z = 0; // back below hoverBlocker
        }
        if (item) {
            item.editMode = true;
            item.z = hoverBlocker.z + 1; // (Plasma sets it to 1 when it selects)
        }
    }

    function widgetEditModeChanged(item: Item): void {
        // (leaving edit mode, the layout leaves it before this item is told)
        if (!active || !appletsLayout.editMode) {
            return;
        }
        if (item.editMode && item !== selectedWidget) {
            select(item);
        } else if (!item.editMode && item === selectedWidget) {
            if (item === moveEndedWidget) {
                selectedWidget = null; // leaving for another screen
            } else {
                select(item); // the mouse left it
            }
        }
    }

    // Whether this point of the layout is on a widget, or on the handles of the
    // selected one (they go beyond it)
    function isOnWidget(x: real, y: real): bool {
        return widgets().some(item => {
            const point = appletsLayout.mapToItem(item, x, y);
            const handles = item.configOverlayItem;
            return item.contains(point)
                || (item.editMode && handles?.visible && handles.childAt(point.x, point.y) !== null);
        });
    }

    // Above the widgets: takes the hover events, and lets the clicks through,
    // unselecting on a click on the desktop itself. A click on a locked widget is
    // taken (a click on a shortcut would launch it): a left click shows the tab of
    // this widget and selects it.
    MouseArea {
        id: hoverBlocker
        parent: grid.appletsLayout
        anchors.fill: parent
        z: 999
        visible: grid.active
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            if (!grid.isOnWidget(mouse.x, mouse.y)) {
                grid.select(null);
            }
            const locked = grid.lockedWidgetAt(mouse.x, mouse.y);
            // (the other buttons do nothing on a locked widget)
            if (locked && mouse.button === Qt.LeftButton) {
                grid.panel.showTab(!grid.isShortcut(locked));
                grid.select(locked);
            }
            mouse.accepted = locked !== null;
        }
    }

    // The widget at this point of the layout if it is locked (the topmost one: the
    // last child is drawn above)
    function lockedWidgetAt(x: real, y: real): Item {
        const items = widgets().filter(item => item.contains(appletsLayout.mapToItem(item, x, y)));
        const top = items[items.length - 1];
        return top && isLocked(top) ? top : null;
    }

    // The selected widget, above hoverBlocker, would get the clicks once locked
    onPlasmoidsTabChanged: select(null)

    // --- Cancel ----------------------------------------------------------
    // Cancel puts back the desktops of all screens as when grid mode started: the
    // desktop where it is clicked first, then the others when grid mode ends.
    // Widgets moved to another screen are taken back by their desktop.

    // Layout when grid mode started: geometry and rotation of every widget (by
    // applet id), and grid settings
    property var savedLayout: null
    readonly property var savedSettings: ["gridCellWidth", "gridCellHeight", "gridIconSize",
                                          "gridPlasmoidCellWidth", "gridPlasmoidCellHeight",
                                          "gridPlasmoidCellLinked", "gridSnapToEdges"]

    onActiveChanged: {
        select(null);
        if (!active) {
            if (GridDrag.cancelling) {
                restoreSavedLayout();
            }
            savedLayout = null;
            return;
        }
        const geometries = {};
        const rotations = {};
        for (const item of widgets()) {
            geometries[item.applet.plasmoid.id] = Qt.rect(item.x, item.y, item.width, item.height);
            rotations[item.applet.plasmoid.id] = item.rotation;
        }
        const settings = {};
        for (const key of savedSettings) {
            settings[key] = config[key];
        }
        savedLayout = { geometries, rotations, settings };
    }

    // Puts every widget back where it was when grid mode started, with its rotation
    // and the grid settings of that time
    function restoreSavedLayout(): void {
        const layout = savedLayout;
        if (!layout) {
            return;
        }
        savedLayout = null; // only once
        // (a widget just dropped is not put back where it was dropped)
        dropEndTimer.stop();
        droppedWidget = null;
        if (!GridDrag.cancelling) {
            // Clicked here: the other desktops restore theirs when grid mode ends,
            // right after
            GridDrag.cancelling = true;
            Qt.callLater(() => GridDrag.cancelling = false);
        }

        // Widgets moved to another screen, taken back the way main.qml drops them
        const widgetIds = widgets().map(item => item.applet.plasmoid.id);
        for (const appletId in layout.geometries) {
            const desktopId = GridDrag.desktopOf[appletId];
            if (!widgetIds.includes(Number(appletId)) && desktopId !== undefined) {
                takeBack.mimeData.setData("text/x-plasmoidinstanceid", desktopId + ":" + appletId);
                appletsLayout.containmentItem.processMimeData(takeBack.mimeData, 0, 0);
            }
        }

        for (const key in layout.settings) {
            config[key] = layout.settings[key];
        }
        // Once the widgets taken back are in the layout
        Qt.callLater(() => {
            for (const item of grid.widgets()) {
                const appletId = item.applet.plasmoid.id;
                if (layout.geometries[appletId]) {
                    grid.setGeometry(item, layout.geometries[appletId]);
                    item.rotation = layout.rotations[appletId];
                }
            }
            grid.saveLater();
        });
    }

    // Only for its mime data (MimeData cannot be created alone)
    DragDrop.DragArea {
        id: takeBack
        enabled: false
    }
}
