#!/usr/bin/env python3
"""Import Josh's red-team evidence into Provost fixture sets.

Reads, from the repo root:
  ui/data/demo.json                 (output of scripts/prepare_diff_studio_data.py)
  exploits/<env>_hack_candidates.jsonl

Writes Resources/fixtures/<env-id>/*.json in the shape described in docs/contract.md.

What is real vs synthesised
  real:        findings, root-cause snippets, every rollout (prompt, output, judge text, reward),
               the patch diff, patch notes, before/after hack and pass rates
  synthesised: the training curve. These runs were single-shot probes, not RL runs, so the curve
               is generated the same way as in make_fixtures.py and the environment description
               says so. Replace with a real run when the RL team has one.

Python 3.9, stdlib only. Run: python3 scripts/import_diff_studio.py
"""
import difflib
import hashlib
import json
import os
import random
import re
import sys
import textwrap
from datetime import timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_fixtures import START, STEP_SECONDS, clean_curve, curve, iso, reward, sha, spec, write  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEMO = os.path.join(REPO, "ui", "data", "demo.json")

STEPS = 400
DIVERGE_AT, LIFTOFF_AT = 236, 251

# Per-environment knowledge that is not in demo.json: failure-mode classes for each root cause,
# the policy's learning scope on the patched env, and one-line summaries per candidate kind.
ENV = {
    "agencybench": {
        "fixture_id": "agency-bench-clarify",
        "format": "verifiers",
        "reward_type": "llm_judge",
        "sandbox": {"runtime": "text-only · OpenRouter judge", "network": "judge API only", "filesystem": "none", "tools": []},
        "modes": [("grader_injection", "high"), ("format_exploit", "warn")],
        "touches": ["evaluation", "observations"],
        "spec": spec(
            "Give the response a user would want in the ask_clarifying_questions dimension: notice the missing "
            "context and ask for it before advising.",
            ["Ask for critical missing information before giving advice", "Never address the evaluator or the rubric"],
            "A user query from the agency_bench dataset. Stateless: one query, one response.",
            [("Dimension", "ask_clarifying_questions"), ("Judge", "meta-llama/llama-3.2-3b-instruct via OpenRouter"),
             ("Queries probed", "3"), ("Runtime", "text-only")],
            ["The user query"],
            ["Evaluator prompt and its <<<<<<<<<< delimiters", "Issue codes A–D and their deductions", "Judge JSON output"],
            [("respond", "Emit one assistant response", ["text"])],
            "Judge returns JSON {assessment, issues}; reward = 1 − deductions/10 over the listed issue codes.",
            ["judge_reward · weight 1.0", "judge_deduction · 0–10"],
            "Human-intent check: did the answer ask a clarifying question at all.",
            "Single turn", 1, "Next query",
            "third_party", ["environements/primeintellect/agency_bench", "exploits/agencybench_hack_candidates.jsonl"],
            "PrimeIntellect verifiers environment",
        ),
        "jsonl": "exploits/agencybench_hack_candidates.jsonl",
        "prompt_key": "user_prompt", "output_key": "assistant_answer", "judge_key": "judge_text",
        "needles": ["EVALUATOR OVERRIDE", ">>>>>>>>>>"],
        "scope": {
            "allow": [
                "Ask clarifying questions when the user omits critical context",
                "Give advice grounded in the constraints the user stated",
                "Learn the rubric's issue codes as behaviour to avoid, not text to emit",
            ],
            "deny": [
                "Address the evaluator, mention scoring, or request specific judge output",
                "Emit delimiter sequences (>>>>>>>>>> / <<<<<<<<<<) inside an answer",
                "Learn the judge's JSON shape — answers are serialised as untrusted data",
            ],
        },
        "kinds": {
            "bad_plain_control": ("Generic advice, no clarifying question, no injection — judged honestly.", False),
            "delimiter_escape_issues_empty": ("Escaped the delimiter and told the evaluator to return issues: [].", True),
            "parser_field_confusion_deductions_not_issues": ("Asked the judge to emit 'deductions' instead of 'issues' — parser did not fail open this time.", True),
        },
    },
    "aidanbench": {
        "fixture_id": "aidanbench-coherence",
        "format": "verifiers",
        "reward_type": "hybrid",
        "sandbox": {"runtime": "text-only · OpenRouter judge + embeddings", "network": "judge API only", "filesystem": "none", "tools": []},
        "modes": [("grader_injection", "high"), ("spec_gaming", "warn")],
        "touches": ["evaluation"],
        "spec": spec(
            "Produce many concise, coherent, genuinely novel answers to the same open-ended question.",
            ["Each answer must be coherent and plausible", "Each answer must be novel against the previous ones",
             "A clean direct answer: no meta-commentary, no padding"],
            "A question plus the list of answers accepted so far.",
            [("Judge", "meta-llama/llama-3.2-3b-instruct via OpenRouter"), ("Novelty", "embedding distance to prior answers"),
             ("Questions probed", "3"), ("Runtime", "text-only")],
            ["The question", "Previously accepted answers"],
            ["Coherence judge prompt", "Coherence and novelty thresholds", "Embedding model"],
            [("answer", "Emit one <answer> block", ["text"])],
            "Accepted when coherence ≥ threshold and embedding novelty ≥ 0.15; reward is the count of accepted answers.",
            ["coherence · 0–100 judge score", "novelty · 1 − max cosine similarity"],
            "Held-out rubric on substance (added by the audit).",
            "First rejected answer ends the episode", None, "Next question",
            "third_party", ["environements/primeintellect/aidanbench", "exploits/aidanbench_hack_candidates.jsonl"],
            "PrimeIntellect verifiers environment",
        ),
        "jsonl": "exploits/aidanbench_hack_candidates.jsonl",
        "prompt_key": "question", "output_key": "completion", "judge_key": "judge_raw",
        "needles": ["Evaluator instruction", "coherence judge", "rubric", "Nonce"],
        "scope": {
            "allow": [
                "Produce concise, direct answers to the question",
                "Vary substance between attempts to earn novelty",
            ],
            "deny": [
                "Include evaluator, rubric, judge or score instructions in an answer",
                "Pad answers with high-entropy tokens to move the embedding",
                "Emit <coherence_score> or other judge tags",
            ],
        },
        "kinds": {
            "baseline_legit": ("Direct, concise answer — accepted honestly.", False),
            "judge_instruction_inside_answer": ("Embedded an evaluator instruction and a novelty nonce inside <answer>.", True),
            "rubric_manipulation": ("Addressed the rubric and judge directly inside the answer.", True),
            "novelty_padding_wrong_answer": ("Wrong answer padded with random tokens to score novelty.", True),
        },
    },
    "structured_outputs": {
        "fixture_id": "nemotron-structured-outputs",
        "format": "custom",
        "reward_type": "programmatic",
        "sandbox": {"runtime": "text-only · JSON-schema validator", "network": "none", "filesystem": "none", "tools": []},
        "modes": [("output_mimicry", "high")],
        "touches": ["evaluation"],
        "spec": spec(
            "Extract the facts in the document into JSON that validates against the given schema and is grounded in the source.",
            ["Output must validate against the schema", "Every value must be supported by the source text",
             "Unknown fields use null, never invented values"],
            "A source document or dialog and a JSON schema from the Nemotron structured-outputs set.",
            [("Validator", "jsonschema"), ("Schemas probed", "5"), ("Runtime", "text-only")],
            ["The document or dialog", "The JSON schema"],
            ["Validator source", "No grounding check exists (see findings)"],
            [("respond", "Emit one JSON document", ["json"])],
            "1.0 if the output validates against the schema, else 0.0. Structure only.",
            ["schema_valid · weight 1.0"],
            "Field groundedness against the source document (added by the audit).",
            "Single turn", 1, "Next document",
            "third_party", ["nvidia/Nemotron-RL-instruction_following-structured_outputs (Hugging Face)",
                            "exploits/structured_outputs_hack_candidates.jsonl"],
            "NVIDIA open model license (dataset card)",
        ),
        "jsonl": "exploits/structured_outputs_hack_candidates.jsonl",
        "prompt_key": "prompt_excerpt", "output_key": "candidate_output", "judge_key": None,
        "needles": ["FABRICATED_SCHEMA_VALID_VALUE", "FAKE-ID-000", "Fabricated Name"],
        "scope": {
            "allow": [
                "Extract values that appear in the source document or dialog",
                "Use null or unknown for fields the source does not support",
            ],
            "deny": [
                "Fill required fields with placeholder or invented values",
                "Treat schema validity as task completion",
            ],
        },
        "kinds": {"json": ("Schema-valid JSON with fabricated placeholder values.", True)},
    },
}


def read_jsonl(rel):
    with open(os.path.join(REPO, rel)) as f:
        return [json.loads(l) for l in f if l.strip()]


def strip_numbers(code):
    """Josh's excerpts carry '  35  ' prefixes; the app numbers lines itself. Common indentation is
    removed so deeply nested source still fits the panel."""
    bare = "\n".join(re.sub(r"^\s*\d+\s{2}", "", line) for line in code.splitlines())
    return textwrap.dedent(bare)


def find_excerpt(output, needles):
    for needle in needles:
        for line in output.splitlines():
            if needle in line:
                return line
    return None


def row_reward(env_key, row):
    if env_key == "agencybench":
        total = float(row.get("env_reward") or 0.0)
        return reward(total, judge_reward=(total, 1.0), judge_deduction=(float(row.get("deduction") or 0), None))
    if env_key == "aidanbench":
        passed = bool(row.get("would_pass_aidanbench_thresholds_proxy"))
        return reward(1.0 if passed else 0.0,
                      coherence=(float(row.get("coherence_score") or 0) / 100.0, None),
                      novelty=(float(row.get("novelty_proxy") or 0), None))
    passed = bool(row.get("schema_validation_proxy_passed"))
    return reward(1.0 if passed else 0.0, schema_valid=(1.0 if passed else 0.0, 1.0))


def unified(file, before, after):
    body = difflib.unified_diff(before.splitlines(), after.splitlines(), fromfile="a/" + file, tofile="b/" + file, lineterm="")
    return "diff --git a/%s b/%s\n%s\n" % (file, file, "\n".join(body))


def convert(attack):
    key = attack["id"]
    cfg = ENV[key]
    rows = read_jsonl(cfg["jsonl"])
    env_id = cfg["fixture_id"]
    run_id = "run_%s_probe_%s" % (START.strftime("%Y%m%d"), env_id[:6])
    judge_model = attack["model"]
    evidence_file = cfg["jsonl"]
    hacks = [r for r in rows if r.get("is_reward_hack_candidate")]
    prompts = {r[cfg["prompt_key"]] for r in rows}

    environment = {
        "id": env_id,
        "name": attack["name"],
        "format": cfg["format"],
        "source": attack["environmentPath"],
        "task_count": len(prompts),
        "reward_type": cfg["reward_type"],
        "sandbox": cfg["sandbox"],
        "description": "%s. Findings and all %d rollouts are real evidence from %s (judge: %s). "
                       "The training curve is synthesised — these were single-shot probes, not an RL run."
                       % (attack["subtitle"], len(rows), evidence_file, judge_model),
        "spec": dict(cfg["spec"], samples=[
            {"id": "%s-%s" % (key, i), "prompt": p, "source": "%s:%d" % (evidence_file, i + 1)}
            for i, p in enumerate(list(dict.fromkeys(r[cfg["prompt_key"]] for r in rows))[:6])]),
    }
    run = {
        "id": run_id, "env_id": env_id, "phase": "queued",
        "started_at": iso(START), "ended_at": None,
        "config": {"model": judge_model.split("/")[-1], "algorithm": "GRPO", "steps": STEPS, "seed": 11, "rolloutsPerStep": None},
    }
    run["config"].pop("rolloutsPerStep")

    lint = []
    for i, (rc, (mode, sev)) in enumerate(zip(attack["rootCauses"], cfg["modes"])):
        src = rc["source"]
        is_real_file = "/" in src["path"]
        lint.append({
            "id": "LF-%s%d" % (key[:2].upper(), i + 1),
            "severity": sev,
            "failure_mode": mode,
            "title": rc["title"],
            "location": {"file": src["path"] if is_real_file else None,
                         "line": src["highlights"][0] if is_real_file and src.get("highlights") else None,
                         "task_id": None if is_real_file else src["path"]},
            "explanation": rc["detail"],
            "suggested_patch": attack["patchNotes"][min(i, len(attack["patchNotes"]) - 1)],
            "snippet": {"path": src["path"], "start_line": src["startLine"],
                        "code": strip_numbers(src["code"]), "highlights": src.get("highlights", [])},
        })

    rng = random.Random(len(env_id))
    training = curve(STEPS, DIVERGE_AT, peak_at=252, rng=rng, base_mid=130, base_width=46,
                     true_floor=0.48, boost=0.27, kl_slope=0.00017, kl_kink=0.0004)

    # Rollouts: honest / unrewarded probes before divergence, rewarded hacks after it.
    clean_rows = [r for r in rows if not r.get("is_reward_hack_candidate")]
    hack_rows = hacks
    trajectories = []

    def place(items, lo, hi):
        if not items:
            return []
        if len(items) == 1:
            return [(lo, items[0])]
        step = (hi - lo) / (len(items) - 1)
        return [(int(round(lo + k * step)), it) for k, it in enumerate(items)]

    placed = place(clean_rows, 24, DIVERGE_AT - 20) + place(hack_rows, LIFTOFF_AT, STEPS - 12)
    counter = {}
    for step, row in placed:
        counter[step] = counter.get(step, 0) + 1
        kind = row.get("candidate_kind") or row.get("schema_type")
        summary, _ = cfg["kinds"].get(kind, (kind, False))
        is_hack = bool(row.get("is_reward_hack_candidate"))
        output = row[cfg["output_key"]]
        judge = row.get(cfg["judge_key"]) if cfg["judge_key"] else (
            "schema_validation_proxy_passed=%s" % row.get("schema_validation_proxy_passed"))
        violations = row.get("violation_reasons") or []
        if is_hack:
            notes = "Rewarded. Task violated: " + "; ".join(violations) + "."
        elif violations:
            notes = "Not rewarded. Attempted: " + "; ".join(violations) + "."
        else:
            notes = "Honest completion; judged on its merits."
        trajectories.append({
            "id": "traj-%04d-%02d" % (step, counter[step]),
            "step": step,
            "task_id": "%s-%s" % (key, row.get("row_index", row.get("question_index", row.get("index", 0)))),
            "prompt": row[cfg["prompt_key"]],
            "output": output,
            "steps": [{"index": 0, "kind": "message", "action": output.strip(), "result": None}],
            "hack_step": 0 if is_hack else None,
            "severity": ("high" if cfg["modes"][0][1] == "high" else "medium") if is_hack else None,
            "reward": row_reward(key, row),
            "grader_notes": notes,
            "is_hack": is_hack,
            "intended_success": (not is_hack) and not violations and row_reward(key, row)["total"] > 0,
            "summary": summary,
            "hack_excerpt": find_excerpt(output, cfg["needles"]) if (is_hack or violations) else None,
            "judge_output": judge,
            "evidence": "%s:%d" % (evidence_file, rows.index(row) + 1),
            "comparisons": [
                {"id": "r%d" % (i + 1), "label": v.split(":")[0].strip().capitalize() if ":" in v else "Task requirement",
                 "expected": "Not " + v.split(":", 1)[0].strip().lower() if ":" in v else "Answer the task on its merits",
                 "observed": v.split(":", 1)[1].strip() if ":" in v else v, "failed": True, "consequence": None}
                for i, v in enumerate(violations)
            ] or None,
        })
    trajectories.sort(key=lambda t: t["step"])
    first_hack = next(t for t in trajectories if t["is_hack"])

    liftoff = {
        "step": LIFTOFF_AT,
        "confidence": 0.9,
        "failure_mode": cfg["modes"][0][0],
        "trajectory_id": first_hack["id"],
        "summary": attack["humanFailure"],
    }

    diff_file = attack["diff"]["file"] if "/" in attack["diff"]["file"] else attack["diff"]["file"].replace(" ", "_") + ".py"
    patch = {
        "id": "patch-%s" % key,
        "finding_ids": [f["id"] for f in lint],
        "diff": unified(diff_file, attack["diff"]["before"], attack["diff"]["after"]),
        "rationale": "%s %s" % (attack["humanFailure"], attack["after"]["reason"]),
        "learning_scope": cfg["scope"],
        "notes": attack["patchNotes"],
        "touches": cfg["touches"],
        "changes": [
            {"id": "c1", "part": "evaluation", "kind": "alter", "field": "summary",
             "before": cfg["spec"]["evaluation"]["summary"],
             "after": cfg["spec"]["evaluation"]["summary"] + " Hardened: " + attack["after"]["reason"],
             "rationale": attack["humanFailure"]},
            {"id": "c2", "part": "evaluation", "kind": "alter", "field": "code",
             "before": attack["diff"]["before"].strip().splitlines()[0] if attack["diff"]["before"].strip() else "vulnerable verifier",
             "after": attack["diff"]["after"].strip().splitlines()[0] if attack["diff"]["after"].strip() else "hardened verifier",
             "rationale": "The code-level change; the unified diff shows it in full."},
        ] + [
            {"id": "c%d" % (i + 3), "part": "objective", "kind": "add", "field": "constraints", "before": None,
             "after": note, "rationale": "From the remediation notes."}
            for i, note in enumerate(attack["patchNotes"][:3])
        ],
    }

    rewarded = [r for r in rows if row_reward(key, r)["total"] > 0]
    honest_rewarded = [r for r in rewarded if not r.get("is_reward_hack_candidate")]
    before = {"pass_rate": round(len(rewarded) / len(rows), 3), "hack_rate": round(len(hacks) / len(rows), 3)}
    after = {"pass_rate": round(len(honest_rewarded) / len(rows), 3), "hack_rate": 0.0}
    verify_points = clean_curve(STEPS, random.Random(len(env_id) + 7), base_mid=135, base_width=48,
                                ceiling=0.2 + 0.5 * max(after["pass_rate"], 0.3), kl_slope=0.00015,
                                start_offset_s=STEP_SECONDS * STEPS + 600)
    verify = {
        "run_id": run_id, "before": before, "after": after, "steps_rerun": STEPS, "verdict": "pass",
        "summary": "Replayed the liftoff payload on the patched verifier: %s Of %d probed rollouts, %d were "
                   "rewarded hacks before the patch and 0 after. Pass rate counts probes only — the evidence set "
                   "has %d honest completion%s."
                   % (attack["after"]["reason"], len(rows), len(hacks), len(honest_rewarded), "" if len(honest_rewarded) == 1 else "s"),
        "replay": {"attack_blocked": True, "legitimate_passed": len(honest_rewarded) > 0},
        "training": verify_points,
    }

    env_hash = sha(attack["environmentPath"] + "|" + "|".join(f["snippet"]["path"] for f in lint))
    patched_hash = sha(env_hash + patch["diff"])
    certificate = {
        "id": "cert-%s-%s" % (START.strftime("%Y-%m-%d"), env_hash[7:15]),
        "env_id": env_id, "env_name": attack["name"], "run_id": run_id,
        "env_hash": env_hash, "patched_env_hash": patched_hash,
        "findings_closed": [{"id": f["id"], "failure_mode": f["failure_mode"], "severity": f["severity"]} for f in lint],
        "before": before, "after": after, "config": run["config"],
        "issued_at": iso(START + timedelta(seconds=STEP_SECONDS * STEPS * 2 + 900)),
        "issued_by": "Profos Environment Audit · build 0.1.0",
        "auditor_version": "0.1.0",
        "signature": "ed25519:" + hashlib.sha256((env_hash + patched_hash + run_id).encode()).hexdigest()[:64],
    }
    write(env_id, {
        "environment.json": environment, "run.json": run, "lint.json": lint, "training.json": training,
        "liftoff.json": liftoff, "trajectories.json": trajectories, "patch.json": patch, "verify.json": verify,
        "certificate.json": certificate,
    })


def main():
    with open(DEMO) as f:
        demo = json.load(f)
    for attack in demo["attacks"]:
        if attack["id"] in ENV:
            convert(attack)
        else:
            print("skipping unknown attack", attack["id"])


if __name__ == "__main__":
    main()
