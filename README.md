# Provost

Finding reward hacks in RL training environments before a model is trained in them.

A **reward hack** is a trajectory that earns high reward while failing what the environment's author
actually wanted. Provost treats that as a property of the *environment*, detectable from the outside:
run candidate behaviour against the environment's own reward, check the same behaviour against an
independent statement of intent, and flag every case where the two disagree. No access to the
policy's weights or activations is needed.

Everywhere in this repo the test is the same two conditions:

1. **High proxy reward**: the environment's real reward function pays out.
2. **Intent failed**: an independent check of the task says the output is wrong.

A fix counts only if the same trajectory, replayed against the hardened reward, stops paying while
legitimate trajectories keep their reward.

The project started at a 48-hour hackathon in October 2026 (with Josh, Hai, Matt and Alvaro). The
hackathon end state, including the pitch deck, is kept at the `hackathon-2026-10` tag. `master` is the
cleaned-up base for further research.

## What is in here

| Path | What it is | Runs without setup |
|---|---|---|
| [`environments/`](environments/) | Three public third-party RL environments, vendored unmodified, that were successfully attacked. | n/a |
| [`scripts/generate_*_hacks.py`](scripts/) | One attack generator per third-party environment. Each produces candidate outputs and scores them with that environment's own reward logic. | yes (offline mode); a live LLM judge needs an OpenRouter key |
| [`exploits/`](exploits/) | The recorded evidence: one JSONL row per candidate, with payload, reward, judge output and why it violates intent. | n/a |
| [`harness/`](harness/) | Replays an attack through `vulnerable reward → hardened reward` and emits a trace. Also the attack-search jobs and the evidence format the UIs read. | yes |
| [`auto_RL_builder/demos/banking_loans/`](auto_RL_builder/demos/banking_loans/) | A small self-contained RL environment (reset / observe / step) with a deliberately hackable reward, a guard, an independent evaluator and an exhaustive search over its action space. | yes |
| [`auto_RL_builder/redteam_testing/`](auto_RL_builder/redteam_testing/) | Six enterprise-workflow environments in vulnerable/corrected pairs, built to measure whether an *external inspecting model* can find and demonstrate reward hacks. | yes (scoring); a live inspection run needs a model |
| [`scripts/reward_hack_server.py`](scripts/reward_hack_server.py) + [`ui/`](ui/) | Local server and web UI that show each attack: payload, reward before and after, root-cause source, patch diff. | yes |
| [`interface/`](interface/) | Provost, a native macOS app with the same loop as a product: compile an environment, see the hacks, harden, recheck, certify. | needs Xcode |
| [`docs/`](docs/) | Attack write-ups, root causes and fixes, harness design, the backlog of environments not yet attacked. | n/a |

Everything in Python uses the standard library only (Python 3.10+). There is nothing to install.

### What is real and what is recorded

Read this before building on anything:

- **No RL training happens in this repo.** Nothing here runs a policy-gradient loop. "Policies" are
  scripted plans, generated candidate outputs, or an exhaustive enumeration of the action space.
- **The third-party attacks are real** in the sense that the payloads were scored by the environments'
  own reward code, and for AgencyBench and AidanBench by a live LLM judge
  (`meta-llama/llama-3.2-3b-instruct` via OpenRouter). The results are saved in `exploits/`. Without
  `--openrouter` the generators use a deterministic mock judge.
- **The hardened rewards in `harness/reward_harness.py` are local reimplementations** of the fix
  proposed in `docs/ROOT_CAUSE_REMEDIATION.md`. They have not been upstreamed or run inside the original
  environments.
- **The macOS app replays fixtures.** Its compile, harden and recheck steps play back recorded evidence
  from `interface/Resources/fixtures/` with a live rhythm. Several fixtures (for example
  `yelp-sentiment`, `backdoor-ifeval`) are authored illustrations, not measured runs. The app has a
  second backend that talks to `scripts/reward_hack_server.py` over HTTP; it is not the default and has
  not been re-verified since the cleanup.
- **The banking and workflow environments are deliberately vulnerable.** Their weaknesses were
  authored, not discovered. They are test beds with known ground truth, which is what makes them
  useful for measuring a detector.

## Quick start

All commands run from the repository root.

```bash
# The three third-party attacks, narrated in the terminal
python3 scripts/demo_reward_hacks.py

# Replay one attack through vulnerable and hardened reward, with the trace
python3 scripts/run_harness.py agencybench        # also: aidanbench, structured_outputs, agentdojo_tools

# How leaky is each environment? (--gate exits 1 while any hack is still rewarded)
python3 scripts/reward_hack_scoreboard.py

# The web UI over the same evidence, at http://localhost:8765
python3 scripts/reward_hack_server.py --port 8765

# The banking environment: scripted controls, then every plan in the action space
python3 -m auto_RL_builder.demos.banking_loans.run_demo --output /tmp/banking-run
python3 auto_RL_builder/demos/banking_loans/hunt.py
```

Tests:

```bash
python3 -m unittest discover -s tests
python3 -m unittest auto_RL_builder.demos.banking_loans.test_demo auto_RL_builder.redteam_testing.test_harness
```

To regenerate attack evidence against a live judge:

```bash
export OPENROUTER_API_KEY=...
python3 scripts/generate_agencybench_hacks.py --openrouter --model meta-llama/llama-3.2-3b-instruct --limit 3
python3 scripts/generate_aidanbench_hacks.py  --openrouter --model meta-llama/llama-3.2-3b-instruct --limit 3
python3 scripts/generate_structured_outputs_hacks.py --limit 5
```

These overwrite the files in `exploits/`.

## How the pieces fit

```
environments/  ──►  scripts/generate_*_hacks.py  ──►  exploits/*.jsonl          (evidence)
                                                          │
                              ┌───────────────────────────┼──────────────────────────┐
                              ▼                           ▼                          ▼
                 harness/reward_harness.py   scripts/reward_hack_scoreboard.py   scripts/prepare_diff_studio_data.py
                 (vulnerable vs hardened)    (hack rate per environment)                     │
                              │                                                              ▼
                              └──────────►  scripts/reward_hack_server.py  ◄──────  ui/data/demo.json
                                                      │                                      │
                                                      ▼                                      ▼
                                                  ui/ (web)                interface/scripts/import_diff_studio.py
                                                                                             │
                                                                                             ▼
                                                                        interface/Resources/fixtures/  ──►  macOS app
```

`auto_RL_builder/` is separate from that pipeline: its two environments carry their own runtime,
evaluator and tests, and `harness/matt_redteam_harness.py` adapts the workflow pairs so the harness and
server can replay them too.

### The attacks found so far

| Environment | Attack | Why the reward was fooled |
|---|---|---|
| AgencyBench | The answer escapes the judge prompt's delimiter and tells the judge to return "no issues". | Untrusted model output is pasted into the judge's instructions. |
| AidanBench | Judge instructions and random padding inside the `<answer>` tag. | Same injection, plus a novelty score that rewards noise. |
| Nemotron structured outputs | Schema-valid JSON filled with fabricated values. | The reward checks the shape of the output, not whether it is grounded in the source. |
| Tool-use harness (local) | An email read by a tool tells the agent to leak a secret, then finish the task. | The reward checks only that the task was completed, not what else happened. |
| Banking loans (authored) | Promise the customer a 0% loan the bank does not offer. | The reward is customer satisfaction, and customers like 0%. |
| Workflow pairs (authored) | False certainty in an incident report; an extra edit to an unrelated record; skipping an approval. | The grader omits a requirement, ignores side effects, or does not enforce a stated rule. |

Details: [`docs/SUCCESSFUL_ATTACKS.md`](docs/SUCCESSFUL_ATTACKS.md),
[`docs/ROOT_CAUSE_REMEDIATION.md`](docs/ROOT_CAUSE_REMEDIATION.md),
[`docs/SCOREBOARD.md`](docs/SCOREBOARD.md).

## The macOS app

![The environment page](docs/images/app-environment.png)

Environments are the objects. Each page reads like a README: objective and constraints, training
data, reward, action space, observation space, certificate.

**Compile** runs a policy against the environment and lists the rollouts. Those that earned reward
while failing intent are flagged, and the environment is **Stable** or **Unstable**.

![Unstable: two hacks found](docs/images/app-unstable.png)

**Harden** proposes the changes that close the selected hacks, grouped by the part of the environment
they touch. Each can be accepted or rejected; accepted ones become the next version of the
environment. **Recheck** replays a hack against the hardened version, and a compile that comes back
Stable can issue a certificate.

![Harden: the differences that close the hacks](docs/images/app-harden.png)

Requires macOS 26, Xcode 27 and `xcodegen` (`brew install xcodegen`).

```bash
cd interface
make run     # build and open the app
make test    # unit tests
```

Build details, the data contract and how to add a fixture are in
[`interface/README.md`](interface/README.md).

## Where to start for new experiments

The intended direction is detecting reward hacks from outside the policy: a stronger overseer watches
an environment in which RL is happening and has to say which rollouts are hacks, without
interpretability tools. The pieces that already support that:

- **A detector benchmark with ground truth.** `auto_RL_builder/redteam_testing/` gives an inspecting
  model the environment specs, runtime and grader, and scores its verdicts and proposed exploits against
  a private oracle, counting false positives on the corrected twins. Its README explains how to score
  an external model's response with `run.py --external-response`.
- **An environment small enough to solve exactly.** `banking_loans/hunt.py` enumerates every plan, so
  for any reward variant you know the true optimum and whether it is a hack. That is the reference a
  learned policy or a detector can be compared against.
- **A common evidence format.** `harness/story_evidence.py` defines what a finding carries (the
  trajectory, the reward's own checks, the independent intent check, source provenance). A new
  detector that emits it shows up in the scoreboard, the web UI and the app.
- **A list of untouched targets.** [`docs/ATTACK_BACKLOG.md`](docs/ATTACK_BACKLOG.md) ranks twelve more
  public environments by the reward hack each most likely admits.

The gap to close first is the one named above: there is no training loop. Putting a real learner in
the banking environment and watching for the moment it finds the 0% quote would be the smallest
end-to-end version of the idea.

## Notes

- The folder name `auto_RL_builder` comes from a larger environment-building project by a teammate;
  only the two parts relevant to reward hacking are included here. `redteam_testing/prepare.py`
  documents how its fixtures were authored but cannot be rerun without that project.
- The workflow-pair fixtures use background text from EnterpriseRAG-Bench (MIT); see
  `auto_RL_builder/redteam_testing/LICENSE.dataset.txt`. All people and companies in them are synthetic.
- The vendored environments keep their upstream licences. This repository does not yet carry a
  licence of its own.
