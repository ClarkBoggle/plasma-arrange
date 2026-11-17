/*
    SPDX-FileCopyrightText: 2011-2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2011-2019 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014-2015 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

import org.kde.private.desktopcontainment.folder as Folder

import org.kde.plasma.private.containmentlayoutmanager as ContainmentLayoutManager

import "code/FolderTools.js" as FolderTools

ContainmentItem {
    id: root

    switchWidth: { switchSize(); }
    switchHeight: { switchSize(); }

    // Only exists because the default CompactRepresentation doesn't:
    // - open on drag
    // - allow defining a custom drop handler
    // TODO remove once it gains that feature (perhaps optionally?)
    compactRepresentation: (isFolder && !isContainment) ? compactRepresentation : null

    objectName: isFolder ? "folder" : "desktop"

    width: inPanel ? undefined : preferredWidth(false) // Initial size when adding to e.g. desktop.
    height: inPanel ? undefined : preferredHeight(false) // Initial size when adding to e.g. desktop.

    function switchSize() {
        // Support expanding into the full representation on very thick vertical panels.
        if (inPanel && Plasmoid.formFactor === PlasmaCore.Types.Vertical) {
            return Kirigami.Units.gridUnit * 8;
        }

        return 0;
    }

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    property bool isFolder: (Plasmoid.pluginName === "org.kde.plasma.folder")
    property bool isContainment: Plasmoid.isContainment
    property bool inPanel: (Plasmoid.location !== PlasmaCore.Types.Floating)
    property bool useListViewMode: inPanel && Plasmoid.configuration.viewMode === 0
    // Grid mode: while the desktop is in edit mode, show the arrangement grid
    // and snap widgets to it (desktop only, not Folder View)
    property bool gridMode: isContainment && !isFolder && Plasmoid.containment.corona.editMode
    // Whether a widget is being moved in grid mode (see the cells of the applets layout)
    property bool movingWidget: false

    // On the grid, a shortcut (Icon widget) is as wide as its cell (room for its name),
    // has the chosen icon size, and is centered vertically in its cell.
    // The Icon widget gives its icon the frame width × (frame height minus the name):
    // a frame exactly as tall as the icon plus its own name keeps the icon at the
    // chosen size, centered, whatever the frame width and the name length.
    function shortcutSize(title: string, width: real, iconSize: real): size {
        nameMeasure.width = width;
        nameMeasure.text = title;
        return Qt.size(width, iconSize + nameMeasure.implicitHeight);
    }

    // Horizontal offset of a shortcut of this width, centered on its cell
    // (negative if the shortcut is wider than the cell: it overflows on both sides)
    function shortcutOffset(width: real, cellWidth: real): real {
        return Math.round((cellWidth - width) / 2);
    }

    // Vertical offset of a shortcut, centered on its cell as if its name took 2 lines:
    // the same for every shortcut, so that all icons of a row are aligned
    function shortcutOffsetY(iconSize: real, cellHeight: real): real {
        return Math.round((cellHeight - iconSize - twoLinesName.implicitHeight) / 2);
    }

    property Component appletAppearanceComponent

    property int handleDelay: 800
    property real haloOpacity: 0.5

    property bool isUiReady: Plasmoid.containment.corona.isScreenUiReady(root.screen)

    readonly property int hoverActivateDelay: 750 // Magic number that matches Dolphin's auto-expand folders delay.

    readonly property FolderViewLayerLoader folderViewLayer: fullRepresentationItem.folderViewLayer
    readonly property ContainmentLayoutManager.AppletsLayout appletsLayout: fullRepresentationItem.appletsLayout

    // Plasmoid.title is set by a Binding {} in FolderViewLayer
    toolTipSubText: ""
    Plasmoid.icon: (!Plasmoid.configuration.useCustomIcon && folderViewLayer.ready) ? symbolicizeIconName(folderViewLayer.view?.model.iconName) : Plasmoid.configuration.icon

    onScreenChanged: isUiReady = Plasmoid.containment.corona.isScreenUiReady(root.screen)

    // We want to do this here rather than in the model because we don't always want
    // symbolic icons everywhere, but we do know that we always want them in this
    // specific representation right here
    function symbolicizeIconName(iconName) {
        const symbolicSuffix = "-symbolic";
        if (iconName?.endsWith(symbolicSuffix)) {
            return iconName;
        }

        return iconName + symbolicSuffix;
    }

    function addLauncher(desktopUrl) {
        if (!isFolder) {
            return;
        }

        folderViewLayer.view.linkHere(desktopUrl);
    }

    function preferredWidth(forMinimumSize: bool): real {
        if ((isContainment || !folderViewLayer.ready) || (inPanel && !compactRepresentationItem.visible)) {
            return -1;
        } else if (useListViewMode) {
            return (forMinimumSize ? folderViewLayer.view.cellHeight * 4 : Kirigami.Units.gridUnit * 16);
        }

        return (folderViewLayer.view.cellWidth * (forMinimumSize ? 1 : 3)) + (Kirigami.Units.gridUnit * 2);
    }

    function preferredHeight(forMinimumSize: bool): real {
        let height;
        if ((isContainment || !folderViewLayer.ready) || (inPanel && !compactRepresentationItem.visible)) {
            return -1;
        } else if (useListViewMode) {
            height = (folderViewLayer.view.cellHeight * (forMinimumSize ? 1 : 15)) + Kirigami.Units.smallSpacing;
        } else {
            height = (folderViewLayer.view.cellHeight * (forMinimumSize ? 1 : 2)) + Kirigami.Units.gridUnit;
        }

        if (Plasmoid.configuration.labelMode !== 0) {
            height += (folderViewLayer.item as FolderViewLayer).labelHeight;
        }

        return height;
    }

    // Changes the cell size and the icon size. Every shortcut
    // takes its new size, staying centered in the same column and row.
    // Shortcuts stuck to the right or bottom screen edge stay stuck to it.
    function changeGrid(cellWidth: int, cellHeight: int, iconSize: int): void {
        const oldCellWidth = Plasmoid.configuration.gridCellWidth;
        const oldCellHeight = Plasmoid.configuration.gridCellHeight;
        const oldIconSize = Plasmoid.configuration.gridIconSize;

        Plasmoid.configuration.gridCellWidth = cellWidth;
        Plasmoid.configuration.gridCellHeight = cellHeight;
        Plasmoid.configuration.gridIconSize = iconSize;

        for (const item of appletsLayout.children) {
            if (!item.isShortcut) {
                continue;
            }
            const onRightEdge = Math.abs(item.x + item.width - appletsLayout.width) < 1;
            const onBottomEdge = Math.abs(item.y + item.height - appletsLayout.height) < 1;
            const column = Math.round((item.x - shortcutOffset(item.width, oldCellWidth)) / oldCellWidth);
            const row = Math.round((item.y - shortcutOffsetY(oldIconSize, oldCellHeight)) / oldCellHeight);
            const size = shortcutSize(item.applet.plasmoid.title, cellWidth, iconSize);
            const width = size.width;
            const height = size.height;

            item.width = width;
            item.height = height;
            if (onRightEdge) {
                item.x = appletsLayout.width - width;
            } else {
                item.x = Math.max(0, Math.min(column * cellWidth + shortcutOffset(width, cellWidth),
                                              appletsLayout.width - width));
            }
            if (onBottomEdge) {
                item.y = appletsLayout.height - height;
            } else {
                item.y = Math.max(0, Math.min(row * cellHeight + shortcutOffsetY(iconSize, cellHeight),
                                              appletsLayout.height - height));
            }
        }
        saveLayoutLater();
    }

    // Snaps the edges of every plasmoid (not shortcuts) to the plasmoid grid
    function snapAllPlasmoids(): void {
        for (const item of appletsLayout.children) {
            if (item.isShortcut === false) {
                const geometry = item.snappedResizeGeometry();
                item.x = geometry.x;
                item.y = geometry.y;
                item.width = geometry.width;
                item.height = geometry.height;
            }
        }
        saveLayoutLater();
    }

    // Largest icon size keeping every shortcut inside its cell: not wider than the
    // cell, and not taller than the cell with the tallest name (at the cell width)
    function largestIconSize(cellWidth: real, cellHeight: real): int {
        let nameHeight = 0;
        for (const item of appletsLayout.children) {
            if (item.isShortcut) {
                nameHeight = Math.max(nameHeight, shortcutSize(item.applet.plasmoid.title, cellWidth, 0).height);
            }
        }
        return Math.floor(Math.min(cellWidth, cellHeight - nameHeight));
    }

    // Size of the largest shortcut on the desktop: cells cannot be smaller
    function largestShortcutSize(): size {
        let width = 0;
        let height = 0;
        for (const item of appletsLayout.children) {
            if (item.isShortcut) {
                width = Math.max(width, item.width);
                height = Math.max(height, item.height);
            }
        }
        return Qt.size(width, height);
    }

    // "Resize Icons": every shortcut gets its size again, centered in its cell
    function resizeIcons(): void {
        const config = Plasmoid.configuration;
        changeGrid(config.gridCellWidth, config.gridCellHeight, config.gridIconSize);
    }

    // Resize Icons once the drop animation is over (positions are read from the shortcuts)
    Timer {
        id: resizeIconsTimer
        interval: Kirigami.Units.longDuration
        onTriggered: root.resizeIcons()
    }

    // Saves the widgets geometry once the move animations are over
    function saveLayoutLater(): void {
        saveLayoutTimer.restart();
    }

    Timer {
        id: saveLayoutTimer
        interval: Kirigami.Units.longDuration
        onTriggered: root.appletsLayout.save()
    }

    // Hidden labels, set like the shortcut name, to measure its height at a given width,
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

    function isDrag(fromX, fromY, toX, toY) {
        const length = Math.abs(fromX - toX) + Math.abs(fromY - toY);
        return length >= Application.styleHints.startDragDistance;
    }

    onFocusChanged: {
        if (focus && isFolder) {
            (folderViewLayer.item as Item)?.forceActiveFocus();
        }
    }

    onExternalData: (mimetype, data) => {
        Plasmoid.configuration.url = data
    }

    component ShortDropBehavior : Behavior {
        NumberAnimation {
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.InOutQuad
        }
    }

    component LongDropBehavior : Behavior {
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.InOutQuad
        }
    }

    KSvg.FrameSvgItem {
        id: highlightItemSvg

        visible: false

        imagePath: root.inPanel ? "widgets/viewitem" : ""
        prefix: "hover"
    }

    KSvg.FrameSvgItem {
        id: listItemSvg

        visible: false

        imagePath: root.inPanel ? "widgets/viewitem" : ""
        prefix: "normal"
    }

    KSvg.Svg {
        id: toolBoxSvg
        imagePath: "widgets/toolbox"
        property int rightBorder: elementSize("right").width
        property int topBorder: elementSize("top").height
        property int bottomBorder: elementSize("bottom").height
        property int leftBorder: elementSize("left").width
    }

    // FIXME: the use and existence of this property is a workaround
    preloadFullRepresentation: true
    fullRepresentation: FolderViewDropArea {
        id: dropArea

        anchors {
            fill: parent
            leftMargin: (root.isContainment && root.availableScreenRect) ? root.availableScreenRect.x : 0
            topMargin: (root.isContainment && root.availableScreenRect) ? root.availableScreenRect.y : 0

            rightMargin: (root.isContainment && root.availableScreenRect && parent)
                ? (parent.width - root.availableScreenRect.x - root.availableScreenRect.width) : 0

            bottomMargin: (root.isContainment && root.availableScreenRect && parent)
                ? (parent.height - root.availableScreenRect.y - root.availableScreenRect.height) : 0
        }

        LongDropBehavior on anchors.topMargin { }
        LongDropBehavior on anchors.leftMargin { }
        LongDropBehavior on anchors.rightMargin { }
        LongDropBehavior on anchors.bottomMargin { }

        property alias folderViewLayer: folderViewLayer
        property alias appletsLayout: appletsLayout

        // Layout size bindings are set in Component.onCompleted

        preventStealing: true

        onDragEnter: event => {
            if (root.isContainment && Plasmoid.immutable && !(root.isFolder && FolderTools.isFileDrag(event))) {
                event.ignore();
            }

            // Don't allow any drops while listing.
            if (root.isFolder && folderViewLayer.view.status === Folder.FolderModel.Listing) {
                event.ignore();
            }

            // Firefox tabs are regular drags. Since all of our drop handling is asynchronous
            // we would accept this drop and have Firefox not spawn a new window. (Bug 337711)
            if (event.mimeData.formats.indexOf("application/x-moz-tabbrowser-tab") !== -1) {
                event.ignore();
            }
        }

        onDragMove: event => {
            // TODO: We should reject drag moves onto file items that don't accept drops
            // (cf. QAbstractItemModel::flags() here, but DeclarativeDropArea currently
            // is currently incapable of rejecting drag events.

            // Trigger autoscroll.
            if (root.isFolder && FolderTools.isFileDrag(event)) {
                handleDragMove(folderViewLayer.view, mapToItem(folderViewLayer.view, event.x, event.y));
            } else if (root.isContainment) {
                appletsLayout.showPlaceHolderAt(
                    Qt.rect(event.x - appletsLayout.minimumItemWidth / 2,
                    event.y - appletsLayout.minimumItemHeight / 2,
                    appletsLayout.minimumItemWidth,
                    appletsLayout.minimumItemHeight)
                );
            }
        }

        onDragLeave: event => {
            // Cancel autoscroll.
            if (root.isFolder) {
                handleDragEnd(folderViewLayer.view);
            }

            if (root.isContainment) {
                appletsLayout.hidePlaceHolder();
            }
        }

        onDrop: event => {
            if (root.isFolder && FolderTools.isFileDrag(event)) {
                handleDragEnd(folderViewLayer.view);
                folderViewLayer.view.drop(root, event, mapToItem(folderViewLayer.view, event.x, event.y));
            } else if (root.isContainment) {
                root.processMimeData(event.mimeData,
                    event.x - appletsLayout.placeHolder.width / 2,
                    event.y - appletsLayout.placeHolder.height / 2);
                event.accept(event.proposedAction);
                appletsLayout.hidePlaceHolder();
            }
        }

        Component {
            id: compactRepresentation
            CompactRepresentation { folderView: folderViewLayer.view }
        }

        Connections {
            target: Plasmoid.containment.corona
            ignoreUnknownSignals: true

            function onEditModeChanged() {
                appletsLayout.editMode = Plasmoid.containment.corona.editMode;
            }

            // When adding panels, sizes change. We want to make sure all panels
            // are loaded, and when they all are loaded, we tell the folderViewLayer loader to start.
            function onScreenUiReadyChanged(screen: int, newLayoutReady: bool) {
                if (root.screen === screen) {
                    root.isUiReady = newLayoutReady;
                }
            }
        }

        ContainmentLayoutManager.AppletsLayout {
            id: appletsLayout
            anchors.fill: parent
            relayoutLock: width !== root.availableScreenRect.width || height !== root.availableScreenRect.height
            // NOTE: use root.availableScreenRect and not own width and height as they are updated not atomically
            configKey: "ItemGeometries-" + Math.round(root.screenGeometry.width) + "x" + Math.round(root.screenGeometry.height)
            fallbackConfigKey: root.availableScreenRect.width > root.availableScreenRect.height ? "ItemGeometriesHorizontal" : "ItemGeometriesVertical"

            Binding on containment {
                value: Plasmoid
                when: Plasmoid.isContainment
            }
            containmentItem: root
            editModeCondition: Plasmoid.immutable
                    ? ContainmentLayoutManager.AppletsLayout.Locked
                    : ContainmentLayoutManager.AppletsLayout.AfterPressAndHold

            // Sets the containment in edit mode when we go in edit mode as well
            onEditModeChanged: Plasmoid.containment.corona.editMode = editMode;

            // The layout rounds the position and size of every widget to whole cells each
            // time it places them (startup, desktop updates, edit mode). Snapping to the
            // grids is done here instead (see dropGeometry()), so its cells are 1 px:
            // it then keeps the exact geometry, and the shortcut icons keep their size.
            // For the same reason, its minimum item size must not enlarge small shortcuts.
            minimumItemWidth: Kirigami.Units.iconSizes.small
            minimumItemHeight: minimumItemWidth

            //
            // While a widget is moved in grid mode, its cells are huge instead: the layout
            // recomputes its own placeholder each time the mouse enters another cell,
            // which with 1 px cells means at every pixel, over the whole widget area
            // (slow and jerky). Our own placeholder is shown instead (see onUserDrag).
            cellWidth: root.movingWidget ? 100000 : 1
            cellHeight: cellWidth
            defaultItemWidth: Kirigami.Units.iconSizes.small * 6
            defaultItemHeight: Kirigami.Units.iconSizes.small * 6

            eventManagerToFilter: (folderViewLayer.item as FolderViewLayer)?.view.view ?? null

            appletContainerComponent: ContainmentLayoutManager.BasicAppletContainer {
                id: appletContainer

                // In grid mode, only the widgets of the tab shown in the grid panel can be
                // moved and resized: shortcuts in the Shortcuts tab, plasmoids in the
                // Plasmoids tab. The others are locked (no handles).
                editModeCondition: (Plasmoid.immutable || lockedByTab)
                    ? ContainmentLayoutManager.ItemContainer.Locked
                    : ContainmentLayoutManager.ItemContainer.AfterPressAndHold

                readonly property bool isShortcut: applet?.plasmoid.pluginName === "org.kde.plasma.icon"
                readonly property bool lockedByTab: root.gridMode && isShortcut === gridPanel.plasmoidsTab

                // A locked widget does not react to clicks either while arranging
                // (a click on a shortcut would launch it)
                MouseArea {
                    anchors.fill: parent
                    z: 1000
                    enabled: appletContainer.lockedByTab
                    acceptedButtons: Qt.AllButtons
                }

                // In grid mode, the drop geometry is computed here rather than by the
                // layout, which would resize the widget to whole cells and ignores screen edges:
                // - widgets keep their size, shortcuts get the shortcut size, centered in their cell
                // - the widget goes to the nearest grid line, or to the screen edge if closer
                // The placeholder shows that same geometry while dragging.

                property size sizeBeforeDrag
                property point dragPosition // position while dragged, before any snapping
                property bool dragged: false

                onDragActiveChanged: {
                    if (dragActive) {
                        sizeBeforeDrag = Qt.size(width, height);
                        root.movingWidget = root.gridMode;
                        return;
                    }
                    if (dragged && root.gridMode) {
                        const geometry = dropGeometry(dragPosition);
                        x = geometry.x;
                        y = geometry.y;
                        width = geometry.width;
                        height = geometry.height;
                        root.saveLayoutLater();
                        // After a shortcut drop, all shortcuts get their size again ("Resize Icons")
                        if (isShortcut) {
                            resizeIconsTimer.restart();
                        }
                    }
                    dragged = false;
                    root.movingWidget = false;
                }

                function dropGeometry(position: point): rect {
                    const size = isShortcut
                        ? root.shortcutSize(applet.plasmoid.title, Plasmoid.configuration.gridCellWidth,
                                            Plasmoid.configuration.gridIconSize)
                        : sizeBeforeDrag;
                    // Shortcuts are centered on their cell
                    // Shortcuts use the shortcut grid and are centered on their cell,
                    // the other widgets use the plasmoid grid
                    const cellWidth = isShortcut ? Plasmoid.configuration.gridCellWidth : Plasmoid.configuration.gridPlasmoidCellWidth;
                    const cellHeight = isShortcut ? Plasmoid.configuration.gridCellHeight : Plasmoid.configuration.gridPlasmoidCellHeight;
                    const offset = isShortcut ? root.shortcutOffset(size.width, cellWidth) : 0;
                    const offsetY = isShortcut ? root.shortcutOffsetY(Plasmoid.configuration.gridIconSize, cellHeight) : 0;

                    const x = snap(position.x, offset, cellWidth, appletsLayout.width - size.width);
                    const y = snap(position.y, offsetY, cellHeight, appletsLayout.height - size.height);
                    return Qt.rect(x, y, size.width, size.height);
                }

                // While a plasmoid (not a shortcut) is resized with its handles in grid mode,
                // the placeholder shows its size snapped to the plasmoid grid; the snapped size
                // is applied once, when the handle is released. Snapping at every mouse move
                // would resize the plasmoid twice per move, which is slow and jerky.
                onWidthChanged: resizeMoved()
                onHeightChanged: resizeMoved()

                function resizeMoved(): void {
                    if (!root.gridMode || isShortcut || dragActive || !editMode || !resizeHandlePressed()) {
                        return;
                    }
                    const geometry = snappedResizeGeometry();
                    const placeHolder = appletsLayout.placeHolder;
                    placeHolder.x = geometry.x;
                    placeHolder.y = geometry.y;
                    placeHolder.width = geometry.width;
                    placeHolder.height = geometry.height;
                    placeHolder.opacity = 1;
                    resizeEndTimer.start();
                }

                // Whether one of the resize handles of this widget is held
                function resizeHandlePressed(): bool {
                    for (const child of configOverlayItem?.children ?? []) {
                        if (child.resizeCorner !== undefined && child.pressed) {
                            return true;
                        }
                    }
                    return false;
                }

                // Current geometry with its edges snapped to the plasmoid grid
                // (or to the right/bottom screen edge)
                function snappedResizeGeometry(): rect {
                    const cellWidth = Plasmoid.configuration.gridPlasmoidCellWidth;
                    const cellHeight = Plasmoid.configuration.gridPlasmoidCellHeight;
                    const left = snap(x, 0, cellWidth, appletsLayout.width);
                    const top = snap(y, 0, cellHeight, appletsLayout.height);
                    const right = Math.max(left + cellWidth, snap(x + width, 0, cellWidth, appletsLayout.width));
                    const bottom = Math.max(top + cellHeight, snap(y + height, 0, cellHeight, appletsLayout.height));
                    return Qt.rect(left, top, right - left, bottom - top);
                }

                // Waits for the handle to be released, then applies the snapped geometry
                Timer {
                    id: resizeEndTimer
                    interval: 50
                    repeat: true
                    onTriggered: {
                        if (appletContainer.resizeHandlePressed()) {
                            return;
                        }
                        stop();
                        const geometry = appletContainer.snappedResizeGeometry();
                        appletContainer.x = geometry.x;
                        appletContainer.y = geometry.y;
                        appletContainer.width = geometry.width;
                        appletContainer.height = geometry.height;
                        appletsLayout.hidePlaceHolder();
                        root.saveLayoutLater();
                    }
                }

                // Nearest grid line (shifted by offset), or the right/bottom edge (max) if it
                // is closer. The grid starts at the left/top edge, so no snapping is needed there.
                function snap(position: real, offset: real, cellSize: real, max: real): real {
                    const onGrid = Math.round((position - offset) / cellSize) * cellSize + offset;
                    const toGrid = Math.abs(position - onGrid);
                    if (Plasmoid.configuration.gridSnapToEdges && max - position < toGrid) {
                        return max;
                    }
                    return Math.max(0, Math.min(onGrid, max));
                }

                configOverlaySource: "ConfigOverlay.qml"

                Connections {
                    target: appletsLayout
                    function onEditModeChanged(): void {
                        if (!Plasmoid.containment.corona.editMode) {
                            appletContainer.cancelEdit();
                        }
                    }
                }

                onAppletChanged: {
                    applet.visible = true
                }

                Drag.dragType: Drag.Automatic
                Drag.active: false
                Drag.supportedActions: Qt.MoveAction
                Drag.mimeData: {
                    "text/x-plasmoidinstanceid": Plasmoid.containment.id+':'+appletContainer.applet.plasmoid.id
                }
                Drag.onDragFinished: dropEvent => {
                    if (dropEvent == Qt.MoveAction) {
                        appletContainer.visible = true
                        appletContainer.applet.visible = true
                        //currentApplet.applet.plasmoid.internalAction("remove").trigger()
                    } else {
                        appletContainer.visible = true
                        //appletsModel.insert(configurationArea.draggedItemIndex - 1, {applet: appletContainer.applet});
                    }
                    //appletContainer.destroy()
                    //root.dragAndDropping = false
                    //root.layoutManager.save()
                }

                onUserDrag: (newPosition, dragCenter) => {
                    dragPosition = newPosition;
                    dragged = true;
                    if (root.gridMode) {
                        // Set directly: showPlaceHolderAt() would snap it to whole cells again
                        const geometry = dropGeometry(newPosition);
                        const placeHolder = appletsLayout.placeHolder;
                        placeHolder.x = geometry.x;
                        placeHolder.y = geometry.y;
                        placeHolder.width = geometry.width;
                        placeHolder.height = geometry.height;
                        placeHolder.opacity = 1;
                    }

                    const pos = mapToItem(root.parent, dragCenter.x, dragCenter.y);
                    const newCont = root.containmentItemAt(pos.x, pos.y);
                    // User likely touched screen edges, so ignore that.
                    if (!newCont) {
                        return;
                    }

                    if (newCont.plasmoid !== Plasmoid) {
                        // First go out of applet edit mode, get rid of the config overlay, release mouse grabs in preparation of applet reparenting
                        cancelEdit();
                        appletsLayout.hidePlaceHolder();
                        appletContainer.grabToImage(result => {
                            appletContainer.Drag.imageSource = result.url
                            appletContainer.visible = false
                            appletContainer.Drag.active = true
                        })
                    }
                }

                ShortDropBehavior on x { }
                ShortDropBehavior on y { }
            }

            placeHolder: ContainmentLayoutManager.PlaceHolder {}

            // Grid of the tab shown in the grid panel
            GridLines {
                anchors.fill: parent
                z: -1
                visible: root.gridMode
                cellWidth: gridPanel.plasmoidsTab ? Plasmoid.configuration.gridPlasmoidCellWidth : Plasmoid.configuration.gridCellWidth
                cellHeight: gridPanel.plasmoidsTab ? Plasmoid.configuration.gridPlasmoidCellHeight : Plasmoid.configuration.gridCellHeight
            }

            component FolderViewLayerLoader: Loader {
                property bool ready: status === Loader.Ready
                property FolderView view: (item as FolderViewLayer)?.view ?? null
                property Folder.FolderModel model: (item as FolderViewLayer)?.model ?? null

                source: "FolderViewLayer.qml"
            }


            FolderViewLayerLoader {
                id: folderViewLayer

                anchors.fill: parent

                focus: true

                // Do not set this active by default for desktop, and disable it when folderMode is not used
                active: {
                    if (root.isFolder){
                        if (!root.isContainment) {
                            // We are a folder widget
                            return true;
                        } else {
                            // For desktop, test if the screen is ready
                            return root.isUiReady;
                        }
                    }
                    return false;
                }
                asynchronous: false

                onFocusChanged: {
                    if (!focus && model) {
                        model.clearSelection();
                    }
                }

                Binding {
                    target: folderViewLayer.item
                    property: "inPanel"
                    value: root.inPanel
                }

                Binding {
                    target: folderViewLayer.item
                    property: "useListViewMode"
                    value: root.useListViewMode
                }

                Connections {
                    target: folderViewLayer.view

                    // `FolderViewDropArea` is not a FocusScope. We need to forward manually.
                    function onPressed() {
                        folderViewLayer.forceActiveFocus();
                    }
                }
            }
        }

        PlasmaCore.Action {
            id: configAction
            text: i18nc("@action:inmenu opens config dialog", "Desktop and Wallpaper")
            icon.name: "preferences-desktop-wallpaper"
            shortcut:"Ctrl+Shift+D"
            onTriggered: Plasmoid.containment.configureRequested(Plasmoid)
        }

        GridPanel {
            id: gridPanel
            z: 1000 // above the widgets
            visible: root.gridMode
            // Top center by default; can then be moved by its title
            x: Math.round((parent.width - width) / 2)
            y: Kirigami.Units.gridUnit * 2
            largestShortcutSize: root.largestShortcutSize
            largestIconSize: root.largestIconSize
            onSnapPlasmoidsRequested: root.snapAllPlasmoids()
            onGridChangeRequested: (cellWidth, cellHeight, iconSize) => root.changeGrid(cellWidth, cellHeight, iconSize)
        }

        Component.onCompleted: {
            // Layout bindings need to be set delayed; the intermediate steps as the other bindings happen cause loops
            Qt.callLater( () => {
                dropArea.Layout.minimumWidth = Qt.binding(() => root.preferredWidth(root.inPanel))
                dropArea.Layout.minimumHeight = Qt.binding(() => root.preferredHeight(root.inPanel))

                dropArea.Layout.preferredWidth = Qt.binding(() => root.preferredWidth(false))
                dropArea.Layout.preferredHeight = Qt.binding(() => root.preferredHeight(false))

                // Maximum size is intentionally unbounded
            })

            if (!Plasmoid.isContainment) {
                return;
            }

            Plasmoid.setInternalAction("configure", configAction)
        }
    }
}
