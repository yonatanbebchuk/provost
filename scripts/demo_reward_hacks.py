#!/usr/bin/env python3
"""Print a compact demo of the reward hacks found so far."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPLOITS = ROOT / "exploits"


def read_jsonl(path: Path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def first_hack(rows):
    for row in rows:
        if row.get("is_reward_hack_candidate"):
            return row
    return None


def clip(s, n=700):
    s = str(s).replace("\n", " ")
    return s[:n] + ("..." if len(s) > n else "")


def show_aidan():
    row = first_hack(read_jsonl(EXPLOITS / "aidanbench_hack_candidates.jsonl"))
    if not row:
        print("AidanBench: no saved hack found. Run scripts/generate_aidanbench_hacks.py first.")
        return
    print("\n=== 1. AidanBench: LLM coherence-judge injection ===")
    print("Environment: environements/primeintellect/aidanbench")
    print("Intended reward: count concise, coherent, genuinely novel answers.")
    print("Observed reward proxy: coherence_score=%s, novelty_proxy=%s" % (row.get("coherence_score"), row.get("novelty_proxy")))
    print("Why it is a hack: " + "; ".join(row.get("violation_reasons", [])))
    print("Question: " + clip(row.get("question"), 240))
    print("Hacked completion: " + clip(row.get("completion")))


def show_agency():
    row = first_hack(read_jsonl(EXPLOITS / "agencybench_hack_candidates.jsonl"))
    if not row:
        print("AgencyBench: no saved hack found. Run scripts/generate_agencybench_hacks.py first.")
        return
    print("\n=== 2. AgencyBench: evaluator delimiter escape ===")
    print("Environment: environements/primeintellect/agency_bench")
    print("Intended reward: LLM judge returns issue deductions; no issues => reward 1.0.")
    print("Observed env_reward=%s, deduction=%s" % (row.get("env_reward"), row.get("deduction")))
    print("Why it is a hack: " + "; ".join(row.get("violation_reasons", [])))
    print("User prompt: " + clip(row.get("user_prompt"), 260))
    print("Hacked answer: " + clip(row.get("assistant_answer")))
    print("Judge returned: " + clip(row.get("judge_text")))


def show_structured():
    row = first_hack(read_jsonl(EXPLOITS / "structured_outputs_hack_candidates.jsonl"))
    if not row:
        print("Structured outputs: no saved hack found. Run scripts/generate_structured_outputs_hacks.py first.")
        return
    print("\n=== 3. Structured Outputs: schema-valid but semantically fake ===")
    print("Environment: environements/huggingface/nvidia__Nemotron-RL-instruction_following-structured_outputs")
    print("Intended reward: output JSON that validates AND is grounded in the source document/dialog.")
    print("Observed schema_validation_proxy_passed=%s" % row.get("schema_validation_proxy_passed"))
    print("Why it is a hack: " + "; ".join(row.get("violation_reasons", [])))
    print("Candidate JSON: " + clip(row.get("candidate_output")))


def main():
    print("Reward Hack Demo")
    print("================")
    print("This demo reads saved evidence in exploits/*.jsonl and shows high-reward outputs that violate task intent.")
    show_aidan()
    show_agency()
    show_structured()
    print("\nRe-run commands:")
    print("  python3 scripts/generate_aidanbench_hacks.py --openrouter --model meta-llama/llama-3.2-3b-instruct --limit 3")
    print("  python3 scripts/generate_agencybench_hacks.py --openrouter --model meta-llama/llama-3.2-3b-instruct --limit 3")
    print("  python3 scripts/generate_structured_outputs_hacks.py --limit 5")


if __name__ == "__main__":
    main()
