import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    function focusInput() {
        input.forceActiveFocus();
    }

    function submit() {
        if (Gecko.busy || (!input.text.trim().length && !Gecko.attachments.length)) return;
        Gecko.send(input.text);
        input.text = "";
    }

    // Slash-command palette state
    readonly property var matches: Gecko.matchCommands(input.text)
    readonly property bool paletteOpen: matches.length > 0 && input.activeFocus
    property int paletteIndex: 0
    onMatchesChanged: paletteIndex = 0

    function completeCommand(cmd) {
        if (cmd.arg && !cmd.arg.startsWith("[")) {
            input.text = `/${cmd.name} `;
            input.cursorPosition = input.text.length;
        } else {
            input.text = "";
            cmd.run("");
        }
    }

    // Typing dots while the agent works but hasn't started writing yet
    readonly property bool waiting: {
        if (!Gecko.busy || Gecko.messages.count === 0) return false;
        const last = Gecko.messages.get(Gecko.messages.count - 1);
        return !(last.kind === "agent" && last.streaming) && last.permState !== "pending";
    }

    Connections {
        target: Gecko
        function onPrefillRequested(text) {
            input.text = text;
            input.cursorPosition = text.length;
            input.forceActiveFocus();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            leftMargin: 14
            rightMargin: 14
            topMargin: 8
            bottomMargin: 8
            spacing: 14
            clip: true
            popin: false
            add: null
            model: Gecko.messages
            delegate: MessageItem {
                width: list.width - list.leftMargin - list.rightMargin
            }
            footer: Item {
                width: list.width - list.leftMargin - list.rightMargin
                implicitHeight: root.waiting ? 34 : 0
                TypingDots {
                    visible: root.waiting
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                }
            }

            Connections {
                target: Gecko
                function onScrollToEnd() {
                    Qt.callLater(list.positionViewAtEnd);
                }
            }
        }

        Rectangle { // Composer
            id: composer
            Layout.fillWidth: true
            Layout.margins: 10
            implicitHeight: composerColumn.implicitHeight + 16
            radius: Theme.radius
            color: Theme.composerBg
            border.width: 1
            border.color: input.activeFocus ? Qt.alpha(Theme.accent, 0.6) : Theme.border

            Behavior on border.color { ColorAnimation { duration: 150 } }

            ColumnLayout {
                id: composerColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Flow { // Pending attachments
                    Layout.fillWidth: true
                    visible: Gecko.attachments.length > 0 || Gecko.capturing
                    spacing: 6
                    Repeater {
                        model: Gecko.attachments
                        delegate: AttachmentChip {
                            required property var modelData
                            required property int index
                            attachment: modelData
                            onRemoved: Gecko.removeAttachment(index)
                        }
                    }
                    GText {
                        visible: Gecko.capturing
                        text: "Capturing…"
                        muted: true
                        rel: 0.8
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(180, Math.max(28, input.implicitHeight))
                    StyledTextArea {
                        id: input
                        wrapMode: TextArea.Wrap
                        leftPadding: 8
                        rightPadding: 8
                        topPadding: 6
                        bottomPadding: 6
                        background: null
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        color: Theme.text
                        placeholderTextColor: Theme.textMuted
                        enabled: Gecko.connected && !Gecko.killed
                        placeholderText: Gecko.killed ? "Kill switch is on" : `Message ${Theme.assistantName}…  (/ for commands)`
                        Keys.onPressed: event => {
                            if (root.paletteOpen) {
                                const n = root.matches.length;
                                if (event.key === Qt.Key_Down) { root.paletteIndex = (root.paletteIndex + 1) % n; event.accepted = true; return; }
                                if (event.key === Qt.Key_Up) { root.paletteIndex = (root.paletteIndex + n - 1) % n; event.accepted = true; return; }
                                if (event.key === Qt.Key_Tab) { root.completeCommand(root.matches[root.paletteIndex]); event.accepted = true; return; }
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !input.text.includes(" ")) {
                                    root.completeCommand(root.matches[root.paletteIndex]);
                                    event.accepted = true;
                                    return;
                                }
                            }
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && !(event.modifiers & Qt.ShiftModifier)) {
                                root.submit();
                                event.accepted = true;
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    IconButton { // Attach
                        size: 30
                        iconName: "add"
                        tip: "Attach (or type /)"
                        onClicked: attachMenu.shown = !attachMenu.shown
                    }

                    RippleButton { // Model picker
                        implicitHeight: 30
                        implicitWidth: modelRow.implicitWidth + 18
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Theme.surfaceHigh
                        colRipple: Theme.border
                        onClicked: modelMenu.shown = !modelMenu.shown
                        contentItem: Item {
                            RowLayout {
                                id: modelRow
                                anchors.centerIn: parent
                                spacing: 2
                                GText {
                                    text: (Gecko.chatModel || Gecko.defaultModel || "model")
                                        .replace(/^./, c => c.toUpperCase())
                                    muted: true
                                    rel: 0.85
                                    wrapMode: Text.NoWrap
                                }
                                MaterialSymbol { text: "expand_more"; color: Theme.textMuted; iconSize: 16 }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton { // Send / stop
                        implicitWidth: 34
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        readonly property bool active: Gecko.busy || input.text.trim().length > 0 || Gecko.attachments.length > 0
                        colBackground: active ? Theme.accent : Theme.surfaceHigh
                        colBackgroundHover: active ? Qt.lighter(Theme.accent, 1.1) : Theme.surfaceHigh
                        colRipple: Theme.border
                        onClicked: Gecko.busy ? Gecko.stop() : root.submit()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: Gecko.busy ? "stop" : "arrow_upward"
                            fill: 1
                            iconSize: 20
                            color: parent.active ? Theme.accentText : Theme.textMuted
                        }
                    }
                }
            }
        }
    }

    EmptyState {
        onPrefill: text => {
            input.text = text;
            input.cursorPosition = text.length;
            input.forceActiveFocus();
        }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -40
        anchors.margins: 20
        visible: Gecko.messages.count === 0
    }

    Rectangle { // Attach menu
        id: attachMenu
        property bool shown: false
        visible: shown
        z: 10
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14
        anchors.bottomMargin: composer.height + 16
        implicitWidth: 230
        implicitHeight: attachCol.implicitHeight + 12
        radius: Theme.cardRadius
        color: Theme.surfaceHigh
        border.width: 1
        border.color: Theme.border
        ColumnLayout {
            id: attachCol
            anchors.fill: parent
            anchors.margins: 6
            spacing: 0
            Repeater {
                model: [["screenshot", "screenshot_region", "Screenshot a region"],
                        ["window", "web_asset", "Focused window"],
                        ["clipboard", "content_paste", "Clipboard"],
                        ["selection", "text_select_start", "Selected text"],
                        ["file", "attach_file", "File…"]]
                delegate: RippleButton {
                    id: attachItem
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 36
                    buttonRadius: Theme.cardRadius - 4
                    colBackground: "transparent"
                    colBackgroundHover: Theme.surface
                    colRipple: Theme.border
                    onClicked: { attachMenu.shown = false; Gecko.capture(modelData[0]); }
                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        spacing: 10
                        MaterialSymbol { text: attachItem.modelData[1]; iconSize: 18; color: Theme.textMuted }
                        GText { Layout.fillWidth: true; text: attachItem.modelData[2]; rel: 0.9 }
                    }
                }
            }
        }
    }

    Rectangle { // Slash-command palette
        visible: root.paletteOpen
        z: 11
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: composer.height + 16
        implicitHeight: Math.min(paletteList.contentHeight + 12, 320)
        radius: Theme.cardRadius
        color: Theme.surfaceHigh
        border.width: 1
        border.color: Theme.border
        ListView {
            id: paletteList
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            model: root.matches
            currentIndex: root.paletteIndex
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: Rectangle {
                id: cmdRow
                required property var modelData
                required property int index
                width: paletteList.width
                implicitHeight: 34
                radius: Theme.cardRadius - 6
                color: index === root.paletteIndex ? Theme.surface : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    GText {
                        text: `/${cmdRow.modelData.name}`
                        font.family: Theme.monoFont
                        rel: 0.85
                        color: Theme.accent
                        wrapMode: Text.NoWrap
                    }
                    GText {
                        visible: cmdRow.modelData.arg.length > 0
                        text: cmdRow.modelData.arg
                        muted: true
                        rel: 0.75
                        wrapMode: Text.NoWrap
                    }
                    GText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: cmdRow.modelData.desc
                        muted: true
                        rel: 0.75
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.completeCommand(cmdRow.modelData)
                }
            }
        }
    }

    ModelMenu {
        id: modelMenu
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14
        anchors.bottomMargin: composer.height + 16
    }

    component TypingDots: Row {
        spacing: 5
        Repeater {
            model: 3
            delegate: Rectangle {
                required property int index
                width: 7
                height: 7
                radius: 4
                color: Theme.textMuted
                SequentialAnimation on opacity {
                    running: root.waiting
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 160 }
                    NumberAnimation { from: 0.25; to: 1; duration: 320 }
                    NumberAnimation { from: 1; to: 0.25; duration: 320 }
                    PauseAnimation { duration: (2 - index) * 160 }
                }
            }
        }
    }

    component EmptyState: ColumnLayout {
        id: empty
        signal prefill(string text)
        spacing: 18

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            GText {
                Layout.alignment: Qt.AlignHCenter
                text: Theme.avatar
                rel: 2.6
            }
            GText {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: {
                    const h = new Date().getHours();
                    return h < 5 ? "Up late?" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
                }
                rel: 1.7
                font.weight: Font.DemiBold
            }
            GText {
                Layout.alignment: Qt.AlignHCenter
                text: "How can I help?"
                muted: true
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8
            Repeater {
                model: [
                    ["calendar_month", "What's on today?", "What's on my calendar today?"],
                    ["assignment_late", "What's due soon?", "What's due this week, from my calendar and Obsidian tasks?"],
                    ["notifications", "Catch me up", "Summarize my recent notifications."],
                    ["lightbulb", "Capture an idea", ""],
                ]
                delegate: RippleButton {
                    id: card
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 64
                    buttonRadius: Theme.cardRadius
                    colBackground: Theme.surface
                    colBackgroundHover: Theme.surfaceHigh
                    colRipple: Theme.border
                    onClicked: {
                        if (modelData[2]) {
                            Gecko.send(modelData[2]);
                        } else {
                            empty.prefill("Capture this idea in my vault: ");
                        }
                    }
                    contentItem: ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 2
                        MaterialSymbol {
                            text: card.modelData[0]
                            iconSize: 20
                            color: Theme.accent
                        }
                        GText {
                            Layout.fillWidth: true
                            text: card.modelData[1]
                            rel: 0.87
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                    }
                }
            }
        }
    }
}
