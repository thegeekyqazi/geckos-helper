import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// One attachment: image thumbnail or an icon, its name, and an optional remove button.
Rectangle {
    id: root
    property var attachment: ({})
    property bool removable: true
    signal removed()

    implicitHeight: 44
    implicitWidth: Math.min(220, row.implicitWidth + 12)
    radius: Theme.cardRadius - 4
    color: Theme.surfaceHigh
    border.width: 1
    border.color: Theme.border

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 4
        anchors.rightMargin: 6
        spacing: 6
        Rectangle {
            implicitWidth: 36
            implicitHeight: 36
            radius: 6
            color: Theme.surface
            clip: true
            Image {
                anchors.fill: parent
                visible: root.attachment.kind === "image"
                source: visible && root.attachment.path ? `file://${root.attachment.path}` : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 72
                asynchronous: true
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.attachment.kind !== "image"
                text: root.attachment.kind === "file" ? "description" : "content_paste"
                iconSize: 20
                color: Theme.textMuted
            }
        }
        GText {
            Layout.fillWidth: true
            Layout.maximumWidth: 150
            text: root.attachment.name ?? ""
            rel: 0.75
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
        IconButton {
            visible: root.removable
            size: 22
            iconName: "close"
            tip: "Remove"
            onClicked: root.removed()
        }
    }
}
