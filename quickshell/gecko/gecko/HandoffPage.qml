import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 10

    GText {
        Layout.fillWidth: true
        Layout.margins: 14
        Layout.bottomMargin: 0
        text: "Review and edit before sharing. Only the text below will be copied; upload any needed files or images separately in the receiving chat."
        muted: true
        rel: 0.85
    }
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        clip: true
        TextArea {
            id: editor
            text: Gecko.handoffText
            onTextChanged: if (activeFocus) Gecko.handoffText = text
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            font.family: Theme.font
            font.pixelSize: Theme.fontSize * 0.9
            color: Theme.text
            padding: 12
            background: Rectangle { color: Theme.surface; radius: Theme.cardRadius }
        }
    }
    Flow {
        Layout.fillWidth: true
        Layout.margins: 14
        Layout.topMargin: 0
        spacing: 8
        TextButton {
            label: Gecko.copyingHandoff ? "Copying…" : "Copy reviewed handoff"
            enabled: !Gecko.copyingHandoff && editor.text.trim().length > 0
            onClicked: Gecko.copyHandoff(editor.text)
        }
        TextButton {
            label: "Back to chat"
            onClicked: Gecko.page = "chat"
        }
        GText { text: `${editor.text.length.toLocaleString()} characters`; muted: true; rel: 0.75 }
    }
}
