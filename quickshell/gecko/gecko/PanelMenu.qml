import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Overflow menu: hand-off, settings, kill switch and subscription usage.
 */
Rectangle {
    id: root
    property bool shown: false
    visible: shown
    z: 20
    implicitWidth: 250
    implicitHeight: column.implicitHeight + 12
    radius: Theme.cardRadius
    color: Theme.surfaceHigh
    border.width: 1
    border.color: Theme.border

    component MenuItem: RippleButton {
        id: item
        property string iconName
        property string label
        property string hint
        property color tint: Theme.text
        Layout.fillWidth: true
        implicitHeight: hint ? 48 : 38
        buttonRadius: Theme.cardRadius - 4
        colBackground: "transparent"
        colBackgroundHover: Theme.surface
        colRipple: Theme.border
        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            MaterialSymbol {
                text: item.iconName
                iconSize: 20
                color: item.tint
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                GText { text: item.label; color: item.tint; rel: 0.93 }
                GText { visible: item.hint.length > 0; text: item.hint; muted: true; rel: 0.75 }
            }
        }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        MenuItem {
            iconName: "content_copy"
            label: "Copy chat"
            hint: "Full transcript as markdown"
            enabled: Gecko.chatId.length > 0
            onClicked: { Gecko.exportChat("transcript"); root.shown = false; }
        }
        MenuItem {
            iconName: "ios_share"
            label: Gecko.exporting ? "Writing brief…" : "Hand off to Claude.ai"
            hint: "Short brief to paste into another chat"
            enabled: Gecko.chatId.length > 0 && !Gecko.exporting
            onClicked: Gecko.exportChat("brief", () => root.shown = false)
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border; Layout.margins: 4 }
        MenuItem {
            iconName: "timeline"
            label: "Activity"
            hint: "What Gecko did, watchers, goals"
            onClicked: { Gecko.page = "activity"; root.shown = false; }
        }
        MenuItem {
            iconName: "tune"
            label: "Settings"
            hint: "What Gecko can access"
            onClicked: { Gecko.page = "settings"; root.shown = false; }
        }
        MenuItem {
            iconName: "front_hand"
            label: Gecko.killed ? "Turn kill switch off" : "Kill switch"
            hint: "Stop agents, block desktop access"
            tint: Gecko.killed ? Theme.text : Theme.errorText
            onClicked: { Gecko.setKilled(!Gecko.killed); root.shown = false; }
        }

        ColumnLayout { // Usage
            Layout.fillWidth: true
            Layout.margins: 10
            visible: Gecko.usage.five_hour !== undefined
            spacing: 4
            GText { text: "Usage"; muted: true; rel: 0.75 }
            Repeater {
                model: [["5 hours", "five_hour"], ["7 days", "seven_day"]]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    property real value: Gecko.usage[modelData[1]] ?? 0
                    GText { text: modelData[0]; muted: true; rel: 0.75; Layout.preferredWidth: 50 }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: Theme.surface
                        Rectangle {
                            width: parent.width * parent.parent.value
                            height: parent.height
                            radius: 3
                            color: parent.parent.value > 0.8 ? Theme.errorText : Theme.accent
                        }
                    }
                    GText { text: `${Math.round(parent.value * 100)}%`; muted: true; rel: 0.75 }
                }
            }
        }
    }
}
