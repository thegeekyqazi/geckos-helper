// Isolated checks of the functions actually shipped in QML. No desktop/socket access.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const base = new URL('../quickshell/gecko/gecko/', import.meta.url);
function extract(file, name) {
    const text = fs.readFileSync(new URL(file, base), 'utf8');
    const start = text.indexOf(`    function ${name}(`);
    assert(start >= 0, name);
    const brace = text.indexOf('{', start);
    let depth = 0, quote = '', escaped = false;
    for (let i = brace; i < text.length; i++) {
        const c = text[i];
        if (quote) {
            if (escaped) escaped = false;
            else if (c === '\\') escaped = true;
            else if (c === quote) quote = '';
            continue;
        }
        if ('\'"`'.includes(c)) { quote = c; continue; }
        if (c === '{') depth++;
        if (c === '}' && --depth === 0) return text.slice(start, i + 1);
    }
    throw new Error(`Unclosed function ${name}`);
}
const errors = [], toasts = [], writes = [];
const root = {nextId: 1, callbacks: {}, addError: e => errors.push(e), showToast: t => toasts.push(t),
    chatId: 'fixture', exporting: false, copyingHandoff: false};
const socket = {connected: true, write: t => writes.push(JSON.parse(t)), flush() {}};
const ctx = vm.createContext({root, socket});
for (const name of ['call', 'handle', 'exportChat', 'copyHandoff']) {
    vm.runInContext(extract('Gecko.qml', name), ctx);
    root[name] = ctx[name];
}
root.exportChat('brief');
assert.equal(writes.at(-1).preview, true);
assert.equal(root.exporting, true);
root.handle({reply: writes.at(-1).id, ok: false, error: 'Fixture export failure'});
assert.equal(root.exporting, false);
assert.equal(errors.at(-1), 'Fixture export failure');
root.exportChat('brief');
root.handle({reply: writes.at(-1).id, ok: true, text: 'Reviewed fixture', warnings: ['Missing file']});
assert.equal(root.page, 'handoff');
assert.equal(root.handoffText, 'Reviewed fixture');
root.copyHandoff('User edited text');
assert.equal(writes.at(-1).op, 'copy_handoff');
assert.equal(writes.at(-1).text, 'User edited text');
root.handle({reply: writes.at(-1).id, ok: false, error: 'Clipboard disabled'});
assert.equal(root.copyingHandoff, false);
assert.equal(root.handoffText, 'Reviewed fixture');
socket.connected = false;
root.exportChat('brief');
assert.equal(root.exporting, false);
assert.equal(Object.keys(root.callbacks).length, 0);
const prefs = {zoom: 1.5, panelWidth: 705};
const size = vm.createContext({prefs, minWidth: 360, maxWidth: 1200});
for (const name of ['setZoom', 'setWidth', 'resetWidth']) vm.runInContext(extract('Theme.qml', name), size);
size.setZoom(2);
assert.equal(prefs.panelWidth, 705);
size.setWidth(900);
assert.equal(prefs.zoom, 2);
assert.equal(prefs.panelWidth, 900);
size.setWidth(9000); assert.equal(prefs.panelWidth, 1200);
size.setWidth(10); assert.equal(prefs.panelWidth, 360);
size.setZoom(0.1); assert.equal(prefs.zoom, 0.7);
size.setZoom(99); assert.equal(prefs.zoom, 2);
size.setZoom(NaN); assert.equal(prefs.zoom, 2);
size.resetWidth(); assert.equal(prefs.panelWidth, 0);
console.log('QML state checks passed: handoff preview/failures/offline, edited copy, independent sizing and bounds.');
