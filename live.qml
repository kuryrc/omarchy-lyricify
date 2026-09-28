import QtQuick
import Quickshell

ShellRoot {
    // Apply checked changes with make reload-live, not intermediate editor saves.
    Component.onCompleted: Quickshell.watchFiles = false

    LyricIsland {
        demo: false
    }

}
