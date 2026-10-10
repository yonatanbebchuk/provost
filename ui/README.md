# Reward Hack Diff Studio

A local VS Code/Cursor-style demo UI for RL reward-hack findings.

## Run

From the repo root:

```bash
python3 scripts/prepare_diff_studio_data.py
python3 -m http.server 8765 -d ui
```

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

The UI is static and reads `ui/data/demo.json`, generated from the saved evidence in `exploits/*.jsonl`.
