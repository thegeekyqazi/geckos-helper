import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/**
 * What Gecko remembers about you: Claude Code's own memory files for the Gecko
 * workspace. Expand to read, delete what's wrong.
 */
StyledFlickable {
    id: root
    clip: true
    contentHeight: column.implicitHeight + 16
    onVisibleChanged: if (visible) Gecko.refreshMemories()

    ColumnLayout {
        id: column
        x: 14
        width: root.width - 28
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            GText {
                Layout.fillWidth: true
                text: "Gecko saves facts it learns about you here and reads them in every chat."
                muted: true
                rel: 0.8
            }
            IconButton {
                iconName: "folder_open"
                tip: "Open the memory folder"
                onClicked: Quickshell.execDetached(["xdg-open", Gecko.memoryDir])
            }
        }

        GText {
            visible: Gecko.memories.length === 0
            text: "Nothing remembered yet. Tell Gecko things like 'remember that I prefer pavucontrol'."
            muted: true
            rel: 0.85
        }

        Repeater {
            model: Gecko.memories
            delegate: Rectangle {
                id: card
                required property var modelData
                property bool expanded: false
                Layout.fillWidth: true
                implicitHeight: cardCol.implicitHeight + 16
                radius: Theme.cardRadius
                color: Theme.surface
                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.leftMargin: 12
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            GText { Layout.fillWidth: true; text: card.modelData.name; rel: 0.9; font.weight: Font.DemiBold }
                            GText { Layout.fillWidth: true; text: card.modelData.description; muted: true; rel: 0.78 }
                        }
                        IconButton {
                            size: 28
                            iconName: "delete"
                            tip: "Forget this"
                            onClicked: Gecko.deleteMemory(card.modelData.file)
                        }
                    }
                    GText {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: card.expanded
                        text: card.modelData.body
                        textFormat: Text.MarkdownText
                        rel: 0.82
                    }
                }
                TapHandler { onTapped: card.expanded = !card.expanded }
            }
        }
    }
}
