import QtQuick
import Quickshell.Io
import qs.modules.common

/**
 * Applies end-4's wallpaper-generated Material colors, like its MaterialThemeLoader
 * (which lives in the ii shell process, not ours).
 */
FileView {
    id: root
    path: Directories.generatedMaterialThemePath
    watchChanges: true
    onFileChanged: {
        reload();
        delayedApply.start();
    }
    onLoaded: apply(text())

    function apply(content) {
        try {
            const json = JSON.parse(content);
            for (const key in json) {
                const camel = key.replace(/_([a-z])/g, g => g[1].toUpperCase());
                Appearance.m3colors[`m3${camel}`] = json[key];
            }
            Appearance.m3colors.darkmode = Appearance.m3colors.m3background.hslLightness < 0.5;
        } catch (e) {
            console.warn("[Gecko] could not apply theme:", e);
        }
    }

    property Timer delayedApply: Timer {
        interval: 100
        onTriggered: root.apply(root.text())
    }
}
