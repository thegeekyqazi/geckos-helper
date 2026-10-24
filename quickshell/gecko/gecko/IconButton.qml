import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Round icon-only button with an optional tooltip.
RippleButton {
    id: root
    property string iconName
    property string tip
    property color iconColor: Theme.textMuted
    property real size: 34
    implicitWidth: size
    implicitHeight: size
    buttonRadius: Appearance.rounding.full
    colBackground: "transparent"
    colBackgroundHover: Theme.surfaceHigh
    colRipple: Theme.border

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.iconName
        iconSize: root.size * 0.58
        color: root.iconColor
    }

    StyledToolTip {
        text: root.tip
        extraVisibleCondition: root.tip.length > 0
    }
}
