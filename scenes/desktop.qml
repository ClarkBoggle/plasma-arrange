// A desktop in edit mode, as Plasma shows it (desktop slightly shrunk, toolbar
// above it), with the grid, the Arrange Desktop panel, shortcuts and plasmoids
// placed as GridArrange places them, and a selected widget.
// Rendered by render.sh: qml6 desktop.qml -- <output.png> <shortcuts|plasmoids>

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PlasmaComponents

import "fake.js" as Fake

Item {
    id: scene

    width: 1920
    height: 1080

    readonly property var args: Qt.application.arguments
    readonly property string output: args[args.length - 2]
    readonly property bool plasmoidsTab: args[args.length - 1] === "plasmoids"

    readonly property var config: Fake.configuration

    Image {
        anchors.fill: parent
        source: "wallpaper-blurred.png"
    }

    // --- Edit mode toolbar --------------------------------------------------

    Rectangle {
        x: desktop.x
        y: 36
        width: desktop.width * desktop.scale
        height: desktop.y - y
        color: "#cc202326"

        Row {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            ToolbarButton { icon: "view-app-grid-symbolic"; text: "Add or Manage Widgets…" }
            ToolbarButton { icon: "list-add-symbolic"; text: "Add Panel" }
            ToolbarButton { icon: "configure-symbolic"; text: "Manage Desktops and Panels…" }
        }
        ToolbarButton {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            icon: "dialog-ok-symbolic"
            text: "Exit Edit Mode"
        }
    }

    component ToolbarButton: Row {
        property alias icon: buttonIcon.source
        property alias text: label.text
        spacing: 6
        Kirigami.Icon {
            id: buttonIcon
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            color: "#fcfcfc"
            isMask: true
        }
        PlasmaComponents.Label {
            id: label
            color: "#fcfcfc"
        }
    }

    // --- Desktop ---------------------------------------------------------

    Item {
        id: desktop

        x: 96
        y: 65
        width: 1920
        height: 1080
        scale: 0.9
        transformOrigin: Item.TopLeft
        clip: true

        Image {
            anchors.fill: parent
            source: "wallpaper.png"
        }

        GridLines {
            anchors.fill: parent
            cellWidth: scene.plasmoidsTab ? scene.config.gridPlasmoidCellWidth : scene.config.gridCellWidth
            cellHeight: scene.plasmoidsTab ? scene.config.gridPlasmoidCellHeight : scene.config.gridCellHeight
        }

        // Shortcuts, in their cells (column, row), the trash in the bottom right corner
        Shortcut { name: "Home"; icon: "user-home"; column: 0; row: 0 }
        Shortcut { name: "Documents"; icon: "folder-documents"; column: 0; row: 1 }
        Shortcut { name: "Downloads"; icon: "folder-download"; column: 0; row: 2 }
        Shortcut { name: "Pictures"; icon: "folder-pictures"; column: 0; row: 3 }
        Shortcut { name: "Music"; icon: "folder-music"; column: 0; row: 4 }
        Shortcut { name: "System Settings"; icon: "systemsettings"; column: 1; row: 0 }
        Shortcut { name: "Okular"; icon: "okular"; column: 1; row: 1 }
        Shortcut { name: "Gwenview"; icon: "org.kde.gwenview"; column: 1; row: 2 }
        Shortcut { name: "Elisa"; icon: "org.kde.elisa"; column: 1; row: 3 }
        Shortcut { name: "Kate"; icon: "kate"; column: 2; row: 0 }
        Shortcut { name: "Spectacle"; icon: "spectacle"; column: 2; row: 1 }
        Shortcut { id: kcalc; name: "KCalc"; icon: "accessories-calculator"; column: 2; row: 2 }
        Shortcut {
            name: "Trash"
            icon: "user-trash-full"
            x: desktop.width - width
            y: desktop.height - height
        }

        // Plasmoids, on the 16 px plasmoid grid
        Clock { x: 1536; y: 64; width: 304; height: 176 }
        Note { x: 1552; y: 320; width: 288; height: 240 }
        CpuUsage { id: cpu; x: 1536; y: 640; width: 304; height: 176 }

        // The selected widget of the tab shown
        Handles {
            target: scene.plasmoidsTab ? cpu : kcalc
            toolbarOnLeft: scene.plasmoidsTab
            backgroundButton: scene.plasmoidsTab
        }

        GridPanel {
            x: Math.round((desktop.width - width) / 2)
            y: Kirigami.Units.gridUnit * 2
            tallestShortcutHeight: () => 92
            largestIconSize: () => 56
            Component.onCompleted: showTab(scene.plasmoidsTab)
        }
    }

    // --- Widgets -----------------------------------------------------------

    // Height of a 2 lines name, for the vertical offset of the shortcuts (as GridArrange)
    PlasmaComponents.Label {
        id: twoLinesName
        visible: false
        text: "X\nX"
    }

    component Shortcut: Item {
        property string name
        property alias icon: shortcutIcon.source
        property int column
        property int row

        readonly property int iconSize: scene.config.gridIconSize
        readonly property real offsetY: Math.max(0, Math.round(
            (scene.config.gridCellHeight - iconSize - twoLinesName.implicitHeight) / 2))

        x: column * scene.config.gridCellWidth
        y: row * scene.config.gridCellHeight + offsetY
        width: scene.config.gridCellWidth
        height: iconSize + label.implicitHeight

        Kirigami.Icon {
            id: shortcutIcon
            width: parent.iconSize
            height: parent.iconSize
            anchors.horizontalCenter: parent.horizontalCenter
        }
        PlasmaComponents.Label {
            id: label
            y: parent.iconSize
            width: parent.width
            text: parent.name
            color: "white"
            style: Text.Outline
            styleColor: "#40000000"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    component Clock: KSvg.FrameSvgItem {
        imagePath: "widgets/background"
        Column {
            anchors.centerIn: parent
            spacing: 4
            PlasmaComponents.Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "10:42"
                font.pixelSize: 72
                font.weight: Font.Light
            }
            PlasmaComponents.Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Tuesday, November 17"
                opacity: 0.8
            }
        }
    }

    component Note: Rectangle {
        color: "#f8ecc2"
        PlasmaComponents.Label {
            anchors.fill: parent
            anchors.margins: 14
            text: "To do:\n• send the invoice\n• call the plumber\n• backup photos"
            color: "#31363b"
            font.pixelSize: 18
            lineHeight: 1.1
        }
    }

    component CpuUsage: KSvg.FrameSvgItem {
        imagePath: "widgets/background"
        PlasmaComponents.Label {
            x: 14
            y: 12
            text: "CPU Usage"
            font.pixelSize: 13
        }
        PlasmaComponents.Label {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 12
            text: "23 %"
            font.pixelSize: 13
            font.bold: true
        }
        Canvas {
            x: 14
            y: 44
            width: parent.width - 28
            height: parent.height - 60
            onPaint: {
                const ctx = getContext("2d");
                const values = [0.15, 0.25, 0.1, 0.55, 0.4, 0.75, 0.35, 0.2, 0.3, 0.15, 0.4, 0.6, 0.3, 0.2, 0.35];
                const step = width / (values.length - 1);
                ctx.beginPath();
                ctx.moveTo(0, height);
                values.forEach((value, i) => ctx.lineTo(i * step, height * (1 - value)));
                ctx.lineTo(width, height);
                ctx.closePath();
                ctx.fillStyle = "#30226e60";
                ctx.fill();
                ctx.beginPath();
                values.forEach((value, i) => ctx.lineTo(i * step, height * (1 - value)));
                ctx.strokeStyle = "#1abc9c";
                ctx.lineWidth = 2;
                ctx.stroke();
            }
        }
    }

    // Plasma's handles around the selected widget: resize handles at the corners and
    // middle of the sides, and a toolbar beside it
    component Handles: Item {
        property Item target
        property bool toolbarOnLeft
        property bool backgroundButton

        anchors.fill: parent

        Repeater {
            model: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]]
            Rectangle {
                required property var modelData
                width: 22
                height: 22
                radius: 11
                x: target.x + modelData[0] * target.width - width / 2
                y: target.y + modelData[1] * target.height - height / 2
                color: "#31363b"
                border.color: "#a0a8b0"
                border.width: 2
            }
        }

        KSvg.FrameSvgItem {
            imagePath: "widgets/background"
            width: 44
            height: Math.max(target.height, 176)
            x: toolbarOnLeft ? target.x - width - 26 : target.x + target.width + 26
            y: target.y + (target.height - height) / 2

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 10
                spacing: 12
                Kirigami.Icon { width: 22; height: 22; source: "object-rotate-right" }
                Kirigami.Icon { width: 22; height: 22; source: "configure" }
                Rectangle {
                    visible: backgroundButton
                    width: 22
                    height: 22
                    radius: 3
                    color: "#3d1abc9c"
                    border.color: "#1abc9c"
                    Kirigami.Icon { anchors.centerIn: parent; width: 16; height: 16; source: "draw-text" }
                }
            }
            Kirigami.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                width: 22
                height: 22
                source: "edit-delete-remove"
                color: Kirigami.Theme.negativeTextColor
                isMask: true
            }
        }
    }

    Timer {
        running: true
        interval: 2000
        onTriggered: scene.grabToImage(result => {
            result.saveToFile(scene.output);
            Qt.quit();
        })
    }
}
