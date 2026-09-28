# Script responsibilities

| Shipped runtime code | Purpose |
| --- | --- |
| runtime.py | Fixed-manifest download, verification, activation, rollback and confirmed data purge |
| backend-launch.py | Execute the selected backend; never build/download implicitly |
| launch.py | Register the application entry; reuse a preview or enable/summon the native plugin |

| Maintainer tool | Purpose |
| --- | --- |
| release-metadata.py | Generate/check QML and manifests from VERSION |
| package-local.py / install-local.py | Build a local candidate / install its runtime files |
| start-preview.py / stop-preview.py | Maintain one standalone preview |
| check-qml.py / format-qml.py | Parse/lint / atomically format QML |
| measure-preview.py | Measure the existing visible demo; does not certify audible sync |
| render-previews.py | Capture real QML with original fixture data, offscreen |

Prefer the stable `make` commands in [CONTRIBUTING](../CONTRIBUTING.md).
