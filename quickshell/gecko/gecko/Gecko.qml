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
        case "inbox":
            root.inboxUnread = ev.unread;
            if (root.page === "inbox") root.refreshInbox();
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
            messages.append(root.entry({ kind: "user", text: e.text, streaming: false,
                                         extra: JSON.stringify(e.attachments ?? []) }));
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
                              output: e.warning ?? "",
                              inputJson: JSON.stringify(e.input ?? {}, null, 1),
                              permState: live ? "pending" : "expired", streaming: false }));
            break;
        case "permission_resolved": {
            const i = root.findLast(m => m.kind === "permission" && m.requestId === e.request_id);
            if (i >= 0) messages.setProperty(i, "permState", e.allow ? "allowed" : "denied");
            break;
        }
        case "guard_alert":
            messages.append(root.entry({ kind: "guard", title: e.source, text: (e.reasons ?? []).join(", ") }));
            root.tainted = true;
            break;
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
                               permState: "", extra: "" }, fields);
    }

    function addError(text) {
        messages.append(root.entry({ kind: "error", text: text, streaming: false }));
        root.scrollToEnd();
    }

    // --- actions -------------------------------------------------------------

    function refreshAll() {
        root.refreshChats();
        root.refreshInbox();
        root.call("models", {}, r => {
            root.models = r.models;
            root.defaultModel = r.default;
        });
        root.call("status", {}, r => {
            root.killed = r.killed;
            root.capabilities = r.capabilities;
            root.capabilityDescriptions = r.capability_descriptions;
            if (r.usage) root.usage = r.usage;
            root.budget = r.budget ?? {};
        });
    }

    function refreshStatus() {
        root.call("status", {}, r => root.budget = r.budget ?? {});
    }

    function refreshChats() {
        root.call("chats", { limit: 100 }, r => root.chats = r.chats);
    }

    // --- attachments ----------------------------------------------------------

    property var attachments: [] // pending, shown as chips above the message box
    property bool capturing: false

    // kind: screenshot | window | clipboard | selection | file
    function capture(kind) {
        // Hide the panel so it isn't in the shot (and isn't the "focused" thing)
        const hide = kind === "screenshot" || kind === "window" || kind === "file";
        if (hide) root.open = false;
        root.capturing = true;
        captureDelay.kind = kind;
        captureDelay.reopen = hide;
        captureDelay.interval = hide ? 350 : 0;
        captureDelay.restart();
    }
    Timer {
        id: captureDelay
        property string kind
        property bool reopen
        onTriggered: root.call("capture", { kind: kind }, r => {
            root.capturing = false;
            if (r.attachment) root.attachments = [...root.attachments, r.attachment];
            else root.showToast(kind === "clipboard" || kind === "selection" ? "Nothing to attach" : "Cancelled");
            if (reopen) { root.page = "chat"; root.open = true; }
        })
    }
    function removeAttachment(index) {
        const a = root.attachments.slice();
        a.splice(index, 1);
        root.attachments = a;
    }

    // --- toasts -----------------------------------------------------------------

    property string toast: ""
    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }
    Timer { id: toastTimer; interval: 2600; onTriggered: root.toast = "" }

    // --- slash commands ----------------------------------------------------------

    // arg: what the command expects after its name ("" = nothing)
    readonly property var commands: [
        { name: "new", arg: "", desc: "Start a new chat", run: a => root.newChat() },
        { name: "screenshot", arg: "", desc: "Attach a screenshot of a region", run: a => root.capture("screenshot") },
        { name: "window", arg: "", desc: "Attach the focused window", run: a => root.capture("window") },
        { name: "clipboard", arg: "", desc: "Attach the clipboard", run: a => root.capture("clipboard") },
        { name: "selection", arg: "", desc: "Attach the selected text", run: a => root.capture("selection") },
        { name: "file", arg: "", desc: "Attach a file", run: a => root.capture("file") },
        { name: "todo", arg: "text", desc: "Add a to-do (instant, no AI)", run: a => root.quick("todo", a, "Added to your to-dos") },
        { name: "note", arg: "text", desc: "Pin a desktop note (instant)", run: a => root.quick("note", a, "Pinned to your desktop notes") },
        { name: "idea", arg: "text", desc: "Capture an idea in your vault (instant)", run: a => root.quick("idea", a, "Saved to your Gecko inbox note") },
        { name: "remember", arg: "fact", desc: "Tell Gecko something to remember", run: a => root.send(`Remember this about me: ${a}`) },
        { name: "model", arg: "sonnet|opus|haiku", desc: "Switch this chat's model", run: a => { root.setModel(a); root.showToast(`Model: ${a}`); } },
        { name: "theme", arg: "[name]", desc: "Next theme, or switch to one", run: a => root.call("theme", a ? { name: a } : { step: 1 }) },
        { name: "briefing", arg: "", desc: "Run the daily briefing now", run: a => { root.call("recipes", { run: "daily-briefing" }); root.showToast("Briefing running; it'll land in your inbox"); } },
        { name: "handoff", arg: "", desc: "Copy a hand-off brief for Claude.ai", run: a => root.exportChat("brief") },
        { name: "copy", arg: "", desc: "Copy this chat as markdown", run: a => root.exportChat("transcript") },
        { name: "calendar", arg: "", desc: "Open the calendar", run: a => root.page = "calendar" },
        { name: "inbox", arg: "", desc: "Open the inbox", run: a => root.page = "inbox" },
        { name: "history", arg: "", desc: "Open chat history", run: a => { root.refreshChats(); root.page = "history"; } },
        { name: "activity", arg: "", desc: "What Gecko did, watchers, recipes", run: a => root.page = "activity" },
        { name: "memory", arg: "", desc: "What Gecko remembers", run: a => root.page = "memory" },
        { name: "settings", arg: "", desc: "Capabilities and rules", run: a => root.page = "settings" },
        { name: "kill", arg: "", desc: "Toggle the kill switch", run: a => root.setKilled(!root.killed) },
    ]

    function matchCommands(text) {
        if (!text.startsWith("/")) return [];
        const word = text.slice(1).split(" ")[0].toLowerCase();
        if (text.includes(" ")) return root.commands.filter(c => c.name === word);
        return root.commands.filter(c => c.name.startsWith(word));
    }

    // Run "/name arg". Returns false if it isn't a known command.
    function runCommand(text) {
        const m = text.trim().match(/^\/(\S+)\s*([\s\S]*)$/);
        const cmd = m && root.commands.find(c => c.name === m[1].toLowerCase());
        if (!cmd) return false;
        if (cmd.arg && !cmd.arg.startsWith("[") && !m[2].trim()) {
            root.showToast(`/${cmd.name} needs ${cmd.arg}`);
            return true;
        }
        cmd.run(m[2].trim());
        return true;
    }

    function quick(action, text, done) {
        root.call("quick", { action: action, text: text }, () => root.showToast(done));
    }

    function send(text) {
        text = text.trim();
        if (!text.length && !root.attachments.length) return;
        if (text.startsWith("/") && root.runCommand(text)) return;
        const args = { text: text, attachments: root.attachments };
        root.attachments = [];
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
        root.tainted = false;
        messages.clear();
        root.page = "chat";
    }

    function openChat(id) {
        root.call("history", { chat: id }, r => {
            root.chatId = id;
            root.chatTitle = r.chat.title;
            root.chatModel = r.chat.model || root.defaultModel;
            root.busy = r.busy;
            root.tainted = !!r.taint;
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

    // This chat read content that looked like a prompt injection
    property bool tainted: false
    function clearTaint() {
        root.call("untaint", { chat: root.chatId }, () => root.tainted = false);
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

    property var inboxItems: []
    property int inboxUnread: 0
    property var recipes: []
    property var budget: ({})
    function refreshInbox() {
        root.call("inbox", {}, r => { root.inboxItems = r.items; root.inboxUnread = r.unread; });
    }
    function markRead(id) {
        root.call("inbox", { read: id }, r => { root.inboxItems = r.items; root.inboxUnread = r.unread; });
    }
    function deleteInboxItem(id) {
        root.call("inbox", { remove: id }, r => { root.inboxItems = r.items; root.inboxUnread = r.unread; });
    }
    function setRecipe(id, on) {
        root.call("recipes", on ? { enable: id } : { disable: id }, r => root.recipes = r.recipes);
    }
    function runRecipe(id) {
        root.call("recipes", { run: id }, r => root.recipes = r.recipes);
    }

    property var activity: []
    property var watchers: []
    property var goals: []
    function refreshActivity() {
        root.call("activity", { limit: 150 }, r => root.activity = r.entries);
        root.call("watchers", {}, r => root.watchers = r.watchers);
        root.call("goals", {}, r => root.goals = r.goals);
        root.call("recipes", {}, r => root.recipes = r.recipes);
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
