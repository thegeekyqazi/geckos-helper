pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One transcript entry. `kind` decides the look: user / agent / thought / tool /
 * permission / error. Roles come from Gecko.messages.
 */
Item {
    id: root
    required property int index
    required property string kind
    required property string text
    required property bool streaming
    required property string title
    required property string status
    required property string output
    required property string permState
    required property string tool
    required property string inputJson

    implicitHeight: loader.implicitHeight

    Loader {
        id: loader
        width: root.width
        sourceComponent: ({
            user: userBubble,
            agent: agentText,
            thought: thoughtBlock,
            tool: toolCard,
            permission: permissionCard,
            error: errorBox,
        })[root.kind] ?? null
    }

    Component {
        id: userBubble
        Item {
            implicitHeight: bubble.implicitHeight
            Rectangle {
                id: bubble
                anchors.right: parent.right
                width: Math.min(parent.width * 0.85, userText.implicitWidth + 24)
                implicitHeight: userText.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colPrimaryContainer
                StyledText {
                    id: userText
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    text: root.text
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnPrimaryContainer
                    textFormat: Text.PlainText
                }
            }
        }
    }

    Component {
        id: agentText
        StyledText {
            text: root.text + (root.streaming ? " ▍" : "")
            wrapMode: Text.Wrap
            textFormat: Text.MarkdownText
            color: Appearance.colors.colOnLayer0
            leftPadding: 4
            rightPadding: 4
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }

    Component {
        id: thoughtBlock
        ColumnLayout {
            id: tb
            property bool expanded: false
            spacing: 2
            RippleButton {
                implicitHeight: 26
                implicitWidth: thoughtLabel.implicitWidth + 20
                buttonRadius: Appearance.rounding.full
                onClicked: tb.expanded = !tb.expanded
                contentItem: RowLayout {
                    id: thoughtLabel
                    anchors.centerIn: parent
                    MaterialSymbol { text: "psychology"; color: Appearance.colors.colSubtext }
                    StyledText {
                        text: root.streaming ? "Thinking…" : "Thought"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: tb.expanded
                text: root.text
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                leftPadding: 10
            }
        }
    }

    Component {
        id: toolCard
        Rectangle {
            id: tc
            property bool expanded: false
            implicitHeight: tcCol.implicitHeight + 12
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            ColumnLayout {
                id: tcCol
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol {
                        text: root.status === "running" ? "progress_activity"
                            : root.status === "failed" ? "error" : "check_circle"
                        color: root.status === "failed" ? Appearance.colors.colError : Appearance.colors.colSubtext
                        RotationAnimation on rotation {
                            running: root.status === "running"
                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.title
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                    MaterialSymbol {
                        visible: root.output.length > 0
                        text: tc.expanded ? "expand_less" : "expand_more"
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: tc.expanded
                    text: root.output
                    wrapMode: Text.Wrap
                    maximumLineCount: 30
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: root.output.length > 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: tc.expanded = !tc.expanded
            }
        }
    }

    Component {
        id: permissionCard
        Rectangle {
            implicitHeight: pcCol.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: root.permState === "pending" ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer1
            ColumnLayout {
                id: pcCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: root.permState === "allowed" ? "check" : root.permState === "denied" ? "block" : "shield_question"
                        color: Appearance.colors.colOnTertiaryContainer
                        iconSize: Appearance.font.pixelSize.larger
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.permState === "pending" ? `Allow: ${root.title}?`
                            : root.permState === "allowed" ? `Allowed: ${root.title}`
                            : root.permState === "denied" ? `Denied: ${root.title}` : root.title
                        wrapMode: Text.Wrap
                        color: root.permState === "pending" ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSubtext
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.permState === "pending" && root.inputJson !== "{}"
                    text: root.inputJson
                    wrapMode: Text.Wrap
                    maximumLineCount: 12
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnTertiaryContainer
                }
                RowLayout {
                    visible: root.permState === "pending"
                    spacing: 6
                    DialogButton {
                        buttonText: "Allow"
                        onClicked: Gecko.answerPermission(root.index, true, "once")
                    }
                    DialogButton {
                        buttonText: "Allow for this chat"
                        onClicked: Gecko.answerPermission(root.index, true, "chat")
                    }
                    Item { Layout.fillWidth: true }
                    DialogButton {
                        buttonText: "Deny"
                        onClicked: Gecko.answerPermission(root.index, false)
                    }
                }
            }
        }
    }

    Component {
        id: errorBox
        Rectangle {
            implicitHeight: errText.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Appearance.colors.colErrorContainer
            StyledText {
                id: errText
                anchors.fill: parent
                anchors.margins: 8
                text: root.text
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnErrorContainer
            }
        }
    }
}
