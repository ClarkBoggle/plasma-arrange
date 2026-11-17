/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.kirigami as Kirigami

// Draws the arrangement grid behind the desktop widgets.
// The origin is the top-left corner of the applets layout,
// which is also the origin of the grids used by GridArrange.
Canvas {
    id: gridLines

    property int cellWidth: Kirigami.Units.iconSizes.small
    property int cellHeight: Kirigami.Units.iconSizes.small

    onCellWidthChanged: requestPaint()
    onCellHeightChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();

        if (!visible || cellWidth < 4 || cellHeight < 4) {
            return;
        }

        ctx.strokeStyle = Kirigami.Theme.highlightColor;
        ctx.globalAlpha = 0.5;
        ctx.lineWidth = 1;
        ctx.beginPath();

        // +0.5 so that 1 px lines fall exactly on a pixel row/column
        for (let x = 0; x <= width; x += cellWidth) {
            ctx.moveTo(x + 0.5, 0);
            ctx.lineTo(x + 0.5, height);
        }
        for (let y = 0; y <= height; y += cellHeight) {
            ctx.moveTo(0, y + 0.5);
            ctx.lineTo(width, y + 0.5);
        }

        ctx.stroke();
    }
}
