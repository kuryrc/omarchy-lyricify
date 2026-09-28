import "Protocol.js" as Protocol
import QtQuick
import Quickshell
import Quickshell.Io
import "Release.js" as Release
import "Timeline.js" as Timeline

Item {
    id: root

    property bool active: true
    property alias bootstrap: runtime
    property bool replacingRuntime: false
    property bool purgeRequested: false
    property string status: "starting"
    property string error: ""
    property string epoch: ""
    property int requestNumber: 0
    property real sequence: 0
    property var snapshot: null
    property var scope: null
    property var document: null
    property var pendingDocument: null
    property var pending: ({
    })
    property var restartTimes: []
    property string buffer: ""
    readonly property bool ready: status === "ready"

    signal sampled(var state, var trackScope)
    signal response(string id, string operation, var result, string code)

    function start() {
        if (!active || process.running || !runtime.ready)
            return ;

        epoch = "";
        sequence = 0;
        buffer = "";
        pending = ({
        });
        pendingDocument = null;
        status = "starting";
        process.stdinEnabled = true;
        process.running = true;
    }

    function stopOwnedProcess() {
        if (!process.running)
            return ;

        process.stdinEnabled = false;
        gracefulDeadline.start();
    }

    function retry() {
        restartTimes = [];
        error = "";
        if (!runtime.ready)
            runtime.check();
        else if (!process.running)
            start();
    }

    function purgeData() {
        restart.stop();
        replacingRuntime = false;
        status = "purging";
        error = "";
        snapshot = null;
        scope = null;
        document = null;
        if (process.running) {
            purgeRequested = true;
            stopOwnedProcess();
        } else {
            runtime.purge();
        }
    }

    function fail(code, incompatible) {
        error = code;
        status = incompatible ? "incompatible" : "recovering";
        process.running = false;
    }

    function request(op, params, scoped) {
        if ((!ready && op !== "hello") || Object.keys(pending).length >= 32)
            return "";

        var id = "r" + (++requestNumber);
        var message = {
            "version": 2,
            "type": "request",
            "id": id,
            "op": op,
            "params": params || {
            }
        };
        if (op !== "hello")
            message.backendSessionId = epoch;

        if (scoped)
            message.scope = scope;

        var text = JSON.stringify(message);
        if (text.length > 900000) {
            error = "document_too_large";
            return "";
        }
        pending[id] = {
            "op": op,
            "sent": timer.elapsedMs()
        };
        process.write(text + "\n");
        return id;
    }

    function adoptDocument() {
        if (!snapshot)
            return ;

        var next = pendingDocument;
        if (next && Protocol.scopeEqual(next.scope, scope) && next.payload.resolutionId === snapshot.lyrics.resolutionId && next.payload.documentId === snapshot.lyrics.documentId) {
            document = next.payload;
            pendingDocument = null;
        } else if (!document || document.documentId !== snapshot.lyrics.documentId || document.resolutionId !== snapshot.lyrics.resolutionId) {
            document = null;
        }
    }

    function receive(line) {
        try {
            if (line.length > 1.04858e+06)
                throw new Error("size");

            var m = JSON.parse(line);
            if (m.version !== 2) {
                fail("incompatible_backend", true);
                return ;
            }
            if (m.type === "response") {
                var waiting = pending[m.id];
                if (!waiting)
                    return ;

                if (waiting.op !== "hello" && m.backendSessionId !== epoch)
                    return ;

                delete pending[m.id];
                if (waiting.op === "hello") {
                    if (!m.ok || m.result.protocol !== 2 || m.result.backendVersion !== runtime.version || !Array.isArray(m.result.capabilities) || m.result.capabilities.indexOf("playback") < 0 || typeof m.backendSessionId !== "string") {
                        fail("incompatible_backend", true);
                        return ;
                    }
                    epoch = m.backendSessionId;
                    scope = null;
                    status = "ready";
                    error = "";
                    return ;
                }
                var code = m.ok ? "" : (m.error ? m.error.code : "backend_unavailable");
                if (code)
                    error = code;

                response(m.id, waiting.op, m.result || null, code);
                return ;
            }
            if (!ready || m.type !== "event" || m.backendSessionId !== epoch || !Number.isSafeInteger(m.seq) || m.seq <= sequence)
                return ;

            if (!Protocol.validScope(m.scope))
                throw new Error("scope");

            sequence = m.seq;
            if (scope && m.scope && m.scope.trackGeneration < scope.trackGeneration)
                return ;

            if (m.event === "session.state") {
                if (!Protocol.validState(m.payload))
                    throw new Error("state");

                scope = m.scope;
                snapshot = m.payload;
                adoptDocument();
                sampled(snapshot, scope);
            } else if (m.event === "lyrics.document") {
                if (!m.payload || !Timeline.validate(m.payload.document) || typeof m.payload.documentId !== "string")
                    throw new Error("document");

                pendingDocument = m;
                adoptDocument();
            }
        } catch (_) {
            fail("invalid_backend_message", false);
        }
    }

    function chunk(data) {
        var start = 0, end;
        while ((end = data.indexOf("\n", start)) >= 0) {
            if (buffer.length + end - start > 1.04858e+06) {
                buffer = "";
                fail("document_too_large", false);
                return ;
            }
            var line = buffer + data.slice(start, end);
            buffer = "";
            if (line)
                receive(line);

            start = end + 1;
        }
        buffer += data.slice(start);
        if (buffer.length > 1.04858e+06) {
            buffer = "";
            fail("document_too_large", false);
        }
    }

    onActiveChanged: {
        if (active) {
            start();
        } else {
            restart.stop();
            status = "stopped";
            stopOwnedProcess();
        }
    }
    Component.onCompleted: {
        if (active)
            start();

    }
    Component.onDestruction: {
        active = false;
        if (process.running)
            process.stdinEnabled = false;

    }

    ElapsedTimer {
        id: timer
    }

    RuntimeBootstrap {
        id: runtime

        active: root.active
        onSettled: {
            if (!state.path)
                root.status = state.status;

        }
        onActivated: {
            if (process.running) {
                root.replacingRuntime = true;
                root.stopOwnedProcess();
            } else {
                root.start();
            }
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: root.active
        onTriggered: {
            var now = timer.elapsedMs();
            Object.keys(root.pending).forEach(function(id) {
                var request = root.pending[id];
                if (now - request.sent > 5000) {
                    delete root.pending[id];
                    if (request.op === "hello") {
                        root.fail("handshake_timeout", false);
                    } else {
                        root.error = "timeout";
                        root.response(id, request.op, null, "timeout");
                    }
                }
            });
        }
    }

    Timer {
        id: restart

        onTriggered: root.start()
    }

    Timer {
        id: gracefulDeadline

        interval: 1500
        onTriggered: {
            process.running = false;
            killDeadline.start();
        }
    }

    Timer {
        id: killDeadline

        interval: 500
        onTriggered: {
            if (process.running)
                process.signal(9);

        }
    }

    Process {
        id: process

        command: ["python3", Qt.resolvedUrl("../scripts/backend-launch.py").toString().replace("file://", "")]
        stdinEnabled: true
        onStarted: {
            root.status = "handshaking";
            root.request("hello", {
                "clientVersion": Release.version,
                "supportedProtocols": [2],
                "clientInstanceId": "qml"
            }, false);
        }
        onExited: {
            gracefulDeadline.stop();
            killDeadline.stop();
            var outstanding = root.pending;
            root.pending = ({
            });
            Object.keys(outstanding).forEach(function(id) {
                root.response(id, outstanding[id].op, null, "backend_unavailable");
            });
            if (root.purgeRequested) {
                root.purgeRequested = false;
                runtime.purge();
                return ;
            }
            if (root.replacingRuntime) {
                root.replacingRuntime = false;
                root.start();
                return ;
            }
            if (!root.active || root.status === "incompatible")
                return ;

            var now = timer.elapsedMs();
            var attempts = root.restartTimes.filter(function(t) {
                return now - t < 60000;
            });
            if (attempts.length >= 3) {
                root.status = "failed";
                root.error = "backend_unavailable";
                return ;
            }
            restart.interval = [1000, 2000, 5000][attempts.length];
            attempts.push(now);
            root.restartTimes = attempts;
            root.status = "recovering";
            restart.start();
        }

        stdout: SplitParser {
            splitMarker: ""
            onRead: (data) => {
                return root.chunk(data);
            }
        }

        stderr: SplitParser {
            splitMarker: ""
            onRead: (_data) => {
            }
        }

    }

}
