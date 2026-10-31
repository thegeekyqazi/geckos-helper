pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Design tokens for the panel. Values come from the Lua theme the daemon renders
 * to ~/.local/state/geckos-helper/theme.json; anything missing falls back to end-4.
 */
Singleton {
    id: root

    property var t: ({})
    property string name: "default"
    property var themes: []
    property string error: ""

    readonly property color bg: t.bg ?? Appearance.colors.colLayer0
    readonly property color surface: t.surface ?? Appearance.colors.colLayer1
    readonly property color surfaceHigh: t.surface_high ?? Appearance.colors.colLayer2
    // Menus and palettes float over other content, so they stay readable even in glass themes
    readonly property color popup: t.popup ?? surfaceHigh
    readonly property color border: t.border ?? Appearance.colors.colLayer0Border
    readonly property color text: t.text ?? Appearance.colors.colOnLayer0
    readonly property color textMuted: t.text_muted ?? Appearance.colors.colSubtext
    readonly property color accent: t.accent ?? Appearance.colors.colPrimary
    readonly property color accentText: t.on_accent ?? Appearance.colors.colOnPrimary
    readonly property color userBubble: t.user_bubble ?? Appearance.colors.colLayer2
    readonly property color userBubbleText: t.on_user_bubble ?? Appearance.colors.colOnLayer2
    readonly property color toolBg: t.tool_bg ?? Appearance.colors.colLayer1
    readonly property color permissionBg: t.permission_bg ?? Appearance.colors.colTertiaryContainer
    readonly property color permissionText: t.on_permission ?? Appearance.colors.colOnTertiaryContainer
    readonly property color errorBg: t.error_bg ?? Appearance.colors.colErrorContainer
    readonly property color errorText: t.on_error ?? Appearance.colors.colOnErrorContainer
    readonly property color composerBg: t.composer_bg ?? Appearance.colors.colLayer2
    readonly property color codeBg: t.code_bg ?? Appearance.colors.colLayer2

    // Glass / blur looks: a light gradient over the panel, edge width, drop shadow
    readonly property color sheen: t.sheen ?? "transparent"
    readonly property real borderWidth: t.border_width ?? 1
    readonly property bool shadow: t.shadow ?? true

    readonly property real radius: t.radius ?? 22
    readonly property real cardRadius: t.card_radius ?? 14
    readonly property real bubbleRadius: t.bubble_radius ?? 20
    readonly property string font: t.font || Appearance.font.family.main
    readonly property string monoFont: t.mono_font || Appearance.font.family.monospace
    readonly property real fontSize: (t.font_size ?? 15) * zoom
    readonly property real defaultWidth: t.width ?? 470
    readonly property real width: prefs.panelWidth > 0 ? prefs.panelWidth : defaultWidth
    // Actual display limits are supplied by the panel, including gaps/shadows.
    property real availableWidth: 1600
    readonly property real maxWidth: Math.max(1, Math.min(1600, availableWidth))
    readonly property real minWidth: Math.min(360, maxWidth)
    readonly property real panelWidth: Math.round(Math.min(maxWidth, Math.max(minWidth, width)))
    property bool prefsReady: false
    property bool themeReady: false
    function migrateSizing() {
        if (!prefsReady || !themeReady || prefs.sizingVersion >= 1) return;
        // Preserve the previous apparent width once, then keep it independent of text.
        if (prefs.panelWidth <= 0) prefs.panelWidth = Math.round(defaultWidth * Math.max(1, zoom));
        prefs.sizingVersion = 1;
    }
    function setWidth(w) {
        if (Number.isFinite(w)) prefs.panelWidth = Math.round(Math.min(maxWidth, Math.max(minWidth, w)));
    }
    function resetWidth() { prefs.panelWidth = 0; }
    function toggleWidth() { setWidth(panelWidth < defaultWidth * 1.25 ? defaultWidth * 1.5 : defaultWidth); }

    // Text zoom (Ctrl+Plus / Ctrl+Minus / Ctrl+0), kept across restarts
    readonly property real zoom: Number.isFinite(prefs.zoom) ? Math.min(2, Math.max(0.7, prefs.zoom)) : 1
    function setZoom(z) {
        if (Number.isFinite(z)) prefs.zoom = Math.round(Math.min(2, Math.max(0.7, z)) * 10) / 10;
    }
    function zoomKey(event) {
        if (!(event.modifiers & Qt.ControlModifier)) return false;
        if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) setZoom(zoom + 0.1);
        else if (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore) setZoom(zoom - 0.1);
        else if (event.key === Qt.Key_0) setZoom(1);
        else return false;
        return true;
    }
    readonly property bool rightSide: t.side === "right"
    readonly property string assistantName: t.assistant_name ?? "Gecko"
    readonly property string avatar: t.avatar ?? "🦎"

    Timer {
        id: savePrefs
        interval: 150
        onTriggered: prefsFile.writeAdapter()
    }
    FileView {
        id: prefsFile
        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/geckos-helper/panel.json`
        atomicWrites: false
        onAdapterUpdated: if (root.prefsReady) savePrefs.restart()
        onLoaded: { root.prefsReady = true; Qt.callLater(root.migrateSizing); }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.prefsReady = true;
                Qt.callLater(root.migrateSizing);
                savePrefs.restart();
            }
        }
        JsonAdapter {
            id: prefs
            property real zoom: 1
            property real panelWidth: 0
            property int sizingVersion: 0
        }
    }

    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/geckos-helper/theme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: error => { root.themeReady = true; Qt.callLater(root.migrateSizing); }
        onLoaded: {
            try {
                const out = JSON.parse(text());
                root.t = out.tokens ?? {};
                root.name = out.name;
                root.themes = out.themes ?? [];
                root.error = out.error ?? "";
            } catch (e) {
                console.warn("[Gecko] bad theme.json:", e);
            }
            root.themeReady = true;
            Qt.callLater(root.migrateSizing);
        }
    }
}
