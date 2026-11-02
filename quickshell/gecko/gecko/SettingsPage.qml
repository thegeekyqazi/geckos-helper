import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    onVisibleChanged: if (visible) { Gecko.refreshRules(); Gecko.refreshPermissions(); }
    clip: true
    contentHeight: column.implicitHeight

    ColumnLayout {
        id: column
        x: 14
        width: root.width - 28
        spacing: 6

        GText { text: "Permissions"; rel: 1.15; font.weight: Font.DemiBold }
        GText { text: "Default for new chats"; font.weight: Font.DemiBold }
        PermissionPicker { Layout.fillWidth: true; forDefault: true }
        GText { Layout.fillWidth: true; text: "Current chat"; visible: !!Gecko.chatId; font.weight: Font.DemiBold }
        PermissionPicker { Layout.fillWidth: true; visible: !!Gecko.chatId }
        GText {
            Layout.fillWidth: true
            text: "Uses Claude Code's native modes. Changes apply on the next message; stop a running turn first. Defaults apply only to new chats. Auto depends on your Claude Code version, model and account."
            muted: true; rel: 0.8
        }
        GText {
            Layout.fillWidth: true
            text: "Full access skips native permission checks. Saved rules cover requests Claude sends for approval. A guard detection stops the chat in every mode until you review and clear it. Capability switches apply to Gecko tools; they do not restrict shell access. This is not Codex's OS sandbox. Background watchers and recipes remain read-only."
            muted: true; rel: 0.8
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border; Layout.topMargin: 8; Layout.bottomMargin: 8 }

        GText { text: "Display"; rel: 1.15; font.weight: Font.DemiBold }
        GText {
            Layout.fillWidth: true
            text: "Panel width and text size are saved independently. Drag the panel's inner edge to resize. Height follows the screen."
            muted: true
            rel: 0.85
        }
        GText { text: `Text size · ${Math.round(Theme.zoom * 100)}%`; font.weight: Font.DemiBold }
        Slider {
            Layout.fillWidth: true
            from: 0.7; to: 2; stepSize: 0.1
            value: Theme.zoom
            onMoved: Theme.setZoom(value)
            Accessible.name: "Text size"
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            TextButton { label: "Smaller"; enabled: Theme.zoom > 0.7; onClicked: Theme.setZoom(Theme.zoom - 0.1) }
            TextButton { label: "Larger"; enabled: Theme.zoom < 2; onClicked: Theme.setZoom(Theme.zoom + 0.1) }
            TextButton { label: "Reset text"; onClicked: Theme.setZoom(1) }
        }
        GText { text: `Panel width · ${Theme.panelWidth} px`; font.weight: Font.DemiBold }
        Slider {
            Layout.fillWidth: true
            from: Theme.minWidth; to: Math.max(Theme.minWidth + 1, Theme.maxWidth); stepSize: 10
            value: Theme.panelWidth
            onMoved: Theme.setWidth(value)
            Accessible.name: "Panel width"
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            TextButton { label: "Narrower"; enabled: Theme.panelWidth > Theme.minWidth; onClicked: Theme.setWidth(Theme.panelWidth - 40) }
            TextButton { label: "Wider"; enabled: Theme.panelWidth < Theme.maxWidth; onClicked: Theme.setWidth(Theme.panelWidth + 40) }
            TextButton { label: "Reset width"; onClicked: Theme.resetWidth() }
        }
        GText { Layout.fillWidth: true; text: "Ctrl + / −: text size · Ctrl+0: reset text · Ctrl+O: toggle width"; muted: true; rel: 0.75 }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border; Layout.topMargin: 8; Layout.bottomMargin: 8 }

        StyledText {
            Layout.fillWidth: true
            text: "What Gecko can access"
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSize * 1.15
            color: Theme.text
            Layout.leftMargin: 4
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: "Checked on every tool call, so changes apply mid-chat."
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSize * 0.85
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
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSize
                        text: capRow.modelData.replace(/_/g, " ").replace(/^./, c => c.toUpperCase())
                        color: Theme.text
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Gecko.capabilityDescriptions[capRow.modelData]
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSize * 0.85
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

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 8
            TextButton {
                id: ctxButton
                label: "Refresh tools context"
                Layout.maximumWidth: column.width
                onClicked: {
                    label = "Refreshing…";
                    Gecko.regenerateContext(() => ctxButton.label = "Refreshed");
                }
            }
            StyledText {
                text: `Default model: ${Gecko.defaultModel}`
                font.pixelSize: Theme.fontSize * 0.85
                color: Theme.textMuted
            }
        }
    }
}
