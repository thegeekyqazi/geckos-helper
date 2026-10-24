import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Model picker above the composer. Click a model to use it for this chat; the star
 * makes it the default for new chats.
 */
Rectangle {
    id: root
    property bool shown: false
    visible: shown
    z: 10
    implicitWidth: 230
    implicitHeight: column.implicitHeight + 12
    radius: Theme.cardRadius
    color: Theme.popup
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        GText {
            Layout.margins: 6
            text: "Model"
            muted: true
            rel: 0.75
        }

        Repeater {
            model: Gecko.models
            delegate: RippleButton {
                id: row
                required property string modelData
                readonly property bool current: (Gecko.chatModel || Gecko.defaultModel) === modelData
                Layout.fillWidth: true
                implicitHeight: 38
                buttonRadius: Theme.cardRadius - 4
                colBackground: "transparent"
                colBackgroundHover: Theme.surface
                colRipple: Theme.border
                onClicked: {
                    Gecko.setModel(modelData);
                    root.shown = false;
                }
                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 6
                    GText {
                        Layout.fillWidth: true
                        text: row.modelData.replace(/^./, c => c.toUpperCase())
                        rel: 0.93
                        wrapMode: Text.NoWrap
                    }
                    MaterialSymbol {
                        visible: row.current
                        text: "check"
                        color: Theme.accent
                        iconSize: 18
                    }
                    IconButton {
                        size: 28
                        iconName: "star"
                        iconColor: Gecko.defaultModel === row.modelData ? Theme.accent : Theme.textMuted
                        tip: Gecko.defaultModel === row.modelData ? "Default for new chats" : "Make default for new chats"
                        onClicked: Gecko.setDefaultModel(row.modelData)
                    }
                }
            }
        }
    }
}
