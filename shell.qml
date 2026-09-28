import QtQuick
import Quickshell

ShellRoot {
    // Keep the visible preview stable while its source files are being edited.
    Component.onCompleted: Quickshell.watchFiles = false

    LyricIsland {
        demo: true
    }

}
