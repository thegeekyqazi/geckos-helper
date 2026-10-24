import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Audit trail: watchers and recipes first, then everything Gecko did,
 * newest first, with who decided each permission.
 */
StyledFlickable {
    id: root
    clip: true
    contentHeight: column.implicitHeight + 16
    onVisibleChanged: if (visible) Gecko.refreshActivity()

    function describe(e) {
        switch (e.kind) {
        case "action": {
            const name = (e.tool ?? "").replace(/_/g, " ");
            const arg = Object.values(e.args ?? {}).find(v => typeof v === "string") ?? "";
            return { icon: "build", title: arg ? `${name}: ${arg}` : name, detail: "tool action" };
        }
        case "permission": {
            const by = { once: "you", chat: "you, for this chat", always: "you, saved as a rule",
                         rule: "a saved rule", repeat: "automatically (repeat after a deny)" }[e.by] ?? e.by;
            return { icon: e.decision === "allow" ? "check_circle" : "block",
                     title: `${e.decision === "allow" ? "Allowed" : "Denied"}: ${e.title || e.tool}`,
                     detail: `by ${by}` };
        }
        case "watcher":
            return { icon: e.notified ? "notifications_active" : "visibility",
                     title: `${e.name}: ${e.message || (e.error ? "failed" : "nothing to report")}`,
                     detail: e.error ? `error: ${e.error}` : "watcher run" };
        case "guard":
            return { icon: "gpp_maybe", title: e.source === "you" ? "Guard warning cleared"
                                                 : `Possible prompt injection in ${e.source}`,
                     detail: (e.reasons ?? []).join(", ") };
        case "recipe":
            return { icon: e.flagged ? "gpp_maybe" : "auto_awesome",
                     title: `${e.name}: ${e.error ? "failed" : e.title ? e.title : "nothing to report"}`,
                     detail: e.error ? `error: ${e.error}` : e.trigger ? `triggered: ${e.trigger}` : "recipe run" };
        case "trigger":
            return { icon: "bolt", title: `Trigger: ${e.recipe}`, detail: e.why };
        case "budget":
            return { icon: "hourglass_top", title: "Background work paused", detail: e.reason };
        case "goal":
        case "project":
            return { icon: "folder_special", title: `${e.project ?? e.goal}: ${e.note}`, detail: "project update" };
        }
        return { icon: "info", title: e.kind, detail: "" };
    }

    function when(ts) {
        const d = new Date(ts * 1000);
        const today = new Date().toDateString() === d.toDateString();
        return d.toLocaleString(Qt.locale(), today ? "h:mm ap" : "MMM d, h:mm ap");
    }

    ColumnLayout {
        id: column
        x: 14
        width: root.width - 28
        spacing: 4

        Section { text: "Watching"; visible: Gecko.watchers.length > 0 }
        Repeater {
            model: Gecko.watchers
            delegate: Row {
                id: watchRow
                required property var modelData
                Layout.fillWidth: true
                Entry {
                    width: column.width - 64
                    iconName: watchRow.modelData.paused ? "pause_circle" : "visibility"
                    title: watchRow.modelData.name
                    detail: `${watchRow.modelData.schedule_text}` +
                            (watchRow.modelData.next_run ? ` · next ${root.when(watchRow.modelData.next_run)}` : "")
                }
                IconButton {
                    size: 28
                    iconName: "play_arrow"
                    tip: "Run now"
                    onClicked: Gecko.call("watchers", { run: watchRow.modelData.id })
                }
                IconButton {
                    size: 28
                    iconName: "delete"
                    tip: "Stop watching"
                    onClicked: Gecko.deleteWatcher(watchRow.modelData.id)
                }
            }
        }

        Section { text: "Recipes"; visible: Gecko.recipes.length > 0 }
        Repeater {
            model: Gecko.recipes
            delegate: RowLayout {
                id: recipeRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                Entry {
                    Layout.fillWidth: true
                    iconName: "auto_awesome"
                    title: recipeRow.modelData.name
                    detail: recipeRow.modelData.error ? `error: ${recipeRow.modelData.error}`
                        : recipeRow.modelData.schedule_text
                          + (recipeRow.modelData.next_run ? ` · next ${root.when(recipeRow.modelData.next_run)}` : "")
                }
                IconButton {
                    size: 28
                    iconName: "play_arrow"
                    tip: "Run now"
                    onClicked: Gecko.runRecipe(recipeRow.modelData.id)
                }
                StyledSwitch {
                    checked: recipeRow.modelData.enabled
                    onClicked: Gecko.setRecipe(recipeRow.modelData.id, checked)
                }
            }
        }
        GText {
            Layout.fillWidth: true
            visible: Gecko.recipes.length > 0
            text: "Edit or add recipes in ~/.config/geckos-helper/recipes/ (TOML), or ask Gecko to make one."
            muted: true
            rel: 0.7
        }

        Section { text: "Recent" }
        GText {
            visible: Gecko.activity.length === 0
            text: "Nothing yet."
            muted: true
            rel: 0.85
        }
        Repeater {
            model: Gecko.activity
            delegate: Entry {
                required property var modelData
                readonly property var info: root.describe(modelData)
                Layout.fillWidth: true
                iconName: info.icon
                title: info.title
                detail: `${root.when(modelData.ts)} · ${info.detail}`
            }
        }
    }

    component Section: GText {
        Layout.topMargin: 10
        Layout.bottomMargin: 2
        font.weight: Font.DemiBold
        rel: 0.85
        muted: true
    }

    component Entry: RowLayout {
        id: entry
        property string iconName
        property string title
        property string detail
        spacing: 10
        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
            text: entry.iconName
            iconSize: 18
            color: Theme.textMuted
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            GText { Layout.fillWidth: true; text: entry.title; rel: 0.88; maximumLineCount: 2; elide: Text.ElideRight }
            GText { Layout.fillWidth: true; text: entry.detail; muted: true; rel: 0.72 }
        }
    }
}
