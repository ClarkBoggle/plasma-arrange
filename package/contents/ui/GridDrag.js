/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// State shared by all the desktops (one per screen and activity), as a library
// script is loaded once for the whole shell: a widget dragged to another screen
// leaves its desktop, and the desktop it reaches only gets its applet id. The
// desktop it comes from records here what the other one needs to show it; the
// desktops also record where moved widgets are, and when Cancel is clicked.
.pragma library

// Widget being moved, or null: { shortcut: bool, title: string, width: real,
// height: real, rotation: real, grabX: real, grabY: real } (grab: where the
// mouse holds it)
var widget = null;

// Desktop (containment id) where each widget moved to another screen now is, by
// applet id: to take it back on Cancel
var desktopOf = {};

// Cancel was clicked: every desktop restores its layout when grid mode ends
var cancelling = false;

// The GridArrange item of every desktop: the panels of plasma-pannel (another
// package, same shell) load this script too, and ask them the plasmoid grid of
// the screen of a popup (GridArrange.plasmoidCellOn())
var desktops = [];
