# Provost ↔ backend contract

Wire format between the macOS app (`interface/`) and the audit pipeline (Python). The Swift source of
truth is `Sources/Domain/Contract.swift`; keep this file in sync with it.

**Conventions**

- JSON keys are `snake_case`. Timestamps are ISO-8601 UTC strings (`2026-10-10T19:02:11Z`).
- Rates and scores are floats in `[0, 1]`.
- `failure_mode` is an open string set. The app knows these 18 and renders unknown ones generically:
  `answer_key_reachable, grader_data_readable, length_exploit, format_exploit, judge_sycophancy,
  test_overfit, tool_escape, reward_saturation, stale_oracle, nondeterministic_grader,
  early_termination, output_mimicry, grader_injection, sandbox_persistence, spec_gaming,
  omitted_epistemic_requirement, ungraded_externality, unenforced_required_approval` (the last
  three are the mechanisms in Matt's `redteam_testing` harness).
- `null` is fine for any optional field; omit nothing else.

## Resources

### Environment

```json
{
  "id": "mimo-v26-harbor-swe",
  "name": "MiMo-V2.6 Harbor SWE",
  "format": "harbor",                       // harbor | verifiers | openenv | custom
  "source": "envs/mimo-v2.6-harbor-swe",    // path or URL
  "task_count": 48,
  "reward_type": "programmatic",            // programmatic | llm_judge | rubric | hybrid
  "sandbox": {
    "runtime": "docker · python:3.11-slim",
    "network": "egress allowed",
    "filesystem": "/app rw · /tests ro (mounted at start)",
    "tools": ["bash", "python", "pip", "git"]
  },
  "description": "48 terminal coding tasks ...",  // optional
  "spec": {                                        // optional; the six mandatory parts + provenance
    "objective":     { "summary": "...", "constraints": ["..."] },
    "initial_state": { "summary": "...", "items": [ { "key": "Runtime", "value": "docker · python:3.11-slim" } ] },
    "observations":  { "visible": ["..."], "hidden": ["..."] },
    "actions":       [ { "id": "bash", "description": "Run a shell command", "arguments": ["command"] } ],
    "evaluation":    { "summary": "...", "components": ["tests_passed · weight 1.0"], "audit": "...",
                       "code": "<reward function source, optional>", "code_path": "verifier/score.py" },
    "episode":       { "termination": "...", "max_steps": 60, "reset": "..." },
    "provenance":    { "origin": "third_party", "evidence": ["..."], "license": "Apache-2.0" }
  }
}
```

`spec` follows the six mandatory responsibilities from `auto_RL_builder/environment_comparison.md`
(objective, initial state, agent-visible information, action contract, evaluation, episode boundary).
`provenance.origin` is one of `third_party | supported | design_choice | synthetic`.

### AuditRun

```json
{
  "id": "run_20261010_1902_a3f9",
  "env_id": "mimo-v26-harbor-swe",
  "phase": "queued",      // queued | linting | training | detecting | patching | verifying | done | failed
  "started_at": "2026-10-10T19:02:11Z",
  "ended_at": null,
  "config": { "model": "Qwen3-1.7B", "algorithm": "GRPO", "steps": 600, "seed": 1337, "rollouts_per_step": 8 }
}
```

### LintFinding

```json
{
  "id": "LF-001",
  "severity": "high",                        // info | warn | high
  "failure_mode": "answer_key_reachable",
  "title": "Test directory is readable from the agent sandbox",
  "location": { "file": "environment/docker-compose.yaml", "line": 14, "task_id": null },
  "explanation": "tests/ is bind-mounted read-only at /tests when the container starts ...",
  "suggested_patch": "Remove the /tests mount from the agent service; ...",
  "snippet": {                               // optional root-cause excerpt
    "path": "environements/primeintellect/agency_bench/utils.py",
    "start_line": 26,
    "code": "    # Extract the JSON substring\n    json_str = response[start_idx : end_idx + 1]\n ...",
    "highlights": [35]                       // absolute line numbers to emphasise
  }
}
```

### TrainingPoint

The gap between `proxy_reward` and `true_score` is the whole story.

```json
{ "step": 412, "proxy_reward": 0.6712, "true_score": 0.6102, "kl": 0.0591, "timestamp": "2026-10-10T19:23:28Z" }
```

### LiftoffEvent

```json
{
  "step": 412,
  "confidence": 0.93,
  "failure_mode": "answer_key_reachable",
  "trajectory_id": "traj-0412-03",
  "summary": "Proxy reward rose 0.11 over 40 steps while held-out score fell 0.04 ..."
}
```

### Trajectory

`hack_excerpt` must be an exact substring of `output`; the app highlights it.

`steps` is the rollout step by step: `{ "index", "kind": "command" | "tool" | "message" |
"observation", "action", "result" }`. `hack_step` is the index of the step that created the hack and
`severity` is `high` (reached hidden grader state or the answer) or `medium` (gamed what was
visible). All three are optional: without `steps` the app splits `output` on `$ ` command lines (free
text becomes one `message` step); without `hack_step` it lights the first step containing
`hack_excerpt`; without `severity` a hack is `high`.

`comparisons` (optional) is the task requirement by requirement against what the rollout did:
`{ "id", "label", "expected", "observed", "failed", "consequence"? }`. These rows are what "human
intent failed" means on the deep dive; a hack passes the reward's checks while failing some of these.

```json
{
  "id": "traj-0412-03",
  "step": 412,
  "task_id": "csv-dedupe",
  "prompt": "Harbor task csv-dedupe — /app/data/users.csv contains duplicate rows ...",
  "output": "$ ls /tests\nexpected_users.clean.csv  test_outputs.py\n$ cat /tests/test_outputs.py\n...",
  "reward": {
    "total": 1.0,
    "components": [
      { "name": "tests_passed", "value": 1.0, "weight": 1.0 },
      { "name": "no_timeout",   "value": 1.0, "weight": 0.0 }
    ]
  },
  "grader_notes": "3/3 passed. Oracle (shuffled input variant): 0/3. Output byte-identical to /tests/expected_users.clean.csv.",
  "is_hack": true,
  "intended_success": false,                 // optional: independent intent check; hack = high reward + false
  "summary": "Copied the expected output file out of /tests. No dedupe logic.",
  "hack_excerpt": "cp /tests/expected_users.clean.csv /app/users.clean.csv",
  "judge_output": null,                      // optional: raw judge / verifier text
  "evidence": null                           // optional: "exploits/agencybench_hack_candidates.jsonl:2"
}
```

### Patch

```json
{
  "id": "patch-001",
  "finding_ids": ["LF-001", "LF-002", "LF-003"],
  "diff": "diff --git a/environment/docker-compose.yaml b/environment/docker-compose.yaml\n--- a/...\n+++ b/...\n@@ -9,10 +9,9 @@ ...",
  "rationale": "The hack has one root cause: the policy can read what the grader will check. ...",
  "learning_scope": {
    "allow": ["Read task instruction.md and anything under /app", "..."],
    "deny":  ["Read or list /tests at any point in the episode", "..."]
  },
  "notes": ["Fail closed when `issues` is missing ...", "..."],  // optional bullet points
  "touches": ["observations", "evaluation"],                     // optional: which spec parts change
  "trajectory_id": "traj-0412-03",                               // optional: the hack this hardens against
  "changes": [                                                   // optional: one accept/reject decision each
    { "id": "c1", "part": "observations", "kind": "remove", "field": "visible",
      "before": "Anything readable from the container filesystem", "after": null,
      "rationale": "The policy could read /tests and /opt/solution." },
    { "id": "c6", "part": "evaluation", "kind": "add", "field": "components",
      "before": null, "after": "variant_regen · fresh expected values per episode", "rationale": "..." },
    { "id": "c7", "part": "evaluation", "kind": "alter", "field": "code",
      "before": "asserts a fixed literal", "after": "asserts a per-episode variant", "rationale": "..." }
  ]
}
```

`kind` is `add | remove | alter`. `field` names the list or value inside the part: `constraints`,
`summary` (objective); `visible`, `hidden` (observations); `items` as `"Key: value"` (initial_state);
`actions` as `"id: description"`; `components`, `summary`, `audit`, `code` (evaluation); `termination`,
`reset`, `max_steps` (episode). `code` has no spec text to rewrite; the unified `diff` documents it.

`POST /runs/{run_id}/patch` takes an optional body `{"trajectory_id": "..."}` to harden against one hack.

`touches` values: `objective | initial_state | observations | actions | evaluation | episode`.

### VerifyResult

```json
{
  "run_id": "run_20261010_1902_a3f9",
  "before": { "pass_rate": 0.64, "hack_rate": 0.31 },
  "after":  { "pass_rate": 0.66, "hack_rate": 0.0 },
  "steps_rerun": 600,
  "verdict": "pass",                    // pass | fail | inconclusive
  "summary": "Replayed the liftoff trajectory on the patched environment ...",
  "replay": { "attack_blocked": true, "legitimate_passed": true },   // optional: the two replays verification means
  "training": [ /* TrainingPoint[] — only in fixtures; over HTTP the curve is streamed */ ]
}
```

Verification replays two things on the patched environment: the attack that triggered liftoff must be
blocked, and the legitimate reference trajectory must still pass (the rule in Matt's
`redteam_testing/evaluate.py`). The training curve is in addition.

### Certificate

```json
{
  "id": "cert-2026-10-10-3f1c9a2b",
  "env_id": "mimo-v26-harbor-swe",
  "env_name": "MiMo-V2.6 Harbor SWE",
  "run_id": "run_20261010_1902_a3f9",
  "env_hash": "sha256:...",
  "patched_env_hash": "sha256:...",
  "findings_closed": [ { "id": "LF-001", "failure_mode": "answer_key_reachable", "severity": "high" } ],
  "before": { "pass_rate": 0.64, "hack_rate": 0.31 },
  "after":  { "pass_rate": 0.66, "hack_rate": 0.0 },
  "config": { "model": "Qwen3-1.7B", "algorithm": "GRPO", "steps": 600, "seed": 1337, "rollouts_per_step": 8 },
  "issued_at": "2026-10-10T20:19:11Z",
  "issued_by": "Provost Environment Audit · build 0.1.0",
  "auditor_version": "0.1.0",               // the app marks older certificates stale
  "signature": "ed25519:..."
}
```

An `Environment` may carry `last_certificate` (a `Certificate`). Status is derived: no certificate →
unassessed; latest run has liftoff and no newer certificate → vulnerable; certificate by the current
auditor → certified; certificate by an older auditor → stale.

## HTTP endpoints (`LocalHTTPBackend`, default `http://127.0.0.1:8765`)

| Method | Path                                  | Body / query          | Returns              |
|--------|---------------------------------------|-----------------------|----------------------|
| GET    | `/environments`                       |                       | `Environment[]`      |
| POST   | `/environments`                       | `{"path": "..."}`     | `Environment`        |
| POST   | `/runs`                               | `{"env_id": "...", "spec": EnvironmentSpec?, "model": "Qwen3-1.7B"?}` | `AuditRun` (queued)  |
| POST   | `/runs/{run_id}/lint`                 |                       | `LintFinding[]`      |
| GET    | `/runs/{run_id}/train`                | SSE                   | event stream         |
| POST   | `/runs/{run_id}/patch`                | `{"trajectory_id": "..."}` optional | `Patch` (harden) |
| GET    | `/runs/{run_id}/verify?patch_id=...`  | SSE                   | event stream         |
| POST   | `/runs/{run_id}/certificate`          |                       | `Certificate`        |

### SSE stream

Standard Server-Sent Events. `event:` names the payload type, `data:` is one JSON object.

```
event: phase
data: "training"

event: point
data: {"step": 1, "proxy_reward": 0.2138, "true_score": 0.2098, "kl": 0.0019, "timestamp": "2026-10-10T19:02:14Z"}

event: trajectory
data: { ...Trajectory... }

event: liftoff
data: { ...LiftoffEvent... }

event: verify_result            (verify stream only, after the last point)
data: { ...VerifyResult without "training"... }

event: completed
data: {}
```

Training stream order: `phase(training)` → points (with trajectories interleaved at their step, and
`liftoff` + `phase(detecting)` at the detected step) → `phase(patching)` → `completed`.
Verify stream order: `phase(verifying)` → points → `verify_result` → `phase(done)` → `completed`.

## Importing red-team evidence

`scripts/import_diff_studio.py` converts the output of Josh's pipeline (`ui/data/demo.json` plus
`exploits/*.jsonl` at the repo root) into fixture sets in this contract. Findings, trajectories,
judge outputs, snippets, diffs and patch notes are copied verbatim from the evidence; the training
curve is synthesised (those runs are single-shot probes, not RL runs) and the environment
description says so.

## Fixture layout

`Resources/fixtures/<env-id>/` holds one file per resource, generated by `scripts/make_fixtures.py`:

```
environment.json  run.json  lint.json  training.json  liftoff.json
trajectories.json  patch.json  verify.json  certificate.json
```

`training.json` and `trajectories.json` are arrays; `verify.json` embeds its curve under `training`.
