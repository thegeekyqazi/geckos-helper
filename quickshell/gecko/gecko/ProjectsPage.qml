import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/**
 * Projects and goals from the Obsidian vault, grouped by status, plus the ideas list.
 * Tap a project to open its note in Obsidian; "Plan" and "Start" hand off to a chat.
 */
StyledFlickable {
    id: root
    clip: true
    contentHeight: column.implicitHeight + 16
    onVisibleChanged: if (visible) Gecko.refreshProjects()

    readonly property var groups: [
        ["active", "Active"], ["idea", "Ideas (planned)"], ["on-hold", "On hold"], ["done", "Done"]]

    function openNote(file) {
        Qt.openUrlExternally(`obsidian://open?path=${encodeURIComponent(Gecko.vaultPath + "/" + file)}`);
    }

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
                text: "From your vault's Projects folder and tracked notes."
                muted: true
                rel: 0.8
            }
            DialogButton {
                buttonText: "New…"
                onClicked: Gecko.prefill("Help me start a new project: ")
            }
        }

        GText {
            visible: Gecko.projects.length === 0 && Gecko.ideas.length === 0
            Layout.fillWidth: true
            text: "Nothing tracked yet. Try \"turn my Inventory Prediction note into a tracked project\" or /idea something."
            muted: true
            rel: 0.85
        }

        Repeater {
            model: root.groups
            delegate: ColumnLayout {
                id: group
                required property var modelData
                readonly property var items: Gecko.projects.filter(p => p.status === modelData[0])
                property bool collapsed: modelData[0] === "done"
                Layout.fillWidth: true
                visible: items.length > 0
                spacing: 6

                RowLayout {
                    Layout.topMargin: 8
                    GText { text: `${group.modelData[1]} · ${group.items.length}`; muted: true; rel: 0.82; font.weight: Font.DemiBold }
                    MaterialSymbol { text: group.collapsed ? "expand_more" : "expand_less"; iconSize: 16; color: Theme.textMuted }
                    TapHandler { onTapped: group.collapsed = !group.collapsed }
                }

                Repeater {
                    model: group.collapsed ? [] : group.items
                    delegate: RippleButton {
                        id: card
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: cardCol.implicitHeight + 18
                        buttonRadius: Theme.cardRadius
                        colBackground: Theme.surface
                        colBackgroundHover: Theme.surfaceHigh
                        colRipple: Theme.border
                        onClicked: root.openNote(card.modelData.file)
                        contentItem: ColumnLayout {
                            id: cardCol
                            anchors.fill: parent
                            anchors.margins: 9
                            anchors.leftMargin: 12
                            spacing: 3
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                GText { text: card.modelData.kind === "goal" ? "🎯" : "📦"; rel: 0.9 }
                                GText {
                                    Layout.fillWidth: true
                                    text: card.modelData.title
                                    rel: 0.95
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                }
                                GText {
                                    visible: !!card.modelData.due
                                    text: `due ${card.modelData.due}`
                                    muted: true
                                    rel: 0.72
                                }
                            }
                            RowLayout { // Progress
                                Layout.fillWidth: true
                                visible: card.modelData.total > 0
                                spacing: 8
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 5
                                    radius: 3
                                    color: Theme.surfaceHigh
                                    Rectangle {
                                        width: parent.width * card.modelData.done / Math.max(1, card.modelData.total)
                                        height: parent.height
                                        radius: 3
                                        color: Theme.accent
                                    }
                                }
                                GText { text: `${card.modelData.done}/${card.modelData.total}`; muted: true; rel: 0.72 }
                            }
                            GText {
                                Layout.fillWidth: true
                                visible: card.modelData.next.length > 0
                                text: `Next: ${card.modelData.next}`
                                muted: true
                                rel: 0.78
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }
                            RowLayout {
                                spacing: 4
                                GText {
                                    Layout.fillWidth: true
                                    text: card.modelData.category + (card.modelData.last_update ? ` · updated ${card.modelData.last_update}` : "")
                                    muted: true
                                    rel: 0.7
                                }
                                DialogButton {
                                    buttonText: "Plan"
                                    onClicked: Gecko.prefill(`Let's work on my ${card.modelData.kind} "${card.modelData.title}". Where does it stand and what should I do next?`)
                                }
                            }
                        }
                    }
                }
            }
        }

        GText {
            Layout.topMargin: 10
            visible: Gecko.ideas.length > 0
            text: `Ideas list · ${Gecko.ideas.length}`
            muted: true
            rel: 0.82
            font.weight: Font.DemiBold
        }
        Repeater {
            model: Gecko.ideas
            delegate: RowLayout {
                id: ideaRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol { text: "lightbulb"; iconSize: 16; color: Theme.textMuted }
                GText { Layout.fillWidth: true; text: ideaRow.modelData.idea; rel: 0.85 }
                DialogButton {
                    buttonText: "Start"
                    onClicked: Gecko.prefill(`Turn this idea (line ${ideaRow.modelData.line} of my ideas list) into a project: "${ideaRow.modelData.idea}". Ask me anything you need first.`)
                }
            }
        }
        GText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: "Add ideas with /idea. The full table is in Projects/Projects Hub.md."
            muted: true
            rel: 0.7
        }
    }
}
