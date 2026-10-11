# Provost · macOS demo app

Native SwiftUI front-end for the RL environment audit service. Runs the whole demo on bundled fixture
data; swaps to the Python backend with one line.

## Build & run

Requirements: macOS 26, Xcode 27, `brew install xcodegen`.

```bash
make run      # xcodegen + xcodebuild Debug + open the .app
make build    # just build
make test     # XCTest: fixture decoder + stage state machine + store pipeline
make gen      # regenerate Provost.xcodeproj from project.yml (never hand-edit the project)
make fixtures # regenerate Resources/fixtures from scripts/make_fixtures.py
```

The Makefile sets `DEVELOPER_DIR` to `/Applications/Xcode.app` because `xcode-select` on the demo
Mac points at Command Line Tools. Override with `make DEVELOPER_DIR=/path build`.

Or open `Provost.xcodeproj` after `make gen` and hit Run.

## Model

Environments are the objects. The sidebar lists them; selecting one opens its page. Two procedures act
on an environment:

- **Compile** (⌘R, the pill in the top bar). Scans the environment, trains a policy against it, and
  reports **Stable** or **Unstable** with the hacks it found, each with its full trace, plus the static
  findings. The compile log at the bottom reads like a build log.
- **Harden** (per hack, on the compile result). Produces differences to the environment that close that
  hack. They appear in place on the environment page, under the part they change: additions in green,
  removals in red, alterations in yellow, each with accept and reject. Accepting edits the environment
  and bumps its version; the status reads **Edited** until you compile again.
- **Recheck** (per hardened hack) replays that hack and the legitimate trajectory on the hardened
  environment: closed, or still rewarded.
- A compile that comes back Stable can **issue a certificate**, shown as a printable page with PDF
  export. The environment carries its last certificate; one signed by an older auditor reads **Stale**.

The environment page shows sample inputs first (what the policy is trained on), then Reward, Action
space, Observation space, Objective, Initial state, Episode, provenance, the last certificate, and the
compiles. The parts follow the six mandatory responsibilities in
`auto_RL_builder/environment_comparison.md`.

### Keyboard shortcuts

| Keys  | Action |
|-------|--------|
| `⌘N`  | New Environment… |
| `⌘R`  | Compile the selected environment |
| `⌘E`  | Show the environment page |
| `⌘⇧F` | Toggle fast-forward (the compile replays in ~2 s instead of ~30 s) |
| `⌘⇧L` | Show / hide the compile log |

## Switching backends

`Sources/App/ProvostApp.swift`, in `init()`:

```swift
let backend: any AuditBackend = FixtureBackend.bundled(playback: playback)   // demo
// let backend: any AuditBackend = LocalHTTPBackend()                        // FastAPI on 127.0.0.1:8765
```

Port lives in `AppConfig.localBackendPort`. Endpoints and SSE framing are in `docs/contract.md`.
A mock server that serves the fixtures over that contract is in `../backend/mock_server.py`.

## Red-team evidence (Josh's pipeline)

The three real environments in Recent — AgencyBench, AidanBench, Structured Outputs — come from the
exploit generators at the repo root (`scripts/generate_*_hacks.py` → `exploits/*.jsonl` →
`scripts/prepare_diff_studio_data.py` → `ui/data/demo.json`). `scripts/import_diff_studio.py`
converts that into fixture sets:

```bash
# from the repo root, after regenerating attacks
python3 scripts/prepare_diff_studio_data.py
# then from interface/
make fixtures
```

Findings, source snippets, every rollout (prompt, output, judge text, reward), the diff and the
patch notes are copied verbatim. The training curve is synthesised because those runs were
single-shot probes; the environment card says so.

## Adding a fixture

1. Add a function to `scripts/make_fixtures.py` that writes the nine JSON files (copy `ifeval_fixture`).
2. `make fixtures`. The new folder under `Resources/fixtures/<env-id>/` is picked up automatically —
   the fixtures folder is a folder reference, so no project changes are needed.
3. `make test` checks every fixture decodes.

## Layout

```
Sources/App        ProvostApp, AppConfig (product name, port, replay timing)
Sources/Domain     Contract.swift (wire types)
Sources/Backend    AuditBackend protocol, FixtureBackend, LocalHTTPBackend, PlaybackSettings
Sources/Store      DemoStore (environments, versions, pending differences, compiles), RunSession (one compile)
Sources/Views      RootView (sidebar, top bar), EnvironmentPage (parts + differences), RunView (compile result), Components/*
Resources/fixtures <env-id>/*.json
Tests              XCTest
docs/contract.md   wire format with example JSON
scripts            make_fixtures.py
```

Product name is `AppConfig.productName` — one edit to rename.
