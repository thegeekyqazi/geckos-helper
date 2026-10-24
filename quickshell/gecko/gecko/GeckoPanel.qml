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
    property real panelWidth: extend ? Theme.width * 1.5 : Theme.width

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    implicitWidth: Theme.width * 1.5 + Appearance.sizes.elevationMargin * 2
    WlrLayershell.namespace: "quickshell:gecko"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: !Theme.rightSide
        right: Theme.rightSide
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
        anchors.left: Theme.rightSide ? undefined : parent.left
        anchors.right: Theme.rightSide ? parent.right : undefined
        anchors.margins: Appearance.sizes.hyprlandGapsOut
        width: panelWindow.panelWidth
        height: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        color: Theme.bg
        border.width: 1
        border.color: Theme.border
        radius: Theme.radius
        clip: true
        focus: true

        Behavior on width {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (menu.shown) menu.shown = false;
                else if (Gecko.page !== "chat") Gecko.page = "chat";
                else Gecko.open = false;
            } else if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_O) panelWindow.extend = !panelWindow.extend;
                else if (event.key === Qt.Key_N) Gecko.newChat();
                else if (event.key === Qt.Key_H) Gecko.page = Gecko.page === "history" ? "chat" : "history";
                else if (event.key === Qt.Key_T) Gecko.cycleTheme(1);
                else return;
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Header {
                onMenuRequested: menu.shown = !menu.shown
                Layout.fillWidth: true
                Layout.margins: 8
                Layout.bottomMargin: 0
            }

            Rectangle { // Theme errors stay visible until fixed
                Layout.fillWidth: true
                Layout.margins: 8
                visible: Theme.error.length > 0
                implicitHeight: themeError.implicitHeight + 12
                radius: Theme.cardRadius
                color: Theme.errorBg
                GText {
                    id: themeError
                    anchors.fill: parent
                    anchors.margins: 6
                    text: `Theme error, using the last good theme:\n${Theme.error}`
                    color: Theme.errorText
                    rel: 0.8
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: ["chat", "history", "settings", "activity"].indexOf(Gecko.page)

                ChatPage { id: chatPage }
                HistoryPage {}
                SettingsPage {}
                ActivityPage {}
            }
        }

        PanelMenu {
            id: menu
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 50
            anchors.rightMargin: 10
        }
    }

    component Header: RowLayout {
        id: header
        signal menuRequested()
        spacing: 2

        RippleButton { // Chat title; opens history
            Layout.fillWidth: true
            implicitHeight: 38
            buttonRadius: Theme.cardRadius
            colBackground: "transparent"
            colBackgroundHover: Theme.surfaceHigh
            colRipple: Theme.border
            onClicked: {
                Gecko.refreshChats();
                Gecko.page = Gecko.page === "history" ? "chat" : "history";
            }
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 6
                GText {
                    Layout.fillWidth: true
                    text: !Gecko.connected ? "Gecko is offline"
                        : Gecko.page === "history" ? "Chats"
                        : Gecko.page === "settings" ? "Settings"
                        : Gecko.page === "activity" ? "Activity"
                        : (Gecko.chatTitle || "New chat")
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
                MaterialSymbol {
                    text: Gecko.page === "history" ? "expand_less" : "expand_more"
                    color: Theme.textMuted
                    iconSize: 18
                }
            }
        }

        MaterialSymbol { // Kill switch indicator
            visible: Gecko.killed
            text: "front_hand"
            color: Theme.errorText
            iconSize: 20
        }
        IconButton {
            iconName: "palette"
            tip: `Theme: ${Theme.name} (click for next, right-click for previous)`
            onClicked: Gecko.cycleTheme(1)
            altAction: () => Gecko.cycleTheme(-1)
        }
        IconButton {
            iconName: "edit_square"
            tip: "New chat (Ctrl+N)"
            onClicked: Gecko.newChat()
        }
        IconButton {
            iconName: "more_horiz"
            tip: "More"
            onClicked: header.menuRequested()
        }
    }
}
