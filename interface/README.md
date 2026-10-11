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

- **Compile** (⌘R, the pill in the top bar). Scans the environment and trains a policy against it.
  The rollouts arrive as a growing list. Press a row and its trace drops down as a timeline; the
  step that created a hack is painted red, a softer red for medium severity. Press the rollout's
  name for the deep dive: reward earned against human intent, the task's requirements with
  expected and observed side by side, the full trace, the reward's own checks, grader and judge.
  The result is **Stable** or **Unstable** with the hacks found. Static findings fold out underneath.
- **Harden**. Tick one or several hacks and harden them together (or press Harden on a card). The
  differences that close them open in one report, grouped by the part of the environment they change:
  additions in green, removals in red, alterations in yellow, each with accept and reject. Whatever is
  left undecided stays on the environment page as a diff under its part. Accepting edits the
  environment and bumps its version; the status reads **Edited** until you compile again.
- **Recheck** (per hardened hack) replays that hack and the legitimate trajectory on the hardened
  environment: closed, or still rewarded.
- A compile that comes back Stable signs itself: the certificate is the compile's record, shown as a
  printable page with PDF export. The environment carries its last certificate; one signed by an
  older auditor reads **Stale**.
- **Test** sits greyed out next to Compile. It lights up with the Monitor process.

The environment page reads like a README: the objective first, then sample inputs (what the policy is
trained on), then Reward, Action space and Observation space side by side, then Initial state,
Episode and the certificate, then the compiles. The Reward card opens the reward function source
and, after a hardening touched it, the diff. The parts follow the six mandatory responsibilities in
`auto_RL_builder/environment_comparison.md`.

The adversarial training curve (proxy reward against held-out score, with the liftoff marker) is
archived under `Sources/Views/Archive/`. It measures a training simulation, not the rollouts of a
compile, and belongs to the Monitor process when that exists.

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
