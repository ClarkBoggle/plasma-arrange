/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Grid computations of GridArrange, without anything of Plasma: tested by
// tests/tst_gridmath.qml. Geometries are anything with x, y, width and height.
.pragma library

// The value kept between 0 and max
function clamp(value, max) {
    return Math.max(0, Math.min(value, max));
}

// Nearest grid line (lines every cellSize from offset) between 0 and max, or max
// itself (the right/bottom edge) if toEdges and it is closer
function snap(position, offset, cellSize, max, toEdges) {
    max = Math.max(0, max); // (something larger than the screen starts at 0)
    const onGrid = Math.round((position - offset) / cellSize) * cellSize + offset;
    if (toEdges && max - position < Math.abs(position - onGrid)) {
        return max;
    }
    return clamp(onGrid, max);
}

// Grid lines from offset to max, and max itself if withMax
function gridLines(offset, cellSize, max, withMax) {
    const lines = [];
    for (let line = Math.max(0, offset); line <= max; line += cellSize) {
        lines.push(line);
    }
    if (withMax && max >= 0 && lines[lines.length - 1] !== max) {
        lines.push(max);
    }
    return lines;
}

// The geometry overlaps one of the others (more than by rounding errors)
function overlapsAny(geometry, others) {
    return others.some(other =>
        Math.min(geometry.x + geometry.width, other.x + other.width) - Math.max(geometry.x, other.x) > 1
        && Math.min(geometry.y + geometry.height, other.y + other.height) - Math.max(geometry.y, other.y) > 1);
}

// Position { x, y } nearest to the geometry, among the xs and ys, where it
// overlaps none of the others; null if there is none.
// Positions are tried from the nearest: the search stops as soon as the ones left
// are farther than the one found.
function nearestFree(geometry, others, xs, ys) {
    const fromNearest = (lines, from) => lines.slice().sort((a, b) => Math.abs(a - from) - Math.abs(b - from));
    const nearYs = fromNearest(ys, geometry.y);
    let nearest = null;
    let nearestDistance = Infinity;
    for (const x of fromNearest(xs, geometry.x)) {
        const distanceX = (x - geometry.x) * (x - geometry.x);
        if (distanceX >= nearestDistance) {
            break;
        }
        for (const y of nearYs) {
            const distance = distanceX + (y - geometry.y) * (y - geometry.y);
            if (distance >= nearestDistance) {
                break;
            }
            if (!overlapsAny({ x, y, width: geometry.width, height: geometry.height }, others)) {
                nearest = { x, y };
                nearestDistance = distance;
                break;
            }
        }
    }
    return nearest;
}
