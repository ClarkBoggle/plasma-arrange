/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

// Small floating panel shown in grid mode (desktop edit mode), to set up the grids
// (see GridArrange.qml).
// It can be moved by dragging its title.
// Translations: po/ in the project, built into contents/locale/ (see build-translations.sh).
KSvg.FrameSvgItem {
    id: gridPanel

    imagePath: "widgets/background"

    // Inner room around the content, besides the frame margins
    readonly property real padding: Kirigami.Units.largeSpacing

    width: Math.max(content.implicitWidth, Kirigami.Units.gridUnit * 14) + margins.left + margins.right + 2 * padding
    height: content.implicitHeight + margins.top + margins.bottom + 2 * padding

    // Whether the Plasmoids tab is shown: the desktop then shows the plasmoid grid
    readonly property bool plasmoidsTab: tabBar.currentIndex === 1

    // function (): height of the tallest shortcut, the lowest possible shortcut cell
    property var tallestShortcutHeight
    // function (cellWidth, cellHeight): largest icon size keeping shortcuts inside their cell
    property var largestIconSize

    // New shortcut cell size or icon size: the grid and the shortcuts follow
    signal shortcutGridChangeRequested(int cellWidth, int cellHeight, int iconSize)
    signal snapPlasmoidsRequested()
    // Keeps the changes and leaves edit mode
    signal saveRequested()
    // Puts everything back as it was when edit mode started, and leaves it
    signal cancelRequested()

    // Asks for a change of the shortcut grid, the other values staying as they are.
    // A shortcut, as wide as its cell, is never narrower than its icon, an icon cannot
    // be so big that a shortcut overflows its cell, and the cells cannot be made
    // lower than the tallest shortcut.
    function changeShortcutGrid(changes: var): void {
        const config = Plasmoid.configuration;
        const cellHeight = changes.cellHeight !== undefined
            ? Math.max(changes.cellHeight, Math.ceil(tallestShortcutHeight()))
            : config.gridCellHeight;
        let iconSize = changes.iconSize ?? config.gridIconSize;
        const cellWidth = Math.max(changes.cellWidth ?? config.gridCellWidth, iconSize);
        if (changes.iconSize !== undefined) {
            iconSize = Math.min(iconSize, largestIconSize(cellWidth, cellHeight));
        }
        shortcutGridChangeRequested(cellWidth, cellHeight, iconSize);
    }

    // Changes the plasmoid cell size. When width and height are linked, the other one
    // follows, keeping the cell proportions.
    function changePlasmoidCell(changes: var): void {
        const config = Plasmoid.configuration;
        let width = changes.width ?? config.gridPlasmoidCellWidth;
        let height = changes.height ?? config.gridPlasmoidCellHeight;
        if (config.gridPlasmoidCellLinked) {
            if (changes.width !== undefined) {
                height = Math.max(8, Math.round(config.gridPlasmoidCellHeight * width / config.gridPlasmoidCellWidth));
            } else {
                width = Math.max(8, Math.round(config.gridPlasmoidCellWidth * height / config.gridPlasmoidCellHeight));
            }
        }
        config.gridPlasmoidCellWidth = width;
        config.gridPlasmoidCellHeight = height;
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
                text: i18nc("@title", "Arrange")
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
                text: i18nc("@title:tab desktop shortcuts (Icon widgets)", "Shortcuts")
            }
            PlasmaComponents3.TabButton {
                text: i18nc("@title:tab other desktop widgets", "Plasmoids")
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
                    text: i18nc("@label:spinbox", "Cell size:")
                }

                PlasmaComponents3.SpinBox {
                    from: 16
                    to: 1024
                    stepSize: 8
                    value: Plasmoid.configuration.gridCellWidth
                    onValueModified: {
                        gridPanel.changeShortcutGrid({ cellWidth: value });
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
                    onValueModified: {
                        gridPanel.changeShortcutGrid({ cellHeight: value });
                        value = Qt.binding(() => Plasmoid.configuration.gridCellHeight);
                    }
                }

                // Icon size of the shortcuts (a shortcut is as wide as its cell)
                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignRight
                    text: i18nc("@label:spinbox", "Icon size:")
                }

                PlasmaComponents3.SpinBox {
                    from: 16
                    to: 256
                    stepSize: 8
                    value: Plasmoid.configuration.gridIconSize
                    onValueModified: {
                        gridPanel.changeShortcutGrid({ iconSize: value });
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
                        text: i18nc("@label:spinbox", "Cell size:")
                    }

                    PlasmaComponents3.SpinBox {
                        from: 8
                        to: 1024
                        stepSize: 8
                        value: Plasmoid.configuration.gridPlasmoidCellWidth
                        onValueModified: {
                            gridPanel.changePlasmoidCell({ width: value });
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
                            gridPanel.changePlasmoidCell({ height: value });
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
                        text: i18nc("@action:button", "Link width and height")
                        PlasmaComponents3.ToolTip.text: text
                        PlasmaComponents3.ToolTip.visible: hovered
                        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 0

                PlasmaComponents3.CheckBox {
                    id: snapToEdgesCheckBox
                    text: i18nc("@option:check", "Snap to screen edges")
                    checked: Plasmoid.configuration.gridSnapToEdges
                    onToggled: Plasmoid.configuration.gridSnapToEdges = checked
                }

                // Under the check box text: which edges (the grids start at the left/top edges)
                PlasmaComponents3.Label {
                    Layout.leftMargin: snapToEdgesCheckBox.indicator.width + snapToEdgesCheckBox.spacing
                    text: i18nc("@info screen edges the widgets snap to", "(Right and Bottom)")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // Plasmoids tab: snaps the edges of every plasmoid to their grid.
            // Only hidden in the Shortcuts tab, so that the panel keeps the same width
            // in both tabs.
            PlasmaComponents3.Button {
                opacity: gridPanel.plasmoidsTab ? 1 : 0
                enabled: gridPanel.plasmoidsTab
                icon.name: "snap-nodes-cusp"
                text: i18nc("@action:button snap plasmoids to the grid", "Snap to Grid")
                onClicked: gridPanel.snapPlasmoidsRequested()
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.largeSpacing * 2

            PlasmaComponents3.Button {
                icon.name: "document-save"
                text: i18nc("@action:button keep the changes and leave grid mode", "Save")
                onClicked: gridPanel.saveRequested()
            }

            PlasmaComponents3.Button {
                icon.name: "dialog-cancel"
                text: i18nc("@action:button undo all changes and leave grid mode", "Cancel")
                onClicked: gridPanel.cancelRequested()
            }
        }
    }
}
