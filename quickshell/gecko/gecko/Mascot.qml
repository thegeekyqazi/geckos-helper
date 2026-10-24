import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets

/**
 * A small gecko in a screen corner that shows what Gecko is doing:
 *   idle (still), working (bobbing), needs approval (badge + pulse), watcher running
 *   (eye), kill switch on (red hand). Click to open the panel, on the waiting chat if any.
 * Theme tokens: mascot ("always" | "busy" | "off"), mascot_corner, mascot_size.
 */
PanelWindow {
    id: root

    readonly property string mode: Theme.t.mascot ?? "always"
    readonly property string corner: Theme.t.mascot_corner ?? "bottom-right"
    readonly property real size: Theme.t.mascot_size ?? 52
    readonly property bool needsYou: Gecko.pendingCount > 0
    readonly property bool working: Gecko.anyBusy || Gecko.watcherRunning
    readonly property bool active: needsYou || working || Gecko.killed

    visible: Gecko.connected && mode !== "off" && (mode === "always" || active)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:gecko-mascot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitWidth: size + 24
    implicitHeight: size + 24

    anchors {
        bottom: corner.startsWith("bottom")
        top: corner.startsWith("top")
        right: corner.endsWith("right")
        left: corner.endsWith("left")
    }
    margins {
        bottom: 14
        top: 14
        right: 14
        left: 14
    }

    mask: Region { item: bubble }

    Rectangle {
        id: bubble
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: width / 2
        color: Theme.surfaceHigh
        border.width: root.needsYou ? 2 : 1
        border.color: root.needsYou ? Theme.accent : Theme.border
        opacity: root.active || hover.hovered ? 1 : 0.75

        // Pulse for a while when an approval arrives; the badge stays after that
        property bool pulsing: false
        Connections {
            target: Gecko
            function onPendingCountChanged() {
                bubble.pulsing = Gecko.pendingCount > 0;
                if (bubble.pulsing) stopPulse.restart();
            }
        }
        Timer {
            id: stopPulse
            interval: 20000
            onTriggered: bubble.pulsing = false
        }

        SequentialAnimation on scale {
            running: bubble.pulsing && root.visible
            loops: Animation.Infinite
            onRunningChanged: if (!running) bubble.scale = 1
            NumberAnimation { to: 1.12; duration: 450; easing.type: Easing.OutQuad }
            NumberAnimation { to: 1; duration: 450; easing.type: Easing.InQuad }
        }

        GText {
            id: face
            anchors.centerIn: parent
            text: Gecko.killed ? "✋" : Theme.avatar
            rel: root.size / 30

            SequentialAnimation on anchors.verticalCenterOffset { // Bob while working
                running: root.working && !root.needsYou && root.visible
                loops: Animation.Infinite
                onRunningChanged: if (!running) face.anchors.verticalCenterOffset = 0
                NumberAnimation { to: -4; duration: 300; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0; duration: 300; easing.type: Easing.InQuad }
            }
        }

        Rectangle { // Badge: approvals waiting, or the eye while a watcher runs
            visible: root.needsYou || (Gecko.watcherRunning && !Gecko.anyBusy)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: -3
            width: 20
            height: 20
            radius: 10
            color: root.needsYou ? Theme.accent : Theme.surface
            border.width: 1
            border.color: Theme.border
            GText {
                anchors.centerIn: parent
                visible: root.needsYou
                text: Gecko.pendingCount
                color: Theme.accentText
                rel: 0.72
                font.weight: Font.Bold
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.needsYou
                text: "visibility"
                iconSize: 13
                color: Theme.textMuted
            }
        }

        Rectangle { // Unread inbox report
            visible: Gecko.inboxUnread > 0 && !root.needsYou
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 10
            height: 10
            radius: 5
            color: Theme.accent
        }

        HoverHandler { id: hover }
        TapHandler {
            onTapped: {
                if (root.needsYou) Gecko.showAttention();
                else Gecko.open = !Gecko.open;
            }
        }
        StyledToolTip {
            text: Gecko.killed ? "Kill switch is on"
                : root.needsYou ? `${Gecko.pendingCount} approval(s) waiting`
                : Gecko.watcherRunning ? "A watcher is checking something"
                : Gecko.anyBusy ? "Working…" : `${Theme.assistantName} is idle`
            extraVisibleCondition: hover.hovered
        }
    }
}
