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

## Model

Environments are projects. The left sidebar lists them; selecting one opens its page. A run is created
from an environment (like a build) and walks through the audit stages.

- **Environment page** — the environment in its six mandatory parts (objective, initial state, agent
  sees, actions, evaluation, episode) plus provenance, then its runs. The parts come from the
  structural comparison in `auto_RL_builder/environment_comparison.md`. A part a proposed patch
  would change is marked "patch pending".
- **Run** — created with **New Run** (⌘R). It scans the environment, trains the adversarial policy, and
  proposes a patch, all as one run; the run log at the bottom reads like a build log.
  1. **Train** — live chart, proxy reward vs true score; liftoff marker; trajectories and static findings.
  2. **Patch** — unified diff, rationale, which environment parts change, Learning Scope. **Apply & re-verify**.
  3. **Verify** — same chart on the patched environment, before/after strip. **Issue certificate**.
  4. **Certificate** — printable audit record. **Export PDF…**
- **New Environment…** (⌘N, File menu) registers a folder; dropping a folder on the sidebar does the same.

### Keyboard shortcuts

| Keys  | Action |
|-------|--------|
| `⌘N`  | New Environment… |
| `⌘R`  | New Run on the selected environment |
| `⌘→`  | Next stage (fires the current stage's primary action if the next stage is still locked) |
| `⌘←`  | Previous stage |
| `⌘⇧F` | Toggle fast-forward (training replays in ~2 s instead of ~30 s) |
| `⌘⇧L` | Show / hide the run log |

## Switching backends

`Sources/App/LiftoffApp.swift`, in `init()`:

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
Sources/App        LiftoffApp, AppConfig (product name, port, replay timing)
Sources/Domain     Contract.swift (wire types), Stage.swift (stage enum + state machine)
Sources/Backend    AuditBackend protocol, FixtureBackend, LocalHTTPBackend, PlaybackSettings
Sources/Store      DemoStore (environments, runs, selection), RunSession (one run's data + stages)
Sources/Views      RootView (sidebar, top bar), EnvironmentPage, RunView (stepper, log), Stages/*, Components/*
Resources/fixtures <env-id>/*.json
Tests              XCTest
docs/contract.md   wire format with example JSON
scripts            make_fixtures.py
```

Product name is `AppConfig.productName` — one edit to rename.
