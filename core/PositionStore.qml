import "I18n.js" as I18n
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string language: "auto"
    property bool demo: false
    property real savedOffset: NaN
    property string error: ""
    property string pending: ""
    readonly property string directory: Quickshell.env("LYRIC_ISLAND_STATE_DIR") || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-lyricify")
    readonly property string filePath: directory + (demo ? "/preview-position.json" : "/position.json")

    function save(offset) {
        if (!Number.isFinite(offset))
            return ;

        savedOffset = offset;
        error = "";
        pending = JSON.stringify({
            "version": 1,
            "offsetX": offset
        }) + "\n";
        ensureDirectory.running = true;
    }

    function reset() {
        ensureDirectory.running = false;
        savedOffset = NaN;
        pending = "";
        error = "";
    }

    FileView {
        id: file

        path: root.filePath
        printErrors: false
        atomicWrites: true
        onPathChanged: {
            root.savedOffset = NaN;
            root.pending = "";
            root.error = "";
        }
        onLoaded: {
            // Never let an asynchronous startup read override a new drag.
            if (root.pending)
                return ;

            try {
                var data = JSON.parse(text());
                if (data.version !== 1 || !Number.isFinite(data.offsetX) || Math.abs(data.offsetX) > 100000)
                    throw new Error("Invalid position");

                root.savedOffset = data.offsetX;
            } catch (_) {
                root.error = I18n.text(root.language, "Could not read saved position; using default", "无法读取保存的位置，使用默认位置");
            }
        }
        onLoadFailed: (error) => {
            if (error !== FileViewError.FileNotFound)
                root.error = I18n.text(root.language, "Could not read saved position", "无法读取保存的位置");

        }
        onSaveFailed: root.error = I18n.text(root.language, "Could not save position", "位置保存失败")
    }

    Process {
        id: ensureDirectory

        command: ["mkdir", "-p", "--", root.directory]
        onExited: (exitCode, exitStatus) => {
            if (!root.pending)
                return ;

            if (exitCode === 0 && exitStatus === 0)
                file.setText(root.pending);
            else
                root.error = I18n.text(root.language, "Could not create position directory", "无法创建位置保存目录");
        }
    }

}
