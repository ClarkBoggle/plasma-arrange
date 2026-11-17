// The Arrange Desktop panel, Shortcuts tab (left) and Plasmoids tab (right).
// Rendered by render.sh: qml6 panel.qml -- <output.png>

import QtQuick

Rectangle {
    id: scene

    width: 734
    height: 332

    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#1e3a5f" }
        GradientStop { position: 1; color: "#3c5f87" }
    }

    GridPanel {
        x: 24
        y: 24
        tallestShortcutHeight: () => 92
        largestIconSize: () => 56
    }

    GridPanel {
        x: 379
        y: 24
        tallestShortcutHeight: () => 92
        largestIconSize: () => 56
        Component.onCompleted: showTab(true)
    }

    Timer {
        running: true
        interval: 1500
        onTriggered: scene.grabToImage(result => {
            result.saveToFile(Qt.application.arguments[Qt.application.arguments.length - 1]);
            Qt.quit();
        })
    }
}
