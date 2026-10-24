import QtQuick
import qs.modules.common.widgets

// Text with the theme's font and colors.
StyledText {
    property bool muted: false
    property real rel: 1  // size relative to the theme font size
    font.family: Theme.font
    font.pixelSize: Theme.fontSize * rel
    color: muted ? Theme.textMuted : Theme.text
    wrapMode: Text.Wrap
}
