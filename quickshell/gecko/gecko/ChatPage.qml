import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 8

    function focusInput() {
        input.forceActiveFocus();
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        StyledListView {
            id: list
            anchors.fill: parent
            spacing: 8
            clip: true
            popin: false
            add: null
            model: Gecko.messages
            delegate: MessageItem {
                width: list.width
            }

            Connections {
                target: Gecko
                function onScrollToEnd() {
                    Qt.callLater(list.positionViewAtEnd);
                }
            }
        }

        ColumnLayout { // Empty state with a few starters
            anchors.centerIn: parent
            width: parent.width - 20
            visible: Gecko.messages.count === 0
            spacing: 10

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "pest_control_rodent"
                iconSize: 56
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: "What can I do for you?"
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer0
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: ["What's on my calendar today?", "What's due this week?",
                            "Summarize my notifications", "Capture an idea"]
                    delegate: RippleButton {
                        id: starter
                        required property string modelData
                        implicitHeight: 32
                        implicitWidth: starterText.implicitWidth + 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        onClicked: {
                            if (modelData === "Capture an idea") {
                                input.text = "Capture this idea in my vault: ";
                                input.cursorPosition = input.text.length;
                                input.forceActiveFocus();
                            } else {
                                Gecko.send(modelData);
                            }
                        }
                        contentItem: StyledText {
                            id: starterText
                            anchors.centerIn: parent
                            text: starter.modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }
    }

    Rectangle { // Input box
        Layout.fillWidth: true
        implicitHeight: Math.min(200, Math.max(48, input.implicitHeight + 8))
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: input.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary

        RowLayout {
            anchors.fill: parent
            anchors.rightMargin: 6
            spacing: 4

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                StyledTextArea {
                    id: input
                    wrapMode: TextArea.Wrap
                    padding: 12
                    background: null
                    enabled: Gecko.connected && !Gecko.killed
                    placeholderText: Gecko.killed ? "Kill switch is on" : "Ask Gecko…  (Shift+Enter for a new line)"
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && !(event.modifiers & Qt.ShiftModifier)) {
                            if (!Gecko.busy) {
                                Gecko.send(input.text);
                                input.text = "";
                            }
                            event.accepted = true;
                        }
                    }
                }
            }

            RippleButton {
                implicitWidth: 38
                implicitHeight: 38
                buttonRadius: Appearance.rounding.full
                toggled: true
                enabled: Gecko.busy || input.text.trim().length > 0
                onClicked: {
                    if (Gecko.busy) {
                        Gecko.stop();
                    } else {
                        Gecko.send(input.text);
                        input.text = "";
                    }
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Gecko.busy ? "stop" : "arrow_upward"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
