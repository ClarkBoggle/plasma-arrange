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

    // On the grid, a shortcut (Icon widget) fills its cell. It draws its icon in
    // the frame width × (frame height minus its name, 1 or 2 lines). So all icons
    // have the same size when the cell is at least 2 lines taller than wide:
    // cell = icon size × (icon size + shortcutLabelHeight).
    readonly property int shortcutLabelHeight: Math.ceil(labelMetrics.lineSpacing * 2)
    // Icon size of a shortcut whose name takes 2 lines
    readonly property int shortcutIconSize: Math.max(Kirigami.Units.iconSizes.small,
        Math.min(Plasmoid.configuration.gridCellWidth, Plasmoid.configuration.gridCellHeight - shortcutLabelHeight))

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

    // Gives every shortcut the size of a cell and snaps it to the grid,
    // as if it had been dropped where it is
    function resizeAllShortcuts(): void {
        for (const item of appletsLayout.children) {
            if (item.isShortcut) {
                const geometry = item.dropGeometry(Qt.point(item.x, item.y));
                item.x = geometry.x;
                item.y = geometry.y;
                item.width = geometry.width;
                item.height = geometry.height;
            }
        }
        saveLayoutLater();
    }

    // Sets the shortcut icon size, which is the cell width. The cell height must
    // keep room for the icon and a 2 lines name:
    // - wider: the height grows only if needed
    // - narrower: the height shrinks by as much, but never below that room
    // Every shortcut fills its new cell, keeping its column and row.
    // Shortcuts stuck to the right or bottom edge stay stuck to it.
    function setShortcutIconSize(size: int): void {
        const oldCellWidth = appletsLayout.cellWidth;
        const oldCellHeight = appletsLayout.cellHeight;
        const cellWidth = size;
        const minimumHeight = size + shortcutLabelHeight;
        const cellHeight = size > oldCellWidth
            ? Math.max(oldCellHeight, minimumHeight)
            : Math.max(oldCellHeight - (oldCellWidth - size), minimumHeight);

        Plasmoid.configuration.gridCellWidth = cellWidth;
        Plasmoid.configuration.gridCellHeight = cellHeight;

        for (const item of appletsLayout.children) {
            if (!item.isShortcut) {
                continue;
            }
            const onRightEdge = Math.abs(item.x + item.width - appletsLayout.width) < 1;
            const onBottomEdge = Math.abs(item.y + item.height - appletsLayout.height) < 1;
            const column = Math.round(item.x / oldCellWidth);
            const row = Math.round(item.y / oldCellHeight);

            item.width = cellWidth;
            item.height = cellHeight;
            item.x = onRightEdge ? appletsLayout.width - cellWidth
                : Math.min(column * cellWidth, appletsLayout.width - cellWidth);
            item.y = onBottomEdge ? appletsLayout.height - cellHeight
                : Math.min(row * cellHeight, appletsLayout.height - cellHeight);
        }
        saveLayoutLater();
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

    FontMetrics {
        id: labelMetrics
        font: Kirigami.Theme.defaultFont
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

            minimumItemWidth: Kirigami.Units.gridUnit * 3
            minimumItemHeight: minimumItemWidth

            cellWidth: root.gridMode ? Plasmoid.configuration.gridCellWidth : Kirigami.Units.iconSizes.small
            cellHeight: root.gridMode ? Plasmoid.configuration.gridCellHeight : cellWidth
            defaultItemWidth: Kirigami.Units.iconSizes.small * 6
            defaultItemHeight: Kirigami.Units.iconSizes.small * 6

            // The occupied cells are not recomputed when the cell size changes:
            // forget them, so they don't block drops at wrong places.
            // Widgets don't move; each one takes its cells again when it is dropped.
            onCellWidthChanged: releaseAllSpace()
            onCellHeightChanged: releaseAllSpace()

            function releaseAllSpace(): void {
                for (const item of children) {
                    if (item instanceof ContainmentLayoutManager.ItemContainer && item !== placeHolder) {
                        releaseSpace(item);
                    }
                }
            }

            eventManagerToFilter: (folderViewLayer.item as FolderViewLayer)?.view.view ?? null

            appletContainerComponent: ContainmentLayoutManager.BasicAppletContainer {
                id: appletContainer

                editModeCondition: Plasmoid.immutable
                    ? ContainmentLayoutManager.ItemContainer.Locked
                    : ContainmentLayoutManager.ItemContainer.AfterPressAndHold

                readonly property bool isShortcut: applet?.plasmoid.pluginName === "org.kde.plasma.icon"

                // In grid mode, the drop geometry is computed here rather than by the
                // layout, which would resize the widget to whole cells and ignores screen edges:
                // - widgets keep their size, shortcuts fill one cell
                // - the widget goes to the nearest grid line, or to the screen edge if closer
                // The placeholder shows that same geometry while dragging.

                property size sizeBeforeDrag
                property point dragPosition // position while dragged, before any snapping
                property bool dragged: false

                onDragActiveChanged: {
                    if (dragActive) {
                        sizeBeforeDrag = Qt.size(width, height);
                        return;
                    }
                    if (!dragged) {
                        return;
                    }
                    dragged = false;
                    if (!root.gridMode) {
                        return;
                    }

                    const geometry = dropGeometry(dragPosition);
                    x = geometry.x;
                    y = geometry.y;
                    width = geometry.width;
                    height = geometry.height;
                    root.saveLayoutLater();
                }

                function dropGeometry(position: point): rect {
                    const size = isShortcut
                        ? Qt.size(appletsLayout.cellWidth, appletsLayout.cellHeight)
                        : sizeBeforeDrag;

                    const x = snap(position.x, appletsLayout.cellWidth, appletsLayout.width - size.width);
                    const y = snap(position.y, appletsLayout.cellHeight, appletsLayout.height - size.height);
                    return Qt.rect(x, y, size.width, size.height);
                }

                // Nearest grid line, or the edge (0 or max) if it is closer
                function snap(position: real, cellSize: real, max: real): real {
                    const onGrid = Math.round(position / cellSize) * cellSize;
                    const toGrid = Math.abs(position - onGrid);
                    if (Plasmoid.configuration.gridSnapToEdges) {
                        if (position < toGrid) {
                            return 0;
                        }
                        if (max - position < toGrid) {
                            return max;
                        }
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

            GridLines {
                anchors.fill: parent
                z: -1
                visible: root.gridMode
                cellWidth: appletsLayout.cellWidth
                cellHeight: appletsLayout.cellHeight
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
            shortcutIconSize: root.shortcutIconSize
            shortcutLabelHeight: root.shortcutLabelHeight
            onResizeShortcutsRequested: root.resizeAllShortcuts()
            onShortcutIconSizeRequested: size => root.setShortcutIconSize(size)
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
