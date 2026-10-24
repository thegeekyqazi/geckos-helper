//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Gecko's Helper panel. A separate Quickshell config (qs -c gecko) that reuses
// end-4's common widgets and theme through symlinks made by install.sh, so it
// looks native but end-4 updates never overwrite it.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.gecko

ShellRoot {
    ThemeLoader {}

    GeckoPanel {}

    IpcHandler {
        target: "gecko"

        function toggle(): void { Gecko.open = !Gecko.open }
        function open(): void { Gecko.open = true }
        function close(): void { Gecko.open = false }
        function newChat(): void { Gecko.newChat(); Gecko.open = true }
        function history(): void { Gecko.refreshChats(); Gecko.page = "history"; Gecko.open = true }
        function settings(): void { Gecko.page = "settings"; Gecko.open = true }
        function activity(): void { Gecko.page = "activity"; Gecko.open = true }
        function ask(text: string): void {
            Gecko.newChat();
            Gecko.open = true;
            Gecko.send(text);
        }
    }
}
