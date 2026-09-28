import QtQuick
import QtTest
import "../../core" as Core

TestCase {
    name: "IslandLifecycle"
    Component { id: factory; Core.IslandSession {} }
    SignalSpy { id: settingsSpy; signalName: "settingsRequested" }
    SignalSpy { id: exitSpy; signalName: "exitRequested" }
    function test_first_install_prompt_and_dismissal() {
        var session = createTemporaryObject(factory, this);
        settingsSpy.target = session;
        settingsSpy.clear();
        session.runtimeStatus = "needsRuntime";
        compare(settingsSpy.count, 1);
        session.checkSetup();
        compare(settingsSpy.count, 1); // Closing settings is respected within this failure episode.
        session.runtimeStatus = "ready";
        session.backendStatus = "incompatible";
        compare(settingsSpy.count, 2);
    }
    function test_stop_and_open_again() {
        var session = createTemporaryObject(factory, this, {demo: true, runtimeStatus: "needsRuntime"});
        settingsSpy.target = session;
        exitSpy.target = session;
        settingsSpy.clear(); exitSpy.clear();
        session.checkSetup();
        compare(settingsSpy.count, 0);
        session.stop(); session.stop();
        compare(exitSpy.count, 1);
        compare(session.running, false);
        session.demo = false;
        compare(settingsSpy.count, 0);
        session.start();
        compare(session.running, true);
        compare(settingsSpy.count, 1);
    }
}
