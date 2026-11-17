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
KSvg.FrameSvgItem {
    id: gridPanel

    imagePath: "widgets/background"

    width: content.implicitWidth + margins.left + margins.right
    height: content.implicitHeight + margins.top + margins.bottom

    // Icon size of the shortcuts placed on this grid
    property int shortcutIconSize
    // Room taken by a 2 lines shortcut name
    property int shortcutLabelHeight

    // All shortcut icons have the same size only if the cell is tall enough
    readonly property bool equalIcons: Plasmoid.configuration.gridCellWidth
        <= Plasmoid.configuration.gridCellHeight - shortcutLabelHeight

    signal resizeShortcutsRequested()
    // New icon size chosen with the slider: the grid and the shortcuts follow
    signal shortcutIconSizeRequested(int size)

    ColumnLayout {
        id: content

        anchors {
            fill: parent
            leftMargin: gridPanel.margins.left
            topMargin: gridPanel.margins.top
            rightMargin: gridPanel.margins.right
            bottomMargin: gridPanel.margins.bottom
        }

        spacing: Kirigami.Units.smallSpacing

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
                text: i18nc("@title", "Grid")
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

        // Cell size: width × height
        RowLayout {
            PlasmaComponents3.Label {
                text: i18nc("@label:spinbox", "Cell size:")
            }

            PlasmaComponents3.SpinBox {
                from: 16
                to: 512
                stepSize: 8
                value: Plasmoid.configuration.gridCellWidth
                // The width is the shortcut icon size: same as the slider
                onValueModified: gridPanel.shortcutIconSizeRequested(value)
            }

            PlasmaComponents3.Label {
                text: "×"
            }

            PlasmaComponents3.SpinBox {
                from: 16
                to: 512
                stepSize: 8
                value: Plasmoid.configuration.gridCellHeight
                onValueModified: Plasmoid.configuration.gridCellHeight = value
            }
        }

        // Icon size: cell = icon size × (icon size + 2 lines for the name)
        RowLayout {
            PlasmaComponents3.Label {
                text: i18nc("@label:slider", "Icon size:")
            }

            PlasmaComponents3.Slider {
                Layout.fillWidth: true
                from: 32
                to: 256
                stepSize: 8
                value: Plasmoid.configuration.gridCellWidth
                onMoved: gridPanel.shortcutIconSizeRequested(value)
            }

            PlasmaComponents3.Label {
                text: i18nc("@label size in pixels", "%1 px", Plasmoid.configuration.gridCellWidth)
            }
        }

        // Shortcuts fill their cell
        RowLayout {
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: gridPanel.equalIcons
                    ? i18nc("@info", "Shortcut icons: %1 px", gridPanel.shortcutIconSize)
                    : i18nc("@info", "Cells too wide: icon sizes vary")
            }

            PlasmaComponents3.Button {
                text: i18nc("@action:button resize shortcuts and snap them to the grid", "Resize and Snap")
                onClicked: gridPanel.resizeShortcutsRequested()
            }
        }

        PlasmaComponents3.CheckBox {
            text: i18nc("@option:check", "Snap to screen edges")
            checked: Plasmoid.configuration.gridSnapToEdges
            onToggled: Plasmoid.configuration.gridSnapToEdges = checked
        }

        PlasmaComponents3.Button {
            Layout.alignment: Qt.AlignRight
            icon.name: "dialog-ok"
            text: i18nc("@action:button leave grid mode", "Done")
            onClicked: Plasmoid.containment.corona.editMode = false
        }
    }
}
