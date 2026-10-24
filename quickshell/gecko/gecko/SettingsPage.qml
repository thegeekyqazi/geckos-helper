import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    onVisibleChanged: if (visible) Gecko.refreshRules()
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

        GText {
            text: "Permission rules"
            rel: 1.1
            font.weight: Font.DemiBold
            Layout.leftMargin: 4
        }
        GText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: "Saved with \"Always\". Last matching rule wins. Edit patterns in ~/.config/geckos-helper/permission-rules.json"
            muted: true
            rel: 0.8
        }
        GText {
            Layout.leftMargin: 4
            visible: Gecko.rules.length === 0
            text: "No saved rules yet."
            muted: true
            rel: 0.85
        }
        Repeater {
            model: Gecko.rules
            delegate: RowLayout {
                id: ruleRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 8
                MaterialSymbol {
                    text: ruleRow.modelData.action === "allow" ? "check_circle" : "block"
                    color: ruleRow.modelData.action === "allow" ? Theme.accent : Theme.errorText
                    iconSize: 18
                }
                GText {
                    Layout.fillWidth: true
                    text: ruleRow.modelData.match
                    font.family: Theme.monoFont
                    rel: 0.8
                    elide: Text.ElideMiddle
                    wrapMode: Text.NoWrap
                }
                IconButton {
                    size: 28
                    iconName: "delete"
                    tip: "Remove rule"
                    onClicked: Gecko.removeRule(ruleRow.index)
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
