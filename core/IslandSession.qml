import QtQuick

QtObject {
    id: root

    property bool running: true
    property bool demo: false
    property string runtimeStatus: "checking"
    property string backendStatus: "starting"
    property bool prompted: false
    readonly property bool needsSetup: !demo && (runtimeStatus === "needsRuntime" || runtimeStatus === "purged" || backendStatus === "failed" || backendStatus === "incompatible")

    signal settingsRequested()
    signal exitRequested()

    function checkSetup() {
        if (running && needsSetup && !prompted) {
            prompted = true;
            settingsRequested();
        }
    }

    function start() {
        running = true;
        prompted = false;
        checkSetup();
    }

    function stop() {
        if (!running)
            return ;

        running = false;
        exitRequested();
    }

    onNeedsSetupChanged: {
        if (!needsSetup)
            prompted = false;

        checkSetup();
    }
    Component.onCompleted: checkSetup()
}
