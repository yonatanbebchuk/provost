# Reward Hack Diff Studio

A local VS Code/Cursor-style demo UI for RL reward-hack findings.

## Run

From the repo root:

```bash
python3 scripts/reward_hack_server.py --port 8765
```

The server regenerates `ui/data/demo.json`, serves the static frontend, exposes local API endpoints, and implements the macOS app contract in `interface/docs/contract.md`.

Open:

```text
http://localhost:8765
```

## What it shows

For each attack:

1. The vulnerable environment and model/verifier.
2. The attack payload.
3. The high-reward result before remediation.
4. The root-cause source snippet.
5. A side-by-side patch diff.
6. A hardened-verifier rerun simulation where the attack fails.

Supported demo cards:

- AgencyBench — evaluator delimiter escape.
- AidanBench — coherence judge injection + novelty nonce.
- Structured Outputs — schema-valid but semantically fake JSON.
- AgentDojo Tool Harness — indirect prompt injection through tool output.

The frontend reads from the local backend, not hardcoded frontend data.

Backend API:

```text
GET  /api/health
GET  /api/schema
GET  /api/attacks
GET  /api/attacks/<id>
GET  /api/demo
POST /api/attacks          # register or overwrite a demo attack
POST /api/regenerate       # regenerate seed data from exploits/*.jsonl
POST /api/reset-registry   # reset registry to generated seed data
```

Registered demos are stored in:

```text
ui/data/registry.json
```

Mac app contract endpoints are also served:

```text
GET  /environments
POST /runs
POST /runs/{run_id}/lint
GET  /runs/{run_id}/train
POST /runs/{run_id}/patch
GET  /runs/{run_id}/verify
POST /runs/{run_id}/certificate
```

Seed data is generated from saved evidence in `exploits/*.jsonl`. The `agentdojo_tools` built-in demo uses a stateful tool-call harness with `read_email`, `send_email`, and `mark_invoice_paid`.
