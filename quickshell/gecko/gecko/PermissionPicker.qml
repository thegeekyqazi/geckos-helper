import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property bool forDefault: false
    property bool compact: false
    readonly property string selected: forDefault ? Gecko.defaultPermissionMode : Gecko.permissionMode
    spacing: 6

    ComboBox {
        id: picker
        objectName: root.forDefault ? "defaultPermissionPicker" : "chatPermissionPicker"
        Layout.fillWidth: true
        enabled: Gecko.connected && !Gecko.changingPermissions && (root.forDefault || !Gecko.busy)
        model: Gecko.permissionModes
        textRole: "label"
        valueRole: "id"
        font.pixelSize: Theme.fontSize
        palette {
            window: Theme.popup
            base: Theme.popup
            button: Theme.surface
            text: Theme.text
            buttonText: Theme.text
            highlight: Theme.accent
            highlightedText: Theme.accentText
        }
        currentIndex: Gecko.permissionModes.findIndex(m => m.id === root.selected)
        Accessible.name: root.forDefault ? "Default permissions for new chats" : "Chat permissions"
        onActivated: Gecko.setPermissionMode(currentValue, root.forDefault)
        popup.height: Math.min(popup.implicitHeight, 260)
    }
    GText {
        Layout.fillWidth: true
        visible: !root.compact || root.selected === "bypassPermissions"
        text: Gecko.permissionModes.find(m => m.id === root.selected)?.description || "Loading permissions…"
        rel: 0.8
        muted: root.selected !== "bypassPermissions"
    }
}
