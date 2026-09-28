import QtQuick
import Quickshell.Io
import "Release.js" as Release

Item {
    id: root

    property bool active: true
    // Consumers observe one settled result, never a mixture of old path and new status.
    property var state: ({
        "status": "checking",
        "path": ""
    })
    readonly property string status: state.status
    readonly property string path: state.path || ""
    property string version: Release.version
    property string error: ""
    property bool downloadAvailable: false
    property bool updatePending: false
    property real sizeBytes: 0
    property string operation: "status"
    property bool received: false
    property bool purgeQueued: false
    readonly property bool ready: path !== ""

    signal activated()
    signal settled()

    function publish(next) {
        state = next;
        settled();
    }

    function check() {
        run("status");
    }

    function download() {
        run("install");
    }

    function rollback() {
        run("rollback");
    }

    function purge() {
        if (runner.running) {
            purgeQueued = true;
            runner.running = false;
            return ;
        }
        run("purge");
    }

    function cancel() {
        runner.running = false;
        publish({
            "status": path ? "ready" : "needsRuntime",
            "path": path
        });
    }

    function run(op) {
        if (runner.running)
            return ;

        operation = op;
        received = false;
        error = "";
        publish({
            "status": op === "install" ? "downloading" : "checking",
            "path": path
        });
        runner.command = ["python3", Qt.resolvedUrl("../scripts/runtime.py").toString().replace("file://", ""), op];
        if (op === "install")
            runner.command = runner.command.concat(["--consent"]);

        if (op === "purge")
            runner.command = runner.command.concat(["--confirm-user-data-deletion"]);

        runner.running = true;
    }

    onActiveChanged: {
        if (active) {
            check();
        } else {
            purgeQueued = false;
            runner.running = false;
        }
    }
    Component.onCompleted: {
        if (active)
            check();

    }

    Process {
        id: runner

        onExited: {
            if (root.purgeQueued) {
                root.purgeQueued = false;
                Qt.callLater(function() {
                    root.run("purge");
                });
                return ;
            }
            if (!root.received && root.status !== "needsRuntime") {
                root.error = "runtime_error";
                root.publish({
                    "status": root.path ? "ready" : "needsRuntime",
                    "path": root.path
                });
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                if (root.purgeQueued)
                    return ;

                try {
                    var result = JSON.parse(line);
                    root.received = true;
                    if (!result.ok) {
                        root.publish({
                            "status": root.path ? "ready" : "needsRuntime",
                            "path": root.path
                        });
                        root.error = result.error;
                        return ;
                    }
                    root.version = result.version || root.version;
                    root.downloadAvailable = result.downloadAvailable || false;
                    root.sizeBytes = result.sizeBytes || 0;
                    root.updatePending = result.updatePending || false;
                    var previous = root.path;
                    root.publish({
                        "status": result.status,
                        "path": result.path || ""
                    });
                    if (root.path && root.path !== previous)
                        root.activated();

                } catch (_) {
                    root.error = "runtime_error";
                    root.publish({
                        "status": "needsRuntime",
                        "path": ""
                    });
                }
            }
        }

        stderr: SplitParser {
            splitMarker: ""
            onRead: (_data) => {
            }
        }

    }

}
