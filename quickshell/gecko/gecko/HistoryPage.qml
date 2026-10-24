import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    spacing: 6

    StyledText {
        text: "Chats"
        font.pixelSize: Appearance.font.pixelSize.large
        color: Appearance.colors.colOnLayer0
        Layout.leftMargin: 4
    }

    StyledListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 4
        model: Gecko.chats
        delegate: RippleButton {
            id: row
            required property var modelData
            width: list.width
            implicitHeight: 54
            buttonRadius: Appearance.rounding.small
            toggled: modelData.id === Gecko.chatId
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
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
                        Layout.fillWidth: true
                        text: row.modelData.title
                        elide: Text.ElideRight
                        color: row.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: `${new Date(row.modelData.updated * 1000).toLocaleString(Qt.locale(), "MMM d, h:mm ap")}`
                            + ` · ${row.modelData.model ?? ""}` + (row.modelData.busy ? " · working" : "")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
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
                        color: Appearance.colors.colSubtext
                    }
                    StyledToolTip { text: "Delete chat" }
                }
            }
        }
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        visible: Gecko.chats.length === 0
        text: "No chats yet"
        color: Appearance.colors.colSubtext
    }
}
