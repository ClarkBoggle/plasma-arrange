// Stands for Plasma in the scenes: the grid settings (defaults of
// package/contents/config/main.xml, main branch) and the translation function.
.pragma library

var configuration = {
    gridCellWidth: 96,
    gridCellHeight: 92,
    gridIconSize: 56,
    gridPlasmoidCellWidth: 16,
    gridPlasmoidCellHeight: 16,
    gridPlasmoidCellLinked: true,
    gridSnapToEdges: true,
};

function i18nc(context, text) {
    return text;
}
