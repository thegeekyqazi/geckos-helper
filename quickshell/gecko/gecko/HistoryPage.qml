import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: page
    spacing: 6
    property var results: []

    Timer { // Search as you type, without a request per keystroke
        id: searchDelay
        interval: 250
        onTriggered: {
            if (search.text.trim().length) Gecko.call("search", { query: search.text }, r => page.results = r.results);
            else page.results = [];
        }
    }

    Rectangle { // Search box
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.topMargin: 4
        implicitHeight: 38
        radius: Theme.cardRadius
        color: Theme.surface
        border.width: search.activeFocus ? 1 : 0
        border.color: Theme.border
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            spacing: 6
            MaterialSymbol { text: "search"; color: Theme.textMuted; iconSize: 18 }
            TextField {
                id: search
                Layout.fillWidth: true
                background: null
                color: Theme.text
                placeholderText: "Search all chats"
                placeholderTextColor: Theme.textMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize * 0.9
                onTextChanged: searchDelay.restart()
            }
        }
    }

    StyledListView { // Search results
        id: resultList
        visible: search.text.trim().length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        leftMargin: 8
        rightMargin: 8
        clip: true
        spacing: 4
        model: page.results
        delegate: RippleButton {
            id: hit
            required property var modelData
            width: resultList.width - 16
            implicitHeight: hitCol.implicitHeight + 16
            buttonRadius: Theme.cardRadius
            colBackground: "transparent"
            colBackgroundHover: Theme.surface
            onClicked: Gecko.openChat(modelData.chat)
            contentItem: ColumnLayout {
                id: hitCol
                anchors.fill: parent
                anchors.margins: 8
                anchors.leftMargin: 12
                spacing: 2
                GText { Layout.fillWidth: true; text: hit.modelData.title; rel: 0.85; muted: true; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                GText {
                    Layout.fillWidth: true
                    // [term] marks matches; escape everything else
                    text: hit.modelData.snippet.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                        .replace(/\[([^\]]*)\]/g, "<b>$1</b>").replace(/\n/g, " ")
                    textFormat: Text.StyledText
                    rel: 0.88
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }
    }

    StyledListView {
        id: list
        visible: !resultList.visible
        Layout.fillWidth: true
        Layout.fillHeight: true
        leftMargin: 8
        rightMargin: 8
        clip: true
        spacing: 4
        model: Gecko.chats
        delegate: RippleButton {
            id: row
            required property var modelData
            width: list.width - 16
            implicitHeight: 54
            buttonRadius: Theme.cardRadius
            toggled: modelData.id === Gecko.chatId
            colBackgroundToggled: Theme.surfaceHigh
            colBackgroundToggledHover: Theme.surface
            onClicked: Gecko.openChat(modelData.id)
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 4
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        font.pixelSize: Theme.fontSize
                        Layout.fillWidth: true
                        text: row.modelData.title
                        elide: Text.ElideRight
                        color: row.toggled ? Theme.text : Theme.text
                    }
                    StyledText {
                        text: `${new Date(row.modelData.updated * 1000).toLocaleString(Qt.locale(), "MMM d, h:mm ap")}`
                            + ` · ${row.modelData.model ?? ""}` + (row.modelData.busy ? " · working" : "")
                        font.pixelSize: Theme.fontSize * 0.75
                        color: Theme.textMuted
                    }
                }
                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    onClicked: Gecko.deleteChat(row.modelData.id)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "delete"
                        color: Theme.textMuted
                    }
                    StyledToolTip { text: "Delete chat" }
                }
            }
        }
    }

    StyledText {
        font.pixelSize: Theme.fontSize
        Layout.alignment: Qt.AlignHCenter
        visible: Gecko.chats.length === 0
        text: "No chats yet"
        color: Theme.textMuted
    }
}
