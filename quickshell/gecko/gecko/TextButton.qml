import QtQuick
import qs.modules.common.widgets

// Text actions grow with the chosen font size. Width can be capped by the caller.
RippleButton {
    id: root
    property string label
    implicitHeight: labelText.implicitHeight + 18
    implicitWidth: labelText.implicitWidth + 28
    buttonRadius: Theme.cardRadius
    colBackground: Theme.surfaceHigh
    colBackgroundHover: Theme.surface
    colRipple: Theme.border
    contentItem: GText {
        id: labelText
        text: root.label
        rel: 0.85
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
