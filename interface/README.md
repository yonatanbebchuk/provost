# Provost · macOS demo app

Native SwiftUI front-end for the RL environment audit service. Runs the whole demo on bundled fixture
data; swaps to the Python backend with one line.

## Build & run

Requirements: macOS 26, Xcode 27, `brew install xcodegen`.

```bash
make run      # xcodegen + xcodebuild Debug + open the .app
make pitch    # build and open in Pitch Mode on slide 1 (⌘R re-reads the source deck.json)
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
  environment; the decision joins the **change record** (the pill in the top bar). **Save** (⌘S)
  writes the record into the next version. Until then the status reads **Edited**; after a save the
  new version reads **Unassessed** until it is compiled. Compile saves first if anything is unsaved.
- **Recheck** (per hardened hack) replays that hack and the legitimate trajectory on the hardened
  environment: closed, or still rewarded.
- A compile that comes back Stable offers **Issue certificate** at the bottom; the certificate is
  shown as a printable page with PDF export. The environment carries its last certificate; one signed by an
  older auditor reads **Stale**.
- **Run** is one menu in the top bar: Compile now, Test greyed out until the Monitor process exists.
  The top bar also carries the environment name, its version tag, its status tag, the change
  record and Save, and the policy menu.
- The **policy menu** in the top bar picks which model the next compile trains. Open: Qwen,
  Llama. Custom: Provost Secure. The catalog lives in `AppConfig.policyModels`; the compile
  carries the choice in its config and the sidebar, top bar and compiles list show it. The fixture
  replays the same evidence whichever policy is chosen.

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
| `⌘⇧P` | Pitch mode on / off (see Pitch Mode) |

## Pitch Mode

The pitch deck lives inside the app: a third top-level mode of the main window (⌘⇧P, or View ▸
Pitch; `make pitch` launches straight into it with `--pitch`). The deck is data:
`Resources/pitch/deck.json` holds the ten slides (eyebrow, title, subtitle, visual, script, budget).
Edit titles, scripts and budgets there; `make pitch` points the app at the source file so ⌘R in
pitch mode re-reads it without a rebuild. A slide with `"reveal": "step"` builds one piece per `→`
(each tick of a timeline, the chart) before the next slide; `←` un-reveals. Faces on the opening
slide are small round photos beside each name: drop a photo into `Resources/pitch/faces/` and name
it in the person's `image` field, or set their `github` handle and run `make faces` to bundle the
avatar; a person with neither shows initials. Every slide is title-only; the script shows only in the
presenter panel (`P`). Visuals replay each time the slide appears; Reduce Motion jumps to the end.

Slide 6 is the demo. `→` on it shows the app as it stands; the presenter drives it by hand (the
`yelp-sentiment` fixture is the one made for the story: compile, open the step-412 rollout, Harden,
Recheck — the Verify tab shows the re-run and the before/after rates from the fixture). No key is
intercepted while the app is up. **Continue pitch →** in the top bar lands on slide 7; ⌘⇧P returns
to slide 6. The Provost logo (sidebar or pitch top bar) and **Present** start a fresh presentation
from slide 1 with the clocks at zero.

| Key | Pitch mode |
|-----|-----------|
| `→` / `PageDown` / click right half | next slide; on slide 6 enters the demo |
| `←` / `PageUp` / click left half | previous slide |
| `Esc` | Exit to app (**Resume pitch →** in the top bar) |
| `P` | presenter panel: script, slide clock, pitch total |
| `Space` | start / pause the slide clock |
| `⌘R` | reload deck.json |
| `⌘⇧P` | leave pitch mode (plain app); from the demo, back to slide 6 |

Keys are handled at the window level (an `NSEvent` local monitor) only while slides show, so
nothing needs focus and the app keeps every key during the demo.
Rehearsal aid: `--snapshot-dir <dir>` sizes the window to 1280 × 800 and polls `<dir>/cmd` for
`key right`, `snap <label>`, `dark`, `light` …, writing PNGs and an `events.log` there.

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
