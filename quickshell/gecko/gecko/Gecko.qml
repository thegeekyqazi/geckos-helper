pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Client for the gecko daemon (unix socket, one JSON object per line) and the
 * state the panel shows: current chat transcript, chats, models, usage, toggles.
 */
Singleton {
    id: root

    property bool connected: socket.connected
    property bool open: false
    property string page: "chat" // chat | history | settings

    property string chatId: ""
    property string chatTitle: ""
    property string chatModel: ""
    property bool busy: false
    property string pendingNonce: ""

    property var chats: []
    property var models: []
    property string defaultModel: ""
    property var usage: ({})
    property bool killed: false
    property var capabilities: ({})
    property var capabilityDescriptions: ({})

    // kind: user | agent | thought | tool | permission | error
    property ListModel messages: ListModel {}

    signal scrollToEnd()

    // --- socket --------------------------------------------------------------

    property int nextId: 1
    property var callbacks: ({})

    function call(op, args, cb) {
        const id = root.nextId++;
        if (cb) root.callbacks[id] = cb;
        socket.write(JSON.stringify(Object.assign({ id: id, op: op }, args ?? {})) + "\n");
        socket.flush();
    }

    Socket {
        id: socket
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/geckos-helper.sock`
        connected: true
        onConnectedChanged: if (connected) root.refreshAll()
        parser: SplitParser {
            onRead: line => root.handle(JSON.parse(line))
        }
    }

    Timer { // Daemon not up yet or restarted: keep retrying
        interval: 2000
        repeat: true
        running: !socket.connected
        onTriggered: {
            socket.connected = false;
            socket.connected = true;
        }
    }

    function handle(msg) {
        if (msg.reply !== undefined && msg.reply !== null) {
            const cb = root.callbacks[msg.reply];
            delete root.callbacks[msg.reply];
            if (!msg.ok) {
                root.exporting = false;
                if (!msg.error.startsWith("AttributeError")) root.addError(msg.error);
                else console.warn("[Gecko] daemon lacks op:", msg.error);
            }
            else if (cb) cb(msg);
            return;
        }
        if (msg.event) root.handleEvent(msg);
    }

    // --- events ----------------------------------------------------------------

    // Across all chats, for the mascot: which chats are working, which wait for approval
    property var busyChats: ({})
    property var pendingRequests: ({}) // request_id -> chat id
    property bool watcherRunning: false
    readonly property bool anyBusy: Object.keys(busyChats).length > 0
    readonly property int pendingCount: Object.keys(pendingRequests).length

    function trackGlobal(ev) {
        const busy = Object.assign({}, root.busyChats);
        const pending = Object.assign({}, root.pendingRequests);
        switch (ev.event) {
        case "user_message": busy[ev.chat] = true; break;
        case "turn_end": case "closed": delete busy[ev.chat]; break;
        case "permission_request": pending[ev.request_id] = ev.chat; break;
        case "permission_resolved": delete pending[ev.request_id]; break;
        case "watcher_running": root.watcherRunning = ev.on; return;
        default: return;
        }
        root.busyChats = busy;
        root.pendingRequests = pending;
    }

    // Open the panel on the chat that's waiting for an approval, if any
    function showAttention() {
        const chats = Object.values(root.pendingRequests);
        if (chats.length && chats[0] !== root.chatId) root.openChat(chats[0]);
        root.page = "chat";
        root.open = true;
    }

    function handleEvent(ev) {
        root.trackGlobal(ev);
        switch (ev.event) {
        case "chat_created":
            if (ev.nonce && ev.nonce === root.pendingNonce) {
                root.chatId = ev.chat;
                root.chatTitle = ev.title;
                root.chatModel = ev.model;
                root.pendingNonce = "";
            }
            root.refreshChats();
            return;
        case "kill_switch":
            root.killed = ev.on;
            if (ev.on) root.busy = false;
            return;
        case "capability":
            const caps = Object.assign({}, root.capabilities);
            caps[ev.name] = ev.on;
            root.capabilities = caps;
            return;
        case "default_model":
            root.defaultModel = ev.model;
            return;
        case "usage":
            root.usage = ev;
            return;
        case "activity":
            if (root.page === "activity") root.refreshActivity();
            return;
        case "chat_updated":
            if (ev.chat === root.chatId && ev.model) root.chatModel = ev.model;
            return;
        }
        if (ev.chat !== root.chatId) return;
        root.applyEntry(ev.event, ev, true);
    }

    function findLast(pred) {
        for (let i = messages.count - 1; i >= 0; i--) {
            if (pred(messages.get(i))) return i;
        }
        return -1;
    }

    // Claude's own bookkeeping tools; not interesting to show.
    readonly property var hiddenTools: ["ToolSearch", "TodoWrite"]
    property var hiddenToolIds: ({})

    function endThoughts() {
        for (let i = messages.count - 1; i >= 0; i--) {
            if (messages.get(i).kind === "thought" && messages.get(i).streaming)
                messages.setProperty(i, "streaming", false);
        }
    }

    // Shared by live events and transcript replay.
    function applyEntry(kind, e, live) {
        if (kind !== "agent_thought_chunk") root.endThoughts();
        switch (kind) {
        case "user_message":
            messages.append(root.entry({ kind: "user", text: e.text, streaming: false }));
            if (live) root.busy = true;
            break;
        case "agent_thought_chunk": {
            const last = messages.count ? messages.get(messages.count - 1) : null;
            if (last && last.kind === "thought" && last.streaming)
                messages.setProperty(messages.count - 1, "text", last.text + e.text);
            else
                messages.append(root.entry({ kind: "thought", text: e.text, streaming: true }));
            break;
        }
        case "agent_message_chunk": {
            const last = messages.count ? messages.get(messages.count - 1) : null;
            if (last && last.kind === "agent" && last.streaming)
                messages.setProperty(messages.count - 1, "text", last.text + e.text);
            else
                messages.append(root.entry({ kind: "agent", text: e.text, streaming: true }));
            break;
        }
        case "agent_message": {
            const i = root.findLast(m => m.kind === "agent" && m.streaming);
            if (i >= 0) {
                messages.setProperty(i, "text", e.text);
                messages.setProperty(i, "streaming", false);
            } else {
                messages.append(root.entry({ kind: "agent", text: e.text, streaming: false }));
            }
            break;
        }
        case "tool_call":
            if (root.hiddenTools.includes(e.name)) {
                root.hiddenToolIds[e.id] = true;
                break;
            }
            messages.append(root.entry({ kind: "tool", toolId: e.id, title: e.title, name: e.name,
                              status: "running", output: "", streaming: false }));
            break;
        case "tool_call_update": {
            if (root.hiddenToolIds[e.id]) break;
            const i = root.findLast(m => m.kind === "tool" && m.toolId === e.id);
            if (i >= 0) {
                messages.setProperty(i, "status", e.status);
                messages.setProperty(i, "output", e.output ?? "");
            }
            break;
        }
        case "permission_request":
            messages.append(root.entry({ kind: "permission", requestId: e.request_id, title: e.title, tool: e.tool,
                              inputJson: JSON.stringify(e.input ?? {}, null, 1),
                              permState: live ? "pending" : "expired", streaming: false }));
            break;
        case "permission_resolved": {
            const i = root.findLast(m => m.kind === "permission" && m.requestId === e.request_id);
            if (i >= 0) messages.setProperty(i, "permState", e.allow ? "allowed" : "denied");
            break;
        }
        case "turn_end":
        case "closed":
            if (live) {
                root.busy = false;
                root.refreshChats();
            }
            break;
        case "error":
            root.addError(e.message);
            break;
        }
        if (live) root.scrollToEnd();
    }

    // ListModel roles must be uniform, so every entry carries every role.
    function entry(fields) {
        return Object.assign({ kind: "", text: "", streaming: false, toolId: "", title: "", name: "",
                               status: "", output: "", requestId: "", tool: "", inputJson: "{}",
                               permState: "" }, fields);
    }

    function addError(text) {
        messages.append(root.entry({ kind: "error", text: text, streaming: false }));
        root.scrollToEnd();
    }

    // --- actions -------------------------------------------------------------

    function refreshAll() {
        root.refreshChats();
        root.call("models", {}, r => {
            root.models = r.models;
            root.defaultModel = r.default;
        });
        root.call("status", {}, r => {
            root.killed = r.killed;
            root.capabilities = r.capabilities;
            root.capabilityDescriptions = r.capability_descriptions;
            if (r.usage) root.usage = r.usage;
        });
    }

    function refreshChats() {
        root.call("chats", { limit: 100 }, r => root.chats = r.chats);
    }

    function send(text) {
        text = text.trim();
        if (!text.length) return;
        const args = { text: text };
        if (root.chatId) {
            args.chat = root.chatId;
        } else {
            root.pendingNonce = `${Date.now()}-${Math.random()}`;
            args.nonce = root.pendingNonce;
            args.model = root.chatModel || root.defaultModel;
        }
        root.call("send", args);
    }

    function stop() {
        if (root.chatId) root.call("stop", { chat: root.chatId });
    }

    function answerPermission(index, allow, scope) {
        const m = messages.get(index);
        let input = {};
        try { input = JSON.parse(m.inputJson); } catch (e) {}
        root.call("permission", { request_id: m.requestId, allow: allow, scope: scope ?? "once",
                                  tool: m.tool, input: input });
    }

    function newChat() {
        root.chatId = "";
        root.chatTitle = "";
        root.chatModel = root.defaultModel;
        root.busy = false;
        messages.clear();
        root.page = "chat";
    }

    function openChat(id) {
        root.call("history", { chat: id }, r => {
            root.chatId = id;
            root.chatTitle = r.chat.title;
            root.chatModel = r.chat.model || root.defaultModel;
            root.busy = r.busy;
            messages.clear();
            for (const e of r.entries) root.applyEntry(e.kind, e, false);
            // Requests still waiting for an answer stay actionable
            for (let i = 0; i < messages.count; i++) {
                const m = messages.get(i);
                if (m.kind === "permission" && r.pending_permissions.includes(m.requestId))
                    messages.setProperty(i, "permState", "pending");
            }
            root.page = "chat";
            root.scrollToEnd();
        });
    }

    function deleteChat(id) {
        root.call("delete", { chat: id }, () => {
            if (id === root.chatId) root.newChat();
            root.refreshChats();
        });
    }

    function setModel(model) {
        if (root.chatId) root.call("set_model", { chat: root.chatId, model: model });
        root.chatModel = model;
    }

    function setDefaultModel(model) {
        root.call("set_default_model", { model: model });
    }

    function setKilled(on) {
        root.call("kill", { on: on });
    }

    property var activity: []
    property var watchers: []
    property var goals: []
    function refreshActivity() {
        root.call("activity", { limit: 150 }, r => root.activity = r.entries);
        root.call("watchers", {}, r => root.watchers = r.watchers);
        root.call("goals", {}, r => root.goals = r.goals);
    }
    function deleteWatcher(id) {
        root.call("watchers", { remove: id }, r => root.watchers = r.watchers);
    }

    // Put text in the chat box (from other pages), switching to a new chat
    signal prefillRequested(string text)
    function prefill(text) {
        root.newChat();
        root.prefillRequested(text);
    }

    property var memories: []
    property string memoryDir: ""
    function refreshMemories() {
        root.call("memories", {}, r => { root.memories = r.memories; root.memoryDir = r.dir; });
    }
    function deleteMemory(file) {
        root.call("memories", { remove: file }, r => root.memories = r.memories);
    }

    property var rules: []
    function refreshRules() {
        root.call("rules", {}, r => root.rules = r.rules);
    }
    function removeRule(index) {
        root.call("rules", { remove: index }, r => root.rules = r.rules);
    }

    function setCapability(name, on) {
        root.call("capability", { name: name, on: on });
    }

    // Copy this chat to the clipboard to continue elsewhere. mode: transcript | brief
    property bool exporting: false
    function exportChat(mode, cb) {
        if (!root.chatId) return;
        root.exporting = true;
        root.call("export", { chat: root.chatId, mode: mode }, r => {
            root.exporting = false;
            Quickshell.execDetached(["notify-send", "-a", "Gecko's Helper", "Copied to clipboard",
                mode === "brief" ? "Hand-off brief ready to paste into Claude.ai" : "Chat transcript copied"]);
            if (cb) cb(r);
        });
    }

    function cycleTheme(step) {
        root.call("theme", { step: step ?? 1 });
    }

    function regenerateContext(cb) {
        root.call("context", {}, cb);
    }
}
