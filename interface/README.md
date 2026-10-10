# Liftoff · macOS demo app

Native SwiftUI front-end for the RL environment audit service. Runs the whole demo on bundled fixture
data; swaps to the Python backend with one line.

## Build & run

Requirements: macOS 26, Xcode 27, `brew install xcodegen`.

```bash
make run      # xcodegen + xcodebuild Debug + open the .app
make build    # just build
make test     # XCTest: fixture decoder + stage state machine + store pipeline
make gen      # regenerate Liftoff.xcodeproj from project.yml (never hand-edit the project)
make fixtures # regenerate Resources/fixtures from scripts/make_fixtures.py
```

The Makefile sets `DEVELOPER_DIR` to `/Applications/Xcode.app` because `xcode-select` on the demo
Mac points at Command Line Tools. Override with `make DEVELOPER_DIR=/path build`.

Or open `Liftoff.xcodeproj` after `make gen` and hit Run.

## Demo flow

Left sidebar = six stages that unlock in order and stay revisitable. Top bar = environment, model,
phase, elapsed time.

1. **Load** — pick a recent environment or drop a folder. Click **Audit**.
2. **Lint** — static findings grouped by severity; expand for location, explanation, proposed fix.
   Click **Run adversarial training**.
3. **Train** — live chart, proxy reward vs true score. The liftoff marker and accent colour appear when
   they diverge. Trajectories fill in below; click one for prompt / output / reward / grader notes.
4. **Patch** — unified diff, rationale, and the Learning Scope allow/deny list. **Apply & re-verify**.
5. **Verify** — same chart on the patched environment, plus a before/after strip. **Issue certificate**.
6. **Certificate** — printable audit record. **Export PDF…**

### Keyboard shortcuts

| Keys  | Action |
|-------|--------|
| `⌘→`  | Next stage (fires the current stage's primary action if the next stage is still locked) |
| `⌘←`  | Previous stage |
| `⌘⇧F` | Toggle fast-forward (training replays in ~1 s instead of ~30 s) |
| `⌘⇧R` | Reset the run, keep the environment |

## Switching backends

`Sources/App/LiftoffApp.swift`, in `init()`:

```swift
let backend: any AuditBackend = FixtureBackend.bundled(playback: playback)   // demo
// let backend: any AuditBackend = LocalHTTPBackend()                        // FastAPI on 127.0.0.1:8765
```

Port lives in `AppConfig.localBackendPort`. Endpoints and SSE framing are in `docs/contract.md`.
A mock server that serves the fixtures over that contract is in `../backend/mock_server.py`.

## Adding a fixture

1. Add a function to `scripts/make_fixtures.py` that writes the nine JSON files (copy `ifeval_fixture`).
2. `make fixtures`. The new folder under `Resources/fixtures/<env-id>/` is picked up automatically —
   the fixtures folder is a folder reference, so no project changes are needed.
3. `make test` checks every fixture decodes.

## Layout

```
Sources/App        LiftoffApp, AppConfig (product name, port, replay timing)
Sources/Domain     Contract.swift (wire types), Stage.swift (stage enum + state machine)
Sources/Backend    AuditBackend protocol, FixtureBackend, LocalHTTPBackend, PlaybackSettings
Sources/Store      DemoStore — single source of truth
Sources/Views      RootView, TopBar, Sidebar, Stages/*, Components/*
Resources/fixtures <env-id>/*.json
Tests              XCTest
docs/contract.md   wire format with example JSON
scripts            make_fixtures.py
```

Product name is `AppConfig.productName` — one edit to rename.
