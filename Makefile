.PHONY: check check-ui build test test-backend format demo live reload-live smoke stop install-local package-local
QMLTESTRUNNER ?= /usr/lib/qt6/bin/qmltestrunner

build:
	python3 scripts/release-metadata.py --check
	dotnet build backend/LyricIsland.Backend -c Release --nologo
	dotnet build backend/LyricIsland.Tests -c Release --nologo

test-backend: build
	node --test tests/*.test.cjs
	python3 tests/integration_test.py
	dotnet backend/LyricIsland.Tests/bin/Release/net10.0/LyricIsland.Tests.dll
	python3 tests/lyrics_integration_test.py
	python3 tests/runtime_test.py
	python3 tests/launcher_test.py

test: test-backend
	python3 tests/quickshell_test.py
	python3 tests/live_qml_test.py
	python3 tests/startup_test.py
	python3 tests/preferences_test.py
	QT_QPA_PLATFORM=offscreen $(QMLTESTRUNNER) -input tests/qml

check: test
	omarchy plugin validate .
	python3 scripts/check-qml.py

format:
	python3 scripts/format-qml.py

check-ui:
	python3 scripts/check-qml.py
	QT_QPA_PLATFORM=offscreen $(QMLTESTRUNNER) -input tests/qml

reload-live: check-ui
	python3 scripts/stop-preview.py
	python3 scripts/start-preview.py live

demo:
	python3 scripts/start-preview.py demo

live:
	python3 scripts/start-preview.py live

smoke:
	python3 tests/ui_smoke.py

stop:
	python3 scripts/stop-preview.py

install-local: package-local
	python3 scripts/install-local.py

package-local:
	python3 scripts/package-local.py

.PHONY: version
version:
	python3 scripts/release-metadata.py

.PHONY: verify-package
verify-package: package-local
	python3 tests/runtime_test.py --package
	python3 tests/runtime_lifecycle_test.py

.PHONY: previews
previews:
	python3 scripts/render-previews.py
