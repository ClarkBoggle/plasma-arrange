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

// Arranging the desktop widgets on grids, while the desktop is in edit mode.
//
// - Shortcuts (Icon widgets) snap to the shortcut grid: as wide as a cell, with
//   a fixed icon size, centered in their cell.
// - The other widgets (plasmoids) snap to the plasmoid grid and keep their size.
// - Shortcuts cannot be resized by hand (they have the size of the grid);
//   plasmoids can, freely ("Snap to Grid" fits them to their grid).
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

    // In grid mode, the widgets of the other tab are locked: no handles, no clicks
    function isLocked(item: Item): bool {
        return active && isShortcut(item) === plasmoidsTab;
    }

    // Each widget tells when it is selected or moved, and when it gets its handles
    // (connected once per widget). All the applet containers are watched, even
    // without their applet yet: a widget coming from another screen gets its
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
        const onGrid = Math.round((position - offset) / cellSize) * cellSize + offset;
        if (config.gridSnapToEdges && max - position < Math.abs(position - onGrid)) {
            return max;
        }
        return clamp(onGrid, max);
    }

    // The value kept between 0 and max
    function clamp(value: real, max: real): real {
        return Math.max(0, Math.min(value, max));
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
            const x = onRightEdge ? maxX
                : clamp(column * cellWidth + shortcutOffsetX(size.width, cellWidth), maxX);
            const y = onBottomEdge ? maxY
                : clamp(row * cellHeight + shortcutOffsetY(iconSize, cellHeight), maxY);
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
        const right = Math.max(left + cellWidth,
                               snap(item.x + item.width, 0, cellWidth, appletsLayout.width));
        const bottom = Math.max(top + cellHeight,
                                snap(item.y + item.height, 0, cellHeight, appletsLayout.height));
        return Qt.rect(left, top, right - left, bottom - top);
    }

    function snapAllPlasmoids(): void {
        for (const item of widgets().filter(item => !isShortcut(item))) {
            setGeometry(item, snappedPlasmoidGeometry(item));
        }
        saveLater();
    }

    // --- Moving a widget (main.qml calls widgetMoved()) --------------------

    property Item draggedItem: null
    property size sizeBeforeDrag
    property point dragPosition // position while dragged, before any snapping
    property bool dragged: false // it really moved (not only clicked)

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

        if (!dragged) {
            return;
        }
        // The layout has just placed it: put where the placeholder showed
        const geometry = dropGeometry(item, dragPosition);
        setGeometry(item, geometry);
        saveLater();
        if (isShortcut(item)) {
            refitTimer.restart();
        } else {
            droppedPlasmoid = item;
            droppedGeometry = geometry;
            dropEndTimer.restart();
        }
    }

    // Where a widget dropped at this position goes: shortcuts get the shortcut size,
    // centered on the nearest cell; plasmoids keep their size, on the nearest
    // plasmoid grid lines; both stick to the right/bottom edge if it is closer
    function dropGeometry(item: Item, position: point): rect {
        return dropGeometryOf(isShortcut(item), item.applet.plasmoid.title, sizeBeforeDrag, position);
    }

    // The same for a widget known by its kind, its name (shortcut) and its size
    // (plasmoid): a widget coming from another screen
    function dropGeometryOf(shortcut: bool, title: string, plasmoidSize: size, position: point): rect {
        if (shortcut) {
            const size = shortcutSize(title, config.gridCellWidth, config.gridIconSize);
            const x = snap(position.x, shortcutOffsetX(size.width, config.gridCellWidth),
                           config.gridCellWidth, appletsLayout.width - size.width);
            const y = snap(position.y, shortcutOffsetY(config.gridIconSize, config.gridCellHeight),
                           config.gridCellHeight, appletsLayout.height - size.height);
            return Qt.rect(x, y, size.width, size.height);
        }
        const x = snap(position.x, 0, config.gridPlasmoidCellWidth, appletsLayout.width - plasmoidSize.width);
        const y = snap(position.y, 0, config.gridPlasmoidCellHeight, appletsLayout.height - plasmoidSize.height);
        return Qt.rect(x, y, plasmoidSize.width, plasmoidSize.height);
    }

    // A dropped plasmoid slides to its place (animation in main.qml), and the layout
    // places it once more during the slide, rounding its position: off the grid.
    // Once the slide is over, it is put back where it was dropped. (Shortcuts are
    // all refitted after a drop anyway.)
    property Item droppedPlasmoid: null
    property rect droppedGeometry

    Timer {
        id: dropEndTimer
        interval: Kirigami.Units.longDuration
        onTriggered: {
            if (grid.droppedPlasmoid) {
                grid.setGeometry(grid.droppedPlasmoid, grid.droppedGeometry);
                grid.saveLater();
            }
            grid.droppedPlasmoid = null;
        }
    }

    // --- Handles -----------------------------------------------------------
    // Shown around the selected widget: resize handles, and a bar with buttons
    // (rotate, configure, remove) and an area to move the widget.

    // The handles of a widget are created when it is first selected
    function widgetHandlesChanged(item: Item): void {
        removeResizeHandles(item);
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

    // Drop area of the desktop (called after main.qml's handlers)
    Connections {
        target: grid.appletsLayout.parent

        function onDragEnter(event: var): void {
            grid.incomingDrag = grid.isWidgetDrag(event);
        }

        function onDragMove(event: var): void {
            if (!grid.isWidgetDrag(event)) {
                return;
            }
            const widget = GridDrag.widget;
            // Held by the mouse at the same point as its image (in proportion for a
            // shortcut, which takes the shortcut size of this desktop)
            const size = widget.shortcut
                ? grid.shortcutSize(widget.title, grid.config.gridCellWidth, grid.config.gridIconSize)
                : Qt.size(widget.width, widget.height);
            const position = Qt.point(event.x - widget.grabX * size.width / widget.width,
                                      event.y - widget.grabY * size.height / widget.height);
            grid.incomingGeometry = grid.dropGeometryOf(widget.shortcut, widget.title, size, position);
            grid.showPlaceHolder(grid.incomingGeometry, widget.shortcut);
            // Only the kind of widget of the tab shown can be dropped
            grid.panel.showTab(!widget.shortcut);
        }

        // (incomingGeometry is used when the widget is added, right after)
        function onDrop(event: var): void {
            grid.incomingDrag = false;
        }

        function onDragLeave(event: var): void {
            grid.incomingDrag = false;
            grid.incomingGeometry = null;
        }
    }

    Connections {
        target: Plasmoid

        // (the layout creates its container right after)
        function onAppletAdded(applet: var): void {
            GridDrag.desktopOf[applet.id] = Plasmoid.id; // for Cancel
            if (grid.active) {
                Qt.callLater(grid.placeAddedWidget, applet.id, grid.incomingGeometry,
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
    // on the nearest cell, a plasmoid the nearest grid lines.
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
            item.x = snap(item.x, 0, config.gridPlasmoidCellWidth, appletsLayout.width - item.width);
            item.y = snap(item.y, 0, config.gridPlasmoidCellHeight, appletsLayout.height - item.height);
        }
        saveLater();
    }

    property Item arrivedWidget: null

    Timer {
        id: arrivalTimer
        interval: Kirigami.Units.longDuration
        onTriggered: {
            grid.select(grid.arrivedWidget);
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
    // taken (a click on a shortcut would launch it): it shows the tab of this
    // widget and selects it.
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
            if (locked) {
                grid.panel.showTab(!grid.isShortcut(locked));
                grid.select(locked);
            }
            mouse.accepted = locked !== null;
        }
    }

    // The locked widget at this point of the layout (the topmost one), if no unlocked
    // one is there
    function lockedWidgetAt(x: real, y: real): Item {
        const items = widgets().filter(item => item.contains(appletsLayout.mapToItem(item, x, y)));
        return items.some(item => !isLocked(item)) ? null : (items[items.length - 1] ?? null);
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
                                          "gridPlasmoidCellWidth", "gridPlasmoidCellHeight"]

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
