pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
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

    // Assistant-side entries (text, tools, thoughts) sit indented under the avatar
    readonly property real indent: 34
    // The avatar only shows on the first assistant entry after a user message
    readonly property bool firstOfReply: {
        if (root.kind === "user" || root.index === 0) return false;
        return Gecko.messages.get(root.index - 1)?.kind === "user";
    }

    implicitHeight: loader.implicitHeight + (firstOfReply ? 26 : 0)

    Row { // Avatar + name
        visible: root.firstOfReply
        spacing: 8
        Rectangle {
            width: 26
            height: 26
            radius: 13
            color: Theme.surfaceHigh
            GText {
                anchors.centerIn: parent
                text: Theme.avatar
                rel: 0.85
            }
        }
        GText {
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.assistantName
            font.weight: Font.DemiBold
            rel: 0.87
        }
    }

    Loader {
        id: loader
        y: root.firstOfReply ? 26 : 0
        x: root.kind === "user" ? 0 : root.indent
        width: root.width - x
        sourceComponent: ({
            user: userBubble,
            agent: agentText,
            thought: thoughtBlock,
            tool: toolRow,
            permission: permissionCard,
            guard: guardCard,
            error: errorBox,
        })[root.kind] ?? null
    }

    Component {
        id: userBubble
        Item {
            implicitHeight: bubble.implicitHeight + 6
            Rectangle {
                id: bubble
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 6
                width: Math.min(parent.width * 0.85, userText.implicitWidth + 28)
                implicitHeight: userText.implicitHeight + 20
                radius: Theme.bubbleRadius
                color: Theme.userBubble
                GText {
                    id: userText
                    anchors.fill: parent
                    anchors.margins: 10
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    text: root.text
                    color: Theme.userBubbleText
                    textFormat: Text.PlainText
                }
            }
        }
    }

    Component {
        id: agentText
        ColumnLayout {
            spacing: 2
            GText {
                id: body
                Layout.fillWidth: true
                text: root.text + (root.streaming ? " ●" : "")
                textFormat: Text.MarkdownText
                lineHeight: 1.25
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
            Row { // Actions under a finished reply
                visible: !root.streaming
                spacing: 0
                opacity: hover.hovered ? 1 : 0.55
                IconButton {
                    id: copyButton
                    size: 28
                    iconName: "content_copy"
                    tip: "Copy"
                    onClicked: {
                        Quickshell.execDetached(["wl-copy", root.text]);
                        iconName = "check";
                        resetIcon.restart();
                    }
                    Timer {
                        id: resetIcon
                        interval: 1500
                        onTriggered: copyButton.iconName = "content_copy"
                    }
                }
            }
            HoverHandler { id: hover }
        }
    }

    Component {
        id: thoughtBlock
        ColumnLayout {
            id: tb
            property bool expanded: false
            spacing: 4
            RowLayout {
                spacing: 6
                MaterialSymbol {
                    text: "psychology"
                    color: Theme.textMuted
                    iconSize: 16
                }
                GText {
                    text: root.streaming ? "Thinking…" : "Thought for a moment"
                    muted: true
                    rel: 0.85
                    SequentialAnimation on opacity {
                        running: root.streaming
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.4; duration: 700 }
                        NumberAnimation { from: 0.4; to: 1; duration: 700 }
                    }
                }
                MaterialSymbol {
                    text: tb.expanded ? "expand_less" : "expand_more"
                    color: Theme.textMuted
                    iconSize: 16
                }
                TapHandler { onTapped: tb.expanded = !tb.expanded }
            }
            Rectangle {
                Layout.fillWidth: true
                visible: tb.expanded
                implicitHeight: thoughtText.implicitHeight + 8
                color: "transparent"
                Rectangle { width: 2; height: parent.height; color: Theme.border }
                GText {
                    id: thoughtText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    text: root.text
                    muted: true
                    rel: 0.85
                }
            }
        }
    }

    Component {
        id: toolRow
        Rectangle {
            id: tc
            property bool expanded: false
            implicitHeight: tcCol.implicitHeight + 10
            radius: Theme.cardRadius - 4
            color: tc.expanded ? Theme.toolBg : "transparent"
            border.width: 1
            border.color: Theme.border
            ColumnLayout {
                id: tcCol
                anchors.fill: parent
                anchors.margins: 5
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        text: root.status === "running" ? "progress_activity"
                            : root.status === "failed" ? "error" : "check"
                        color: root.status === "failed" ? Theme.errorText : Theme.textMuted
                        iconSize: 16
                        RotationAnimation on rotation {
                            running: root.status === "running"
                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                        }
                    }
                    GText {
                        Layout.fillWidth: true
                        text: root.title
                        muted: true
                        rel: 0.82
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                    MaterialSymbol {
                        visible: root.output.length > 0
                        text: tc.expanded ? "expand_less" : "expand_more"
                        color: Theme.textMuted
                        iconSize: 16
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    visible: tc.expanded
                    implicitHeight: outText.implicitHeight + 12
                    radius: 8
                    color: Theme.codeBg
                    GText {
                        id: outText
                        anchors.fill: parent
                        anchors.margins: 6
                        text: root.output
                        maximumLineCount: 30
                        elide: Text.ElideRight
                        font.family: Theme.monoFont
                        rel: 0.75
                        muted: true
                    }
                }
            }
            TapHandler {
                enabled: root.output.length > 0
                onTapped: tc.expanded = !tc.expanded
            }
        }
    }

    Component {
        id: permissionCard
        Rectangle {
            id: pcard
            readonly property bool pending: root.permState === "pending"
            implicitHeight: pcCol.implicitHeight + 24
            radius: Theme.cardRadius
            color: pending ? Theme.permissionBg : "transparent"
            border.width: pending ? 0 : 1
            border.color: Theme.border
            ColumnLayout {
                id: pcCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: root.permState === "allowed" ? "check_circle"
                            : root.permState === "denied" ? "block" : "shield_question"
                        color: pcard.pending ? Theme.permissionText : Theme.textMuted
                        iconSize: 20
                    }
                    GText {
                        Layout.fillWidth: true
                        text: root.permState === "pending" ? `Allow ${root.title}?`
                            : root.permState === "allowed" ? `Allowed: ${root.title}`
                            : root.permState === "denied" ? `Denied: ${root.title}` : root.title
                        color: pcard.pending ? Theme.permissionText : Theme.textMuted
                        font.weight: pcard.pending ? Font.DemiBold : Font.Normal
                        rel: 0.9
                    }
                }
                GText { // Guard warning: this chat read something that looked like an injection
                    Layout.fillWidth: true
                    visible: pcard.pending && root.output.length > 0
                    text: "⚠ " + root.output
                    color: Theme.permissionText
                    rel: 0.8
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    Layout.fillWidth: true
                    visible: pcard.pending && root.inputJson !== "{}"
                    implicitHeight: inputText.implicitHeight + 14
                    radius: 8
                    color: Qt.alpha(Theme.bg, 0.5)
                    GText {
                        id: inputText
                        anchors.fill: parent
                        anchors.margins: 7
                        text: root.inputJson
                        maximumLineCount: 12
                        elide: Text.ElideRight
                        font.family: Theme.monoFont
                        rel: 0.75
                        color: Theme.permissionText
                    }
                }
                RowLayout {
                    visible: pcard.pending
                    spacing: 6
                    PermissionButton {
                        label: "Allow"
                        primary: true
                        onClicked: Gecko.answerPermission(root.index, true, "once")
                    }
                    PermissionButton {
                        label: "This chat"
                        onClicked: Gecko.answerPermission(root.index, true, "chat")
                        StyledToolTip { text: "Allow this kind of call for the rest of this chat" }
                    }
                    PermissionButton {
                        label: "Always"
                        onClicked: Gecko.answerPermission(root.index, true, "always")
                        StyledToolTip { text: "Save a rule that always allows this exact call (edit in Settings)" }
                    }
                    Item { Layout.fillWidth: true }
                    PermissionButton {
                        label: "Deny"
                        onClicked: Gecko.answerPermission(root.index, false)
                    }
                }
            }
        }
    }

    component PermissionButton: RippleButton {
        id: pb
        property string label
        property bool primary: false
        implicitHeight: 32
        implicitWidth: pbText.implicitWidth + 26
        buttonRadius: Appearance.rounding.full
        colBackground: primary ? Theme.permissionText : Qt.alpha(Theme.permissionText, 0.12)
        colBackgroundHover: primary ? Qt.alpha(Theme.permissionText, 0.85) : Qt.alpha(Theme.permissionText, 0.2)
        colRipple: Qt.alpha(Theme.permissionText, 0.3)
        contentItem: GText {
            id: pbText
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: pb.label
            rel: 0.85
            font.weight: Font.DemiBold
            wrapMode: Text.NoWrap
            color: pb.primary ? Theme.permissionBg : Theme.permissionText
        }
    }

    Component {
        id: guardCard
        Rectangle {
            implicitHeight: guardCol.implicitHeight + 20
            radius: Theme.cardRadius
            color: Theme.errorBg
            ColumnLayout {
                id: guardCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                RowLayout {
                    spacing: 8
                    MaterialSymbol { text: "gpp_maybe"; iconSize: 20; color: Theme.errorText }
                    GText {
                        Layout.fillWidth: true
                        text: `Possible prompt injection in ${root.title}`
                        color: Theme.errorText
                        font.weight: Font.DemiBold
                        rel: 0.9
                    }
                }
                GText {
                    Layout.fillWidth: true
                    text: `Found: ${root.text}. Gecko will treat it as data, and every action in this chat now needs your approval (saved rules are paused). Check what it read before allowing anything.`
                    color: Theme.errorText
                    rel: 0.8
                }
                RippleButton {
                    visible: Gecko.tainted
                    implicitHeight: 30
                    implicitWidth: clearText.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: Qt.alpha(Theme.errorText, 0.15)
                    colBackgroundHover: Qt.alpha(Theme.errorText, 0.25)
                    onClicked: Gecko.clearTaint()
                    contentItem: GText {
                        id: clearText
                        anchors.centerIn: parent
                        text: "I checked it, clear the warning"
                        color: Theme.errorText
                        rel: 0.8
                        wrapMode: Text.NoWrap
                    }
                }
            }
        }
    }

    Component {
        id: errorBox
        Rectangle {
            implicitHeight: errText.implicitHeight + 18
            radius: Theme.cardRadius
            color: Theme.errorBg
            GText {
                id: errText
                anchors.fill: parent
                anchors.margins: 9
                text: root.text
                color: Theme.errorText
                rel: 0.85
            }
        }
    }
}
