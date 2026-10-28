import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets

/**
 * Quick ask (Super+Space): a small box in the middle of the screen. Enter sends the
 * text to a new chat and opens the panel; "/" commands work here too (e.g. /todo milk).
 */
PanelWindow {
    id: root
    property bool shown: false
    visible: shown
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:gecko-quickask"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    implicitWidth: 640
    implicitHeight: box.implicitHeight + palette.implicitHeight + 40

    readonly property var matches: Gecko.matchCommands(field.text)
    property int index: 0
    onMatchesChanged: index = 0

    onShownChanged: {
        if (shown) {
            field.text = "";
            field.forceActiveFocus();
        }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.shown
        onCleared: root.shown = false
    }

    function submit() {
        const text = field.text.trim();
        if (!text) return;
        root.shown = false;
        if (text.startsWith("/") && Gecko.runCommand(text)) return;
        Gecko.newChat();
        Gecko.send(text);
        Gecko.open = true;
    }

    function complete(cmd) {
        if (cmd.arg && !cmd.arg.startsWith("[")) {
            field.text = `/${cmd.name} `;
            field.cursorPosition = field.text.length;
        } else {
            root.shown = false;
            cmd.run("");
            if (Gecko.page !== "chat" || cmd.name === "new") Gecko.open = true;
        }
    }

    StyledRectangularShadow { target: box; radius: box.radius }

    Rectangle {
        id: box
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 10
        width: parent.width - 20
        implicitHeight: 58
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.border

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 10
            GText { text: Theme.avatar; rel: 1.3 }
            TextField {
                id: field
                Layout.fillWidth: true
                background: null
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fontSize * 1.15
                placeholderText: `Ask ${Theme.assistantName}…  (/ for commands, Esc to close)`
                placeholderTextColor: Theme.textMuted
                Keys.onPressed: event => {
                    const n = root.matches.length;
                    if (event.key === Qt.Key_Escape) { root.shown = false; event.accepted = true; }
                    else if (Theme.zoomKey(event)) event.accepted = true;
                    else if (n && event.key === Qt.Key_Down) { root.index = (root.index + 1) % n; event.accepted = true; }
                    else if (n && event.key === Qt.Key_Up) { root.index = (root.index + n - 1) % n; event.accepted = true; }
                    else if (n && event.key === Qt.Key_Tab) { root.complete(root.matches[root.index]); event.accepted = true; }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (n && !field.text.includes(" ")) root.complete(root.matches[root.index]);
                        else root.submit();
                        event.accepted = true;
                    }
                }
            }
        }
    }

    Rectangle {
        id: palette
        visible: root.matches.length > 0
        anchors.top: box.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: box.width
        implicitHeight: visible ? Math.min(list.contentHeight + 12, 300) : 0
        radius: Theme.cardRadius
        color: Theme.popup
        border.width: 1
        border.color: Theme.border
        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            model: root.matches
            currentIndex: root.index
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: list.width
                implicitHeight: 34
                radius: Theme.cardRadius - 6
                color: index === root.index ? Theme.surface : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    GText { text: `/${row.modelData.name}`; font.family: Theme.monoFont; color: Theme.accent; rel: 0.9; wrapMode: Text.NoWrap }
                    GText { visible: row.modelData.arg.length > 0; text: row.modelData.arg; muted: true; rel: 0.8; wrapMode: Text.NoWrap }
                    GText { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: row.modelData.desc; muted: true; rel: 0.8; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                }
                MouseArea { anchors.fill: parent; onClicked: root.complete(row.modelData) }
            }
        }
    }
}
