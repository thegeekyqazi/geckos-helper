import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Model picker. Click a model to use it for this chat; the star makes it the
 * default for new chats.
 */
Rectangle {
    id: root
    property bool shown: false
    visible: shown
    z: 10
    implicitWidth: 220
    implicitHeight: column.implicitHeight + 12
    radius: Appearance.rounding.normal
    color: Appearance.colors.colSurfaceContainerHigh
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        StyledText {
            Layout.margins: 6
            text: "Model"
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: Gecko.models
            delegate: RippleButton {
                id: row
                required property string modelData
                Layout.fillWidth: true
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                toggled: (Gecko.chatModel || Gecko.defaultModel) === modelData
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: {
                    Gecko.setModel(modelData);
                    root.shown = false;
                }
                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData
                        color: row.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                    RippleButton {
                        implicitWidth: 28
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.full
                        onClicked: Gecko.setDefaultModel(row.modelData)
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "star"
                            fill: Gecko.defaultModel === row.modelData ? 1 : 0
                            color: Gecko.defaultModel === row.modelData ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                        StyledToolTip { text: "Make default for new chats" }
                    }
                }
            }
        }
    }
}
