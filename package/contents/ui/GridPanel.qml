/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

// Small floating panel shown in grid mode (desktop edit mode), to set up the grid.
// It can be moved by dragging its title.
// The interface stays in English: the i18n contexts end with "grid panel" so that
// no existing translation of the desktop containment is picked up.
KSvg.FrameSvgItem {
    id: gridPanel

    imagePath: "widgets/background"

    // Inner room around the content, besides the frame margins
    readonly property real padding: Kirigami.Units.largeSpacing

    width: Math.max(content.implicitWidth, Kirigami.Units.gridUnit * 14) + margins.left + margins.right + 2 * padding
    height: content.implicitHeight + margins.top + margins.bottom + 2 * padding

    // Whether the Plasmoids tab is shown: the desktop then shows the plasmoid grid
    readonly property bool plasmoidsTab: tabBar.currentIndex === 1

    // function (): size of the largest shortcut, the smallest possible cell size
    property var largestShortcutSize
    // function (cellWidth, cellHeight): largest icon size keeping shortcuts inside their cell
    property var largestIconSize

    signal snapPlasmoidsRequested()
    // Puts everything back as it was when grid mode started
    signal cancelRequested()

    // New cell size or icon size chosen in the panel: the grid and the shortcuts follow
    signal gridChangeRequested(int cellWidth, int cellHeight, int iconSize)

    // Asks for a change of one value, the others staying as they are.
    // A shortcut, as wide as its cell, is never narrower than its icon, and an icon
    // cannot be so big that a shortcut overflows its cell.
    function requestChange(changes: var): void {
        const config = Plasmoid.configuration;
        const cellHeight = changes.cellHeight ?? config.gridCellHeight;
        let iconSize = changes.iconSize ?? config.gridIconSize;
        const cellWidth = Math.max(changes.cellWidth ?? config.gridCellWidth, iconSize);
        if (changes.iconSize !== undefined) {
            iconSize = Math.min(iconSize, largestIconSize(cellWidth, cellHeight));
        }
        gridChangeRequested(cellWidth, cellHeight, iconSize);
    }

    ColumnLayout {
        id: content

        anchors {
            fill: parent
            leftMargin: gridPanel.margins.left + gridPanel.padding
            topMargin: gridPanel.margins.top + gridPanel.padding
            rightMargin: gridPanel.margins.right + gridPanel.padding
            bottomMargin: gridPanel.margins.bottom + gridPanel.padding
        }

        spacing: Kirigami.Units.largeSpacing

        // Title, also used to move the panel
        RowLayout {
            Layout.fillWidth: true

            Kirigami.Icon {
                source: "view-grid"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: i18nc("@title, grid panel", "Arrange")
            }

            HoverHandler {
                cursorShape: Qt.SizeAllCursor
            }

            DragHandler {
                target: gridPanel
                xAxis.minimum: 0
                xAxis.maximum: gridPanel.parent.width - gridPanel.width
                yAxis.minimum: 0
                yAxis.maximum: gridPanel.parent.height - gridPanel.height
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        PlasmaComponents3.TabBar {
            id: tabBar
            Layout.fillWidth: true

            PlasmaComponents3.TabButton {
                text: i18nc("@title:tab desktop shortcuts (Icon widgets), grid panel", "Shortcuts")
            }
            PlasmaComponents3.TabButton {
                text: i18nc("@title:tab other desktop widgets, grid panel", "Plasmoids")
            }
        }

        StackLayout {
            currentIndex: tabBar.currentIndex
            // As tall as the tab shown, so that a shorter tab leaves no empty space
            Layout.preferredHeight: children[currentIndex]?.implicitHeight ?? 0

            // Shortcuts: their grid and their size
            GridLayout {
                columns: 4
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.largeSpacing

                // Cell size: width × height
                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignRight
                    Layout.minimumWidth: plasmoidsCellLabel.implicitWidth
                    text: i18nc("@label:spinbox, grid panel", "Cell size:")
                }

                PlasmaComponents3.SpinBox {
                    from: 16
                    to: 1024
                    stepSize: 8
                    value: Plasmoid.configuration.gridCellWidth
                    onValueModified: {
                        gridPanel.requestChange({ cellWidth: value });
                        // Changing the value by hand breaks the binding: restore it
                        value = Qt.binding(() => Plasmoid.configuration.gridCellWidth);
                    }
                }

                PlasmaComponents3.Label {
                    text: "×"
                }

                PlasmaComponents3.SpinBox {
                    from: 16
                    to: 1024
                    stepSize: 8
                    value: Plasmoid.configuration.gridCellHeight
                    // Cells cannot be lower than the tallest shortcut
                    onValueModified: {
                        gridPanel.requestChange({ cellHeight: Math.max(value, Math.ceil(gridPanel.largestShortcutSize().height)) });
                        value = Qt.binding(() => Plasmoid.configuration.gridCellHeight);
                    }
                }

                // Icon size of the shortcuts (a shortcut is as wide as its cell)
                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignRight
                    text: i18nc("@label:spinbox, grid panel", "Icon size:")
                }

                PlasmaComponents3.SpinBox {
                    from: 16
                    to: 256
                    stepSize: 8
                    value: Plasmoid.configuration.gridIconSize
                    onValueModified: {
                        gridPanel.requestChange({ iconSize: value });
                        value = Qt.binding(() => Plasmoid.configuration.gridIconSize);
                    }
                }

            }

            // Plasmoids: their own grid; they keep their size.
            // Same columns as the Shortcuts tab, so that both look alike.
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        id: plasmoidsCellLabel
                        Layout.alignment: Qt.AlignRight
                        text: i18nc("@label:spinbox, grid panel", "Cell size:")
                    }

                    PlasmaComponents3.SpinBox {
                        from: 8
                        to: 1024
                        stepSize: 8
                        value: Plasmoid.configuration.gridPlasmoidCellWidth
                        onValueModified: {
                            const config = Plasmoid.configuration;
                            // Linked: the height follows, keeping the cell proportions
                            if (config.gridPlasmoidCellLinked) {
                                config.gridPlasmoidCellHeight = Math.max(8, Math.round(
                                    config.gridPlasmoidCellHeight * value / config.gridPlasmoidCellWidth));
                            }
                            config.gridPlasmoidCellWidth = value;
                            value = Qt.binding(() => Plasmoid.configuration.gridPlasmoidCellWidth);
                        }
                    }

                    PlasmaComponents3.Label {
                        text: "×"
                    }

                    PlasmaComponents3.SpinBox {
                        from: 8
                        to: 1024
                        stepSize: 8
                        value: Plasmoid.configuration.gridPlasmoidCellHeight
                        onValueModified: {
                            const config = Plasmoid.configuration;
                            // Linked: the width follows, keeping the cell proportions
                            if (config.gridPlasmoidCellLinked) {
                                config.gridPlasmoidCellWidth = Math.max(8, Math.round(
                                    config.gridPlasmoidCellWidth * value / config.gridPlasmoidCellHeight));
                            }
                            config.gridPlasmoidCellHeight = value;
                            value = Qt.binding(() => Plasmoid.configuration.gridPlasmoidCellHeight);
                        }
                    }

                    // Links width and height: changing one changes the other
                    PlasmaComponents3.ToolButton {
                        icon.name: "link"
                        checkable: true
                        checked: Plasmoid.configuration.gridPlasmoidCellLinked
                        onToggled: Plasmoid.configuration.gridPlasmoidCellLinked = checked
                        display: PlasmaComponents3.AbstractButton.IconOnly
                        text: i18nc("@action:button, grid panel", "Link width and height")
                        PlasmaComponents3.ToolTip.text: text
                        PlasmaComponents3.ToolTip.visible: hovered
                        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }
            }
        }

        RowLayout {
            PlasmaComponents3.CheckBox {
                Layout.fillWidth: true
                text: i18nc("@option:check, grid panel", "Snap to screen edges")
                checked: Plasmoid.configuration.gridSnapToEdges
                onToggled: Plasmoid.configuration.gridSnapToEdges = checked
            }

            // Plasmoids tab: snaps the edges of every plasmoid to their grid
            PlasmaComponents3.Button {
                visible: gridPanel.plasmoidsTab
                icon.name: "snap-nodes-cusp"
                text: i18nc("@action:button snap plasmoids to the grid, grid panel", "Snap to Grid")
                onClicked: gridPanel.snapPlasmoidsRequested()
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Button {
                icon.name: "document-save"
                text: i18nc("@action:button keep the changes and leave grid mode, grid panel", "Save")
                onClicked: Plasmoid.containment.corona.editMode = false
            }

            PlasmaComponents3.Button {
                icon.name: "dialog-cancel"
                text: i18nc("@action:button undo all changes and leave grid mode, grid panel", "Cancel")
                onClicked: gridPanel.cancelRequested()
            }
        }
    }
}
