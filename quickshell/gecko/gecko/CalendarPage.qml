import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Week strip + agenda for the selected day, across all calendars (Laurier, Google…).
 */
Item {
    id: root

    property date weekStart: mondayOf(new Date())
    property date selected: new Date()
    property var events: []
    property var errors: []
    property bool configured: true
    property bool loading: false

    function mondayOf(d) {
        const m = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        m.setDate(m.getDate() - ((m.getDay() + 6) % 7));
        return m;
    }
    function addDays(d, n) {
        const r = new Date(d);
        r.setDate(r.getDate() + n);
        return r;
    }
    function key(d) { // local YYYY-MM-DD
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    }
    function eventDay(e) {
        return e.all_day ? e.start.slice(0, 10) : key(new Date(e.start));
    }
    function onDay(d) {
        const k = key(d);
        return root.events.filter(e => {
            if (!e.all_day) return eventDay(e) === k;
            return e.start.slice(0, 10) <= k && k < (e.end ?? e.start).slice(0, 10) || e.start.slice(0, 10) === k;
        });
    }
    function timeText(iso) {
        return new Date(iso).toLocaleTimeString(Qt.locale(), "h:mm ap");
    }

    function load() {
        root.loading = true;
        Gecko.call("calendar", { start: key(root.weekStart), days: 7 }, r => {
            root.events = r.events;
            root.errors = r.errors;
            root.configured = r.configured;
            root.loading = false;
        });
    }
    onWeekStartChanged: load()
    onVisibleChanged: if (visible) load()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout { // Month + week navigation
            Layout.fillWidth: true
            GText {
                Layout.fillWidth: true
                text: root.weekStart.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                font.weight: Font.DemiBold
            }
            IconButton { iconName: "chevron_left"; tip: "Previous week"; onClicked: root.weekStart = root.addDays(root.weekStart, -7) }
            IconButton {
                iconName: "today"
                tip: "Today"
                onClicked: { root.selected = new Date(); root.weekStart = root.mondayOf(new Date()); }
            }
            IconButton { iconName: "chevron_right"; tip: "Next week"; onClicked: root.weekStart = root.addDays(root.weekStart, 7) }
        }

        RowLayout { // Week strip
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: 7
                delegate: RippleButton {
                    id: day
                    required property int index
                    readonly property date d: root.addDays(root.weekStart, index)
                    readonly property bool isSelected: root.key(d) === root.key(root.selected)
                    readonly property bool isToday: root.key(d) === root.key(new Date())
                    readonly property var dayEvents: root.onDay(d)
                    Layout.fillWidth: true
                    implicitHeight: 62
                    buttonRadius: Theme.cardRadius
                    colBackground: isSelected ? Theme.accent : "transparent"
                    colBackgroundHover: isSelected ? Theme.accent : Theme.surfaceHigh
                    colRipple: Theme.border
                    onClicked: root.selected = d
                    contentItem: ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 0
                        GText {
                            Layout.alignment: Qt.AlignHCenter
                            text: day.d.toLocaleDateString(Qt.locale(), "ddd")
                            rel: 0.7
                            color: day.isSelected ? Theme.accentText : Theme.textMuted
                        }
                        GText {
                            Layout.alignment: Qt.AlignHCenter
                            text: day.d.getDate()
                            rel: 1.1
                            font.weight: day.isToday ? Font.Bold : Font.Normal
                            color: day.isSelected ? Theme.accentText : day.isToday ? Theme.accent : Theme.text
                        }
                        Row { // One dot per calendar with events that day
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredHeight: 6
                            spacing: 3
                            Repeater {
                                model: [...new Set(day.dayEvents.map(e => e.color))].slice(0, 4)
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 5; height: 5; radius: 3
                                    color: day.isSelected ? Theme.accentText : modelData
                                }
                            }
                        }
                    }
                }
            }
        }

        GText {
            text: root.selected.toLocaleDateString(Qt.locale(), "dddd, MMMM d")
            muted: true
            rel: 0.85
        }

        StyledListView { // Agenda for the selected day
            id: agenda
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.onDay(root.selected).sort((a, b) => (b.all_day - a.all_day) || a.start.localeCompare(b.start))
            delegate: Rectangle {
                id: ev
                required property var modelData
                width: agenda.width
                implicitHeight: evRow.implicitHeight + 16
                radius: Theme.cardRadius - 4
                color: Theme.surface
                RowLayout {
                    id: evRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10
                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: 4
                        radius: 2
                        color: ev.modelData.color
                    }
                    GText {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 64
                        text: ev.modelData.all_day ? "All day"
                            : `${root.timeText(ev.modelData.start)}\n${ev.modelData.end ? root.timeText(ev.modelData.end) : ""}`
                        muted: true
                        rel: 0.75
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        GText { Layout.fillWidth: true; text: ev.modelData.title; rel: 0.9 }
                        GText {
                            Layout.fillWidth: true
                            text: [ev.modelData.location, ev.modelData.calendar].filter(x => x).join(" · ")
                            muted: true
                            rel: 0.72
                        }
                    }
                }
            }
            GText {
                anchors.centerIn: parent
                visible: agenda.count === 0 && !root.loading
                text: root.configured ? "Nothing scheduled" : "No calendars connected yet"
                muted: true
            }
        }

        GText { // Feed errors, e.g. offline
            Layout.fillWidth: true
            visible: root.errors.length > 0
            text: "Couldn't load: " + root.errors.join("; ")
            color: Theme.errorText
            rel: 0.75
        }

        RowLayout { // Legend + schedule button
            Layout.fillWidth: true
            Flow {
                Layout.fillWidth: true
                spacing: 10
                Repeater {
                    model: {
                        const seen = {};
                        for (const e of root.events) seen[e.calendar] = { color: e.color, writable: e.writable };
                        return Object.entries(seen);
                    }
                    delegate: Row {
                        required property var modelData
                        spacing: 4
                        Rectangle { width: 8; height: 8; radius: 4; color: modelData[1].color; anchors.verticalCenter: parent.verticalCenter }
                        GText { text: modelData[0] + (modelData[1].writable ? "" : " (read-only)"); muted: true; rel: 0.72 }
                    }
                }
            }
            DialogButton {
                buttonText: "Schedule…"
                onClicked: Gecko.prefill(`Schedule on ${root.selected.toLocaleDateString(Qt.locale(), "dddd MMMM d")}: `)
            }
        }
    }
}
