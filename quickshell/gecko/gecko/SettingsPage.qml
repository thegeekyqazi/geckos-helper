import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    clip: true
    contentHeight: column.implicitHeight

    ColumnLayout {
        id: column
        x: 14
        width: root.width - 28
        spacing: 6

        StyledText {
            text: "What Gecko can access"
            font.pixelSize: Appearance.font.pixelSize.large
            color: Theme.text
            Layout.leftMargin: 4
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: "Checked on every tool call, so changes apply mid-chat."
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Theme.textMuted
        }

        Repeater {
            model: Object.keys(Gecko.capabilityDescriptions)
            delegate: RowLayout {
                id: capRow
                required property string modelData
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: capRow.modelData.replace(/_/g, " ").replace(/^./, c => c.toUpperCase())
                        color: Theme.text
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Gecko.capabilityDescriptions[capRow.modelData]
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Theme.textMuted
                    }
                }
                StyledSwitch {
                    checked: Gecko.capabilities[capRow.modelData] ?? false
                    onClicked: Gecko.setCapability(capRow.modelData, checked)
                }
            }
        }

        Item { implicitHeight: 8 }

        RowLayout {
            Layout.leftMargin: 4
            spacing: 8
            DialogButton {
                id: ctxButton
                buttonText: "Refresh tools context"
                onClicked: {
                    buttonText = "Refreshing…";
                    Gecko.regenerateContext(() => ctxButton.buttonText = "Refreshed");
                }
            }
            StyledText {
                text: `Default model: ${Gecko.defaultModel}`
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Theme.textMuted
            }
        }
    }
}
