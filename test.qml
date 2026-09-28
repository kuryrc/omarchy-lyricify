// Quickshell requires a root entry so core/ui stay inside its scanner root.
import QtQuick
import Quickshell
import "tests/quickshell" as Tests
ShellRoot {
    Loader {
        active: Quickshell.env("LYRIC_ISLAND_TEST_SUITE") !== "live"
        sourceComponent: Component { Tests.ProtocolSuite {} }
    }
    Loader {
        active: Quickshell.env("LYRIC_ISLAND_TEST_SUITE") === "live"
        sourceComponent: Component { Tests.LiveSuite {} }
    }
}
