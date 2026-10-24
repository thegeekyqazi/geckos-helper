import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Reports from recipes (daily briefing, weekly review…). Tap to read; continue a
 * report in a chat to ask follow-ups.
 */
StyledFlickable {
    id: root
    clip: true
    contentHeight: column.implicitHeight + 16
    onVisibleChanged: if (visible) Gecko.refreshInbox()

    ColumnLayout {
        id: column
        x: 14
        width: root.width - 28
        spacing: 8

        GText {
            Layout.topMargin: 6
            visible: Gecko.inboxItems.length === 0
            text: "No reports yet. The daily briefing arrives at 8:00; recipes are on the Activity page."
            muted: true
            rel: 0.85
        }

        Repeater {
            model: Gecko.inboxItems
            delegate: Rectangle {
                id: card
                required property var modelData
                property bool expanded: false
                Layout.fillWidth: true
                implicitHeight: cardCol.implicitHeight + 20
                radius: Theme.cardRadius
                color: Theme.surface
                border.width: card.modelData.flagged ? 1 : 0
                border.color: Theme.errorText

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 10
                    anchors.leftMargin: 14
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle { // Unread dot
                            visible: !card.modelData.read
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: Theme.accent
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            GText {
                                Layout.fillWidth: true
                                text: card.modelData.title
                                font.weight: card.modelData.read ? Font.Normal : Font.DemiBold
                                rel: 0.95
                            }
                            GText {
                                text: new Date(card.modelData.ts * 1000).toLocaleString(Qt.locale(), "ddd MMM d, h:mm ap")
                                      + " · " + card.modelData.source.replace("recipe:", "").replace(/-/g, " ")
                                muted: true
                                rel: 0.72
                            }
                        }
                        MaterialSymbol {
                            text: card.expanded ? "expand_less" : "expand_more"
                            color: Theme.textMuted
                            iconSize: 18
                        }
                    }
                    GText {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: card.expanded
                        text: card.modelData.body
                        textFormat: Text.MarkdownText
                        rel: 0.88
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                    ColumnLayout { // Suggested to-dos: tick and add with one click
                        id: suggestions
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: card.expanded && card.modelData.todos.length > 0
                        spacing: 2
                        property var picked: card.modelData.todos.slice()
                        GText { text: "Suggested to-dos"; muted: true; rel: 0.75; font.weight: Font.DemiBold }
                        Repeater {
                            model: card.modelData.todos
                            delegate: RowLayout {
                                id: sugRow
                                required property string modelData
                                Layout.fillWidth: true
                                spacing: 6
                                readonly property bool checked: suggestions.picked.includes(modelData)
                                MaterialSymbol {
                                    text: sugRow.checked ? "check_box" : "check_box_outline_blank"
                                    fill: sugRow.checked ? 1 : 0
                                    iconSize: 18
                                    color: sugRow.checked ? Theme.accent : Theme.textMuted
                                }
                                GText { Layout.fillWidth: true; text: sugRow.modelData; rel: 0.85 }
                                TapHandler {
                                    onTapped: suggestions.picked = sugRow.checked
                                        ? suggestions.picked.filter(t => t !== sugRow.modelData)
                                        : [...suggestions.picked, sugRow.modelData]
                                }
                            }
                        }
                        DialogButton {
                            buttonText: `Add ${suggestions.picked.length} to to-dos`
                            enabled: suggestions.picked.length > 0
                            onClicked: Gecko.addSuggestedTodos(card.modelData.id, suggestions.picked)
                        }
                    }
                    RowLayout {
                        visible: card.expanded
                        spacing: 4
                        DialogButton {
                            buttonText: "Continue in chat"
                            enabled: !card.modelData.flagged
                            onClicked: Gecko.prefill(`About my "${card.modelData.title}" report:\n\n${card.modelData.body}\n\n`)
                        }
                        Item { Layout.fillWidth: true }
                        IconButton {
                            size: 28
                            iconName: "delete"
                            tip: "Delete"
                            onClicked: Gecko.deleteInboxItem(card.modelData.id)
                        }
                    }
                }
                TapHandler {
                    onTapped: {
                        card.expanded = !card.expanded;
                        if (!card.modelData.read) Gecko.markRead(card.modelData.id);
                    }
                }
            }
        }
    }
}
