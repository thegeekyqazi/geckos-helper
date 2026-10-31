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

    readonly property real panelWidth: resizeGrip.pressed ? resizeGrip.draggedWidth : Theme.panelWidth
    readonly property real outerMargin: Math.max(Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)
    Binding {
        target: Theme
        property: "availableWidth"
        value: Math.max(1, (panelWindow.screen?.width ?? 1920) - panelWindow.outerMargin * 2)
    }

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    implicitWidth: panelWidth + outerMargin * 2
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
        visible: Theme.shadow
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
        border.width: Theme.borderWidth
        border.color: Theme.border
        radius: Theme.radius
        clip: true
        focus: true

        Rectangle { // Sheen: a soft light falling across glass themes
            anchors.fill: parent
            radius: parent.radius
            visible: Theme.sheen.a > 0
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Theme.sheen }
                GradientStop { position: 0.45; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.sheen, Theme.sheen.a * 0.4) }
            }
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (menu.shown) menu.shown = false;
                else if (Gecko.page !== "chat") Gecko.page = "chat";
                else Gecko.open = false;
            } else if (Theme.zoomKey(event)) {
                event.accepted = true;
            } else if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_O) Theme.toggleWidth();
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
                id: panelHeader
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
                currentIndex: ["chat", "history", "settings", "activity", "memory", "calendar", "inbox", "projects", "handoff"].indexOf(Gecko.page)

                ChatPage { id: chatPage }
                HistoryPage {}
                SettingsPage {}
                ActivityPage {}
                MemoryPage {}
                CalendarPage {}
                InboxPage {}
                ProjectsPage {}
                HandoffPage {}
            }
        }

        Rectangle { // Toast: short confirmations from slash commands etc.
            z: 30
            visible: opacity > 0
            opacity: Gecko.toast ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 92
            implicitWidth: Math.min(parent.width - 40, toastText.implicitWidth + 28)
            implicitHeight: toastText.implicitHeight + 14
            radius: height / 2
            color: Theme.accent
            GText {
                id: toastText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.parent.width - 68)
                horizontalAlignment: Text.AlignHCenter
                text: Gecko.toast
                color: Theme.accentText
                rel: 0.85
            }
        }

        PanelMenu {
            id: menu
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: panelHeader.height + 12
            anchors.rightMargin: 10
        }

        MouseArea { // Drag the inner edge; save on release rather than on every pixel.
            id: resizeGrip
            objectName: "panelResizeGrip"
            z: 40
            width: 10
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: Theme.rightSide ? parent.left : undefined
            anchors.right: Theme.rightSide ? undefined : parent.right
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            property real startWidth: 0
            property real startX: 0
            property real draggedWidth: Theme.panelWidth
            onPressed: mouse => {
                startWidth = Theme.panelWidth;
                startX = mapToGlobal(mouse.x, mouse.y).x;
                draggedWidth = startWidth;
            }
            onPositionChanged: mouse => {
                if (!pressed) return;
                const delta = mapToGlobal(mouse.x, mouse.y).x - startX;
                draggedWidth = Math.min(Theme.maxWidth, Math.max(Theme.minWidth,
                    startWidth + delta * (Theme.rightSide ? -1 : 1)));
            }
            onReleased: Theme.setWidth(draggedWidth)
            Rectangle {
                anchors.centerIn: parent
                width: 3
                height: 44
                radius: 2
                color: parent.pressed || parent.containsMouse ? Theme.accent : Theme.border
            }
            StyledToolTip { text: "Drag to resize panel width" }
        }
    }

    component Header: RowLayout {
        id: header
        signal menuRequested()
        spacing: 2

        RippleButton { // Chat title; opens history
            Layout.fillWidth: true
            implicitHeight: Math.max(38, Theme.fontSize * 1.4 + 14)
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
                        : Gecko.page === "memory" ? "Memory"
                        : Gecko.page === "calendar" ? "Calendar"
                        : Gecko.page === "inbox" ? "Inbox"
                        : Gecko.page === "projects" ? "Projects"
                        : Gecko.page === "handoff" ? "Handoff preview"
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
        IconButton { // Inbox with unread badge
            iconName: "inbox"
            tip: Gecko.inboxUnread ? `Inbox (${Gecko.inboxUnread} unread)` : "Inbox"
            onClicked: Gecko.page = Gecko.page === "inbox" ? "chat" : "inbox"
            Rectangle {
                visible: Gecko.inboxUnread > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 4
                width: 8
                height: 8
                radius: 4
                color: Theme.accent
            }
        }
        IconButton {
            iconName: "calendar_month"
            tip: "Calendar"
            onClicked: Gecko.page = Gecko.page === "calendar" ? "chat" : "calendar"
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
