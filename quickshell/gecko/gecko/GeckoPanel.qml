import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets

PanelWindow {
    id: panelWindow
    visible: Gecko.open

    property bool extend: false
    property real panelWidth: extend ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin
    WlrLayershell.namespace: "quickshell:gecko"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"

    anchors {
        top: true
        left: true
        bottom: true
    }

    mask: Region {
        item: background
    }

    HyprlandFocusGrab { // Click outside to close
        windows: [panelWindow]
        active: Gecko.open
        onCleared: Gecko.open = false
    }

    onVisibleChanged: if (visible) chatPage.focusInput()

    StyledRectangularShadow {
        target: background
        radius: background.radius
    }

    Rectangle {
        id: background
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: Appearance.sizes.hyprlandGapsOut
        anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
        width: panelWindow.panelWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
        height: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        focus: true

        Behavior on width {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Gecko.open = false;
            } else if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_O) panelWindow.extend = !panelWindow.extend;
                else if (event.key === Qt.Key_N) Gecko.newChat();
                else if (event.key === Qt.Key_H) Gecko.page = Gecko.page === "history" ? "chat" : "history";
                else return;
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Header {
                Layout.fillWidth: true
            }

            UsageBar {
                Layout.fillWidth: true
                visible: Gecko.usage.five_hour !== undefined
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: ["chat", "history", "settings"].indexOf(Gecko.page)

                ChatPage { id: chatPage }
                HistoryPage {}
                SettingsPage {}
            }
        }

        ModelMenu {
            id: modelMenu
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 52
            anchors.rightMargin: 10
        }
    }

    component Header: RowLayout {
        spacing: 4

        MaterialSymbol {
            text: "pest_control_rodent"
            iconSize: Appearance.font.pixelSize.huge
            color: Gecko.killed ? Appearance.colors.colError : Appearance.colors.colPrimary
            Layout.leftMargin: 4
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: -2
            StyledText {
                text: "Gecko"
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: !Gecko.connected ? "Daemon offline (systemctl --user start geckos-helper)"
                    : Gecko.killed ? "Kill switch on"
                    : (Gecko.chatTitle || "New chat")
            }
        }
        HeaderChip {
            label: Gecko.chatModel || Gecko.defaultModel || "model"
            onClicked: modelMenu.shown = !modelMenu.shown
        }
        HeaderButton { iconName: "add"; tip: "New chat (Ctrl+N)"; onClicked: Gecko.newChat() }
        HeaderButton {
            iconName: "history"; tip: "History (Ctrl+H)"
            toggled: Gecko.page === "history"
            onClicked: { Gecko.refreshChats(); Gecko.page = Gecko.page === "history" ? "chat" : "history"; }
        }
        HeaderButton {
            iconName: "tune"; tip: "Capabilities"
            toggled: Gecko.page === "settings"
            onClicked: Gecko.page = Gecko.page === "settings" ? "chat" : "settings"
        }
        HeaderButton {
            iconName: "front_hand"; tip: Gecko.killed ? "Kill switch is ON (click to turn off)" : "Kill switch"
            toggled: Gecko.killed
            colBackgroundToggled: Appearance.colors.colError
            onClicked: Gecko.setKilled(!Gecko.killed)
        }
    }

    component HeaderButton: RippleButton {
        id: hb
        property string iconName
        property string tip
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: hb.iconName
            iconSize: Appearance.font.pixelSize.larger
            color: hb.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        }
        StyledToolTip { text: hb.tip }
    }

    component HeaderChip: RippleButton {
        id: chip
        property alias label: chipText.text
        implicitHeight: 30
        implicitWidth: chipRow.implicitWidth + 20
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        contentItem: Item {
            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 2
                StyledText {
                    id: chipText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                }
                MaterialSymbol {
                    text: "expand_more"
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    component UsageBar: RowLayout {
        spacing: 10
        Repeater {
            model: [["5h", "five_hour"], ["7d", "seven_day"]]
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                property real value: Gecko.usage[modelData[1]] ?? 0
                StyledText {
                    text: modelData[0]
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                StyledProgressBar {
                    Layout.fillWidth: true
                    valueBarWidth: width
                    value: parent.value
                }
                StyledText {
                    text: `${Math.round(parent.value * 100)}%`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
