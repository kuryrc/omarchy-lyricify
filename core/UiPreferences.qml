import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string language: "auto"
    property bool remoteArtwork: false
    property string error: ""
    property string pending: ""
    property var defaults: ({
        "width": 520,
        "offsetX": 430,
        "monitor": "",
        "hideFullscreen": true,
        "pauseCollapseMs": 5000
    })
    property var overrides: ({
    })
    readonly property var display: Object.assign({
    }, defaults, overrides)
    property bool loaded: false
    property bool legacyLoaded: false
    property bool migrated: false
    property var legacy: null
    readonly property string directory: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy-lyricify"

    function validateDisplay(value) {
        if (!value || typeof value !== "object" || Array.isArray(value))
            throw new Error("display");

        var limits = {
            "width": [300, 900],
            "offsetX": [-3000, 3000],
            "pauseCollapseMs": [100, 60000]
        };
        Object.keys(value).forEach(function(key) {
            if (limits[key]) {
                if (!Number.isFinite(value[key]) || value[key] < limits[key][0] || value[key] > limits[key][1])
                    throw new Error("range");

            } else if (key === "monitor") {
                if (typeof value[key] !== "string")
                    throw new Error("monitor");

            } else if (key === "hideFullscreen") {
                if (typeof value[key] !== "boolean")
                    throw new Error("fullscreen");

            } else {
                throw new Error("unknown setting");
            }
        });
        return value;
    }

    function migrate() {
        if (!loaded || !legacyLoaded || !legacy || error || pending)
            return ;

        if (migrated) {
            retireLegacy();
            return ;
        }
        // Old install-tree config only fills absent overrides. User settings win.
        overrides = Object.assign({
        }, legacy, overrides);
        save();
    }

    function retireLegacy() {
        if (!legacy || !migrated || error || archiveLegacy.running)
            return ;

        archiveLegacy.command = ["mv", "-T", "--", Qt.resolvedUrl("../config.json").toString().replace("file://", ""), directory + "/legacy-display-" + Date.now() + ".json"];
        archiveLegacy.running = true;
    }

    function saveDisplay(key, value) {
        var next = Object.assign({
        }, overrides);
        next[key] = value;
        try {
            overrides = validateDisplay(next);
            save();
        } catch (_) {
            error = "storage_error";
        }
    }

    function saveLanguage(value) {
        if (["auto", "en", "zh_CN"].indexOf(value) < 0)
            return ;

        language = value;
        save();
    }

    function saveRemoteArtwork(value) {
        remoteArtwork = !!value;
        save();
    }

    function reset() {
        mkdir.running = false;
        migrated = true;
        language = "auto";
        remoteArtwork = false;
        overrides = ({
        });
        pending = "";
        error = "";
        legacy = null;
    }

    function save() {
        migrated = true;
        error = "";
        pending = JSON.stringify({
            "schemaVersion": 1,
            "language": language,
            "remoteArtwork": remoteArtwork,
            "display": overrides
        }) + "\n";
        mkdir.running = true;
    }

    FileView {
        path: Qt.resolvedUrl("../assets/defaults.json")
        onLoaded: {
            try {
                root.defaults = root.validateDisplay(JSON.parse(text()));
            } catch (_) {
                root.error = "storage_error";
            }
        }
    }

    FileView {
        path: Qt.resolvedUrl("../config.json")
        printErrors: false
        onLoaded: {
            try {
                root.legacy = root.validateDisplay(JSON.parse(text()));
            } catch (_) {
                root.error = "storage_error";
            }
            root.legacyLoaded = true;
            root.migrate();
        }
        onLoadFailed: (error) => {
            root.legacyLoaded = true;
            if (error !== FileViewError.FileNotFound)
                root.error = "storage_error";

        }
    }

    FileView {
        id: file

        path: root.directory + "/ui.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            if (root.pending)
                return ;

            try {
                var saved = JSON.parse(text());
                if (saved.schemaVersion !== 1 || ["auto", "en", "zh_CN"].indexOf(saved.language) < 0)
                    throw new Error("schema");

                root.language = saved.language;
                root.remoteArtwork = saved.remoteArtwork === true;
                root.overrides = root.validateDisplay(saved.display || {
                });
                // A completed migration must not be reimported after resetting a preference.
                root.migrated = saved.display !== undefined;
                root.loaded = true;
                root.migrate();
            } catch (_) {
                root.error = "storage_error";
            }
        }
        onSaveFailed: root.error = "storage_error"
        onSaved: root.retireLegacy()
        onLoadFailed: (error) => {
            if (error !== FileViewError.FileNotFound)
                root.error = "storage_error";

            root.loaded = true;
            root.migrate();
        }
    }

    Process {
        id: archiveLegacy

        onExited: (code, status) => {
            if (code === 0 && status === 0)
                root.legacy = null;
            else
                root.error = "storage_error";
        }
    }

    Process {
        id: mkdir

        command: ["mkdir", "-p", "--", root.directory]
        onExited: (code, status) => {
            if (!root.pending)
                return ;

            if (code === 0 && status === 0)
                file.setText(root.pending);
            else
                root.error = "storage_error";
        }
    }

}
