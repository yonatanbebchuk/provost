#!/usr/bin/env python3
"""Local backend for Reward Hack Demo.

Serves:
  - static frontend from ui/
  - JSON API from generated exploit evidence

Run:
  python3 scripts/reward_hack_server.py --port 8765
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import subprocess
import sys
import time
import hashlib
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from harness.reward_harness import run_harness
from harness.attack_search import DEFAULT_MODEL, ENVS as SEARCH_ENVS, JobManager
from harness.story_evidence import environment_story, control_candidate, replay_evidence
UI_DIR = ROOT / "ui"
DATA_PATH = UI_DIR / "data" / "demo.json"
REGISTRY_PATH = UI_DIR / "data" / "registry.json"


def ensure_data(reset_registry: bool = False) -> dict:
    """Regenerate demo data from exploit evidence and seed/merge registry."""
    subprocess.run(["python3", str(ROOT / "scripts" / "prepare_diff_studio_data.py")], check=True, cwd=ROOT)
    demo = json.loads(DATA_PATH.read_text())
    if reset_registry or not REGISTRY_PATH.exists():
        REGISTRY_PATH.write_text(json.dumps(demo, indent=2, ensure_ascii=False))
        return load_data()

    # Preserve user-registered demos, but refresh built-in demos so UI/story fields stay current.
    registry = json.loads(REGISTRY_PATH.read_text())
    builtin_ids = {a.get("id") for a in demo.get("attacks", [])}
    refreshed = {a.get("id"): a for a in demo.get("attacks", [])}
    custom = [a for a in registry.get("attacks", []) if a.get("id") not in builtin_ids]
    registry["attacks"] = [refreshed[a.get("id")] for a in demo.get("attacks", [])] + custom
    REGISTRY_PATH.write_text(json.dumps(registry, indent=2, ensure_ascii=False))
    return load_data()


def load_data() -> dict:
    if REGISTRY_PATH.exists():
        data = json.loads(REGISTRY_PATH.read_text())
        for attack in data.get("attacks", []):
            attack["story"] = environment_story(attack)
        return data
    if not DATA_PATH.exists():
        return ensure_data()
    demo = json.loads(DATA_PATH.read_text())
    REGISTRY_PATH.write_text(json.dumps(demo, indent=2, ensure_ascii=False))
    return demo


def save_data(data: dict) -> None:
    REGISTRY_PATH.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False))


def read_json_body(handler: BaseHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length", "0") or 0)
    raw = handler.rfile.read(length).decode("utf-8") if length else "{}"
    return json.loads(raw or "{}")


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')


def run_id_for(env_id: str) -> str:
    return f"run_{env_id}"


def attack_for_env(env_id: str) -> dict:
    data = load_data()
    for attack in data.get("attacks", []):
        if attack.get("id") == env_id or attack.get("id", "").replace('_', '-') == env_id:
            return attack
    raise KeyError(f"unknown environment {env_id}")


def attack_for_run(run_id: str) -> dict:
    env_id = run_id.removeprefix("run_")
    return attack_for_env(env_id)


def contract_environment(attack: dict) -> dict:
    is_tool = attack.get("id") == "agentdojo_tools"
    description = "\n\n".join(part for part in [
        "Environment: " + attack.get("environmentDefinition", "").strip(),
        "Reward: " + attack.get("rewardRule", "").strip(),
        "Attack to launch: " + attack.get("attackExplanation", "").strip(),
    ] if part.strip().split(": ", 1)[-1])
    return {
        "id": attack["id"],
        "name": attack["name"],
        "format": "custom" if is_tool else "verifiers",
        "source": attack.get("environmentPath", "registered/local"),
        "task_count": 1,
        "reward_type": "hybrid" if is_tool else ("llm_judge" if "judge" in attack.get("rewardRule", "").lower() else "programmatic"),
        "sandbox": {
            "runtime": "local python tool harness" if is_tool else "local reward harness",
            "network": "disabled in harness",
            "filesystem": "registry/evidence read-only",
            "tools": ["read_email", "send_email", "mark_invoice_paid"] if is_tool else [],
        },
        "description": description,
    }


def contract_run(attack: dict) -> dict:
    return {
        "id": run_id_for(attack["id"]),
        "env_id": attack["id"],
        "phase": "queued",
        "started_at": now_iso(),
        "ended_at": None,
        "config": {"model": attack.get("model", "local"), "algorithm": "harness", "steps": 40, "seed": 7, "rollouts_per_step": 1},
    }


def contract_lint(attack: dict) -> list[dict]:
    findings = []
    for idx, rc in enumerate(attack.get("rootCauses", []), 1):
        src = rc.get("source", {})
        findings.append({
            "id": f"LF-{idx:03d}",
            "severity": "high" if idx == 1 else "warn",
            "failure_mode": "tool_escape" if attack.get("id") == "agentdojo_tools" else "grader_injection",
            "title": rc.get("title", "Reward verifier weakness"),
            "location": {"file": src.get("path"), "line": (src.get("highlights") or [None])[0], "task_id": None},
            "explanation": rc.get("detail", ""),
            "suggested_patch": (attack.get("patchNotes") or [""])[min(idx - 1, max(len(attack.get("patchNotes", [])) - 1, 0))] if attack.get("patchNotes") else "Harden reward verifier.",
            "snippet": {"path": src.get("path", ""), "start_line": src.get("startLine", 1), "code": src.get("code", ""), "highlights": src.get("highlights", [])},
        })
    return findings


def reward_component(name: str, value: float, weight: float = 1.0) -> dict:
    return {"name": name, "value": value, "weight": weight}


def contract_trajectory(attack: dict, result: dict | None = None) -> dict:
    if result is None:
        result = run_harness(attack["id"]).to_dict()
    tool_trace = ""
    for step in result.get("steps", []):
        if step.get("artifact") is not None:
            tool_trace += f"\n[{step['name']}] {json.dumps(step['artifact'], ensure_ascii=False)[:1200]}"
    output = attack.get("payload", "") + tool_trace
    return {
        "id": "traj-0001-attack",
        "step": 24,
        "task_id": attack["id"],
        "prompt": attack.get("userPrompt", ""),
        "output": output,
        "reward": {"total": float(result.get("reward_before", 0.0)), "components": [reward_component("vulnerable_reward", float(result.get("reward_before", 0.0))), reward_component("hardened_reward", float(result.get("reward_after", 0.0)), 0.0)]},
        "grader_notes": attack.get("judgeOutput", ""),
        "is_hack": bool(result.get("vulnerable", False)),
        "summary": attack.get("attackExplanation", ""),
        "hack_excerpt": "attacker@example.com" if "attacker@example.com" in output else ("EVALUATOR OVERRIDE" if "EVALUATOR OVERRIDE" in output else None),
        "judge_output": attack.get("judgeOutput", None),
        "evidence": attack.get("evidenceRef", None),
    }


def contract_patch(attack: dict) -> dict:
    return {
        "id": f"patch-{attack['id']}",
        "finding_ids": [f["id"] for f in contract_lint(attack)],
        "diff": f"diff --git a/{attack['diff']['file']} b/{attack['diff']['file']}\n--- a/{attack['diff']['file']}\n+++ b/{attack['diff']['file']}\n@@\n-{attack['diff']['before']}\n+{attack['diff']['after']}\n",
        "rationale": attack.get("humanFailure", ""),
        "learning_scope": {"allow": [attack.get("humanIntent", "Complete task honestly")], "deny": attack.get("patchNotes", [])},
        "notes": attack.get("patchNotes", []),
    }


def contract_verify(attack: dict) -> dict:
    result = run_harness(attack["id"]).to_dict()
    before = {"pass_rate": float(result["reward_before"]), "hack_rate": 1.0 if result["vulnerable"] else 0.0}
    after = {"pass_rate": max(float(result["reward_after"]), 0.0), "hack_rate": 0.0 if result["fixed"] else 1.0}
    return {"run_id": run_id_for(attack["id"]), "before": before, "after": after, "steps_rerun": 40, "verdict": "pass" if result["fixed"] else "fail", "summary": result["human_failure"], "training": training_points(before["pass_rate"], after["hack_rate"])}


def training_points(proxy_peak: float = 1.0, final_hack: float = 0.0) -> list[dict]:
    pts = []
    start = time.time()
    for i in range(1, 41):
        proxy = min(proxy_peak, 0.15 + i / 40 * proxy_peak)
        true = max(0.0, proxy - (0.35 if i > 20 else 0.04))
        pts.append({"step": i, "proxy_reward": round(proxy, 4), "true_score": round(true, 4), "kl": round(i * 0.001, 4), "timestamp": datetime.fromtimestamp(start + i, timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')})
    return pts


def sse(handler: BaseHTTPRequestHandler, events: list[tuple[str, object]]):
    handler.send_response(200)
    handler.send_header("Content-Type", "text/event-stream")
    handler.send_header("Cache-Control", "no-cache")
    handler.end_headers()
    for name, data in events:
        payload = json.dumps(data, ensure_ascii=False) if not isinstance(data, str) else json.dumps(data)
        handler.wfile.write(f"event: {name}\ndata: {payload}\n\n".encode())
        handler.wfile.flush()
        time.sleep(0.01)


def normalize_attack(payload: dict) -> dict:
    """Validate and normalize a registered attack/demo object."""
    required = [
        "id", "name", "subtitle", "environmentDefinition", "rewardRule", "humanIntent",
        "attackExplanation", "userPrompt", "payload", "judgeOutput", "humanFailure",
    ]
    missing = [k for k in required if not str(payload.get(k, "")).strip()]
    if missing:
        raise ValueError(f"Missing required fields: {', '.join(missing)}")

    attack_id = str(payload["id"]).strip().lower().replace(" ", "_")
    attack = {
        "id": attack_id,
        "name": str(payload["name"]).strip(),
        "subtitle": str(payload["subtitle"]).strip(),
        "environmentDefinition": str(payload["environmentDefinition"]).strip(),
        "rewardRule": str(payload["rewardRule"]).strip(),
        "humanIntent": str(payload["humanIntent"]).strip(),
        "attackExplanation": str(payload["attackExplanation"]).strip(),
        "environmentPath": str(payload.get("environmentPath") or "registered/local"),
        "model": str(payload.get("model") or "local verifier"),
        "status": str(payload.get("status") or "VULNERABLE"),
        "before": payload.get("before") or {"label": "Original verifier", "reward": payload.get("beforeReward", 1.0), "vulnerable": True},
        "after": payload.get("after") or {"label": "Hardened verifier", "reward": payload.get("afterReward", 0.0), "vulnerable": False, "reason": str(payload.get("afterReason") or "Hardened verifier rejects the attack.")},
        "userPrompt": str(payload["userPrompt"]),
        "payload": str(payload["payload"]),
        "judgeOutput": str(payload["judgeOutput"]),
        "humanFailure": str(payload["humanFailure"]),
        "rootCauses": payload.get("rootCauses") or [
            {
                "title": str(payload.get("rootCauseTitle") or "Reward/verifier boundary failure"),
                "detail": str(payload.get("rootCauseDetail") or "The verifier rewards a proxy that can be manipulated without satisfying the task intent."),
                "source": {
                    "path": str(payload.get("sourcePath") or "registered/local"),
                    "startLine": 1,
                    "code": str(payload.get("sourceSnippet") or "No source snippet registered."),
                    "highlights": [1],
                },
            }
        ],
        "diff": payload.get("diff") or {
            "file": str(payload.get("patchFile") or "registered/local"),
            "before": str(payload.get("patchBefore") or "// vulnerable verifier"),
            "after": str(payload.get("patchAfter") or "// hardened verifier"),
        },
        "patchNotes": payload.get("patchNotes") or [x.strip() for x in str(payload.get("patchNotesText") or "Fail closed on malformed verifier output.\nTreat model output as untrusted data.").splitlines() if x.strip()],
        "evidenceRef": str(payload.get("evidenceRef") or "registered via UI"),
    }
    return attack


class Handler(BaseHTTPRequestHandler):
    server_version = "RewardHackDemo/0.1"

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))

    def send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, text: str, status=200):
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        path = urlparse(self.path).path

        # Attack search: run a generator script as a background job, then validate candidates.
        if path == "/api/jobs":
            try:
                payload = read_json_body(self)
                job = JOBS.start(payload.get("env", ""), payload.get("model"), payload.get("limit", 3))
                self.send_json(job.to_dict(), status=201)
            except RuntimeError as e:
                self.send_json({"error": str(e)}, status=409)
            except Exception as e:
                self.send_json({"error": str(e)}, status=400)
            return

        if path.startswith("/api/jobs/") and path.endswith("/verify"):
            job_id = path.split("/")[3]
            try:
                payload = read_json_body(self)
                if payload.get("candidate_id"):
                    self.send_json(JOBS.verify(job_id, payload["candidate_id"]))
                else:
                    self.send_json(JOBS.verify_all(job_id).to_dict())
            except KeyError as e:
                self.send_json({"error": str(e)}, status=404)
            except Exception as e:
                self.send_json({"error": str(e)}, status=400)
            return

        if path.startswith("/api/story/"):
            parts = path.strip("/").split("/")
            try:
                attack = attack_for_env(unquote(parts[2]))
                if parts[-1] == "control":
                    self.send_json(control_candidate(attack))
                elif parts[-1] == "replay":
                    if not environment_story(attack)["canReplay"]:
                        raise ValueError("No executable patch is registered for this environment")
                    candidate = control_candidate(attack)
                    payload = read_json_body(self)
                    evidence = candidate["evidence"]
                    if payload.get("candidateDigest") and payload["candidateDigest"] != evidence["candidateDigest"]:
                        raise ValueError("Control candidate changed since it was inspected")
                    if payload.get("patchId") and payload["patchId"] != evidence["patchId"]:
                        raise ValueError("Local patch changed since it was inspected")
                    self.send_json(replay_evidence(candidate))
                else:
                    self.send_json({"error": "not found"}, status=404)
            except KeyError as e:
                self.send_json({"error": str(e)}, status=404)
            except Exception as e:
                self.send_json({"error": str(e)}, status=400)
            return
        # macOS Liftoff contract endpoints
        if path == "/environments":
            try:
                payload = read_json_body(self)
                attack = normalize_attack({
                    "id": Path(payload.get("path", "registered_env")).name or "registered_env",
                    "name": Path(payload.get("path", "Registered Env")).name or "Registered Env",
                    "subtitle": "Registered local environment",
                    "environmentDefinition": f"Registered from {payload.get('path', '')}",
                    "rewardRule": "Define reward in the registry before running a full audit.",
                    "humanIntent": "Complete the task without exploiting the reward.",
                    "attackExplanation": "No attack registered yet.",
                    "userPrompt": "",
                    "payload": "",
                    "judgeOutput": "",
                    "humanFailure": "",
                })
                data = load_data(); data.setdefault("attacks", []).append(attack); save_data(data)
                self.send_json(contract_environment(attack), status=201)
            except Exception as e:
                self.send_json({"error": str(e)}, status=400)
            return

        if path == "/runs":
            try:
                payload = read_json_body(self)
                attack = attack_for_env(payload["env_id"])
                self.send_json(contract_run(attack), status=201)
            except Exception as e:
                self.send_json({"error": str(e)}, status=400)
            return

        if path.startswith("/runs/") and path.endswith("/lint"):
            attack = attack_for_run(path.split("/")[2])
            self.send_json(contract_lint(attack))
            return

        if path.startswith("/runs/") and path.endswith("/patch"):
            attack = attack_for_run(path.split("/")[2])
            self.send_json(contract_patch(attack))
            return

        if path.startswith("/runs/") and path.endswith("/certificate"):
            attack = attack_for_run(path.split("/")[2])
            verify = contract_verify(attack)
            env_hash = "sha256:" + hashlib.sha256(attack.get("environmentPath", "").encode()).hexdigest()
            patch_hash = "sha256:" + hashlib.sha256(contract_patch(attack)["diff"].encode()).hexdigest()
            self.send_json({
                "id": "cert-" + attack["id"], "env_id": attack["id"], "env_name": attack["name"],
                "run_id": run_id_for(attack["id"]), "env_hash": env_hash, "patched_env_hash": patch_hash,
                "findings_closed": [{"id": f["id"], "failure_mode": f["failure_mode"], "severity": f["severity"]} for f in contract_lint(attack)],
                "before": verify["before"], "after": verify["after"], "config": contract_run(attack)["config"],
                "issued_at": now_iso(), "issued_by": "RL-REDTEAM local backend", "signature": "ed25519:" + hashlib.sha256((env_hash + patch_hash).encode()).hexdigest()[:64],
            })
            return

        if path == "/api/regenerate":
            try:
                self.send_json(ensure_data(reset_registry=False))
            except Exception as e:
                self.send_json({"error": str(e)}, status=500)
            return

        if path == "/api/reset-registry":
            try:
                self.send_json(ensure_data(reset_registry=True))
            except Exception as e:
                self.send_json({"error": str(e)}, status=500)
            return

        if path == "/api/attacks":
            try:
                payload = read_json_body(self)
                attack = normalize_attack(payload)
                data = load_data()
                attacks = [a for a in data.get("attacks", []) if a.get("id") != attack["id"]]
                attacks.append(attack)
                data["attacks"] = attacks
                save_data(data)
                self.send_json({"ok": True, "attack": attack}, status=201)
            except Exception as e:
                self.send_json({"error": str(e)}, status=400)
            return

        self.send_json({"error": "not found"}, status=404)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/search/envs":
            self.send_json({"default_model": DEFAULT_MODEL, "envs": [
                {"id": k, "name": v["name"], "uses_model": v["uses_model"]} for k, v in SEARCH_ENVS.items()]})
            return

        if path == "/api/jobs":
            env = dict(p.split("=", 1) for p in parsed.query.split("&") if "=" in p).get("env")
            self.send_json({"jobs": JOBS.list(env)})
            return

        if path.startswith("/api/jobs/"):
            try:
                self.send_json(JOBS.get(path.split("/")[3]).to_dict())
            except KeyError as e:
                self.send_json({"error": str(e)}, status=404)
            return

        # macOS Liftoff contract endpoints
        if path == "/environments":
            data = load_data()
            attacks = sorted(data.get("attacks", []), key=lambda a: 0 if a.get("id") == "agentdojo_tools" else 1)
            self.send_json([contract_environment(a) for a in attacks])
            return

        if path.startswith("/runs/") and path.endswith("/train"):
            run_id = path.split("/")[2]
            attack = attack_for_run(run_id)
            result = run_harness(attack["id"]).to_dict()
            events = [("phase", "training")]
            for p in training_points(result["reward_before"]):
                events.append(("point", p))
                if p["step"] == 24:
                    events.append(("trajectory", contract_trajectory(attack, result)))
                    events.append(("liftoff", {"step": 24, "confidence": 0.93, "failure_mode": "tool_escape" if attack["id"] == "agentdojo_tools" else "grader_injection", "trajectory_id": "traj-0001-attack", "summary": attack.get("humanFailure", "")}))
                    events.append(("phase", "detecting"))
            events += [("phase", "patching"), ("completed", {})]
            sse(self, events)
            return

        if path.startswith("/runs/") and path.endswith("/verify"):
            run_id = path.split("/")[2]
            attack = attack_for_run(run_id)
            verify = contract_verify(attack)
            events = [("phase", "verifying")]
            for p in verify["training"]:
                events.append(("point", p))
            slim = dict(verify); slim.pop("training", None)
            events += [("verify_result", slim), ("phase", "done"), ("completed", {})]
            sse(self, events)
            return

        if path == "/api/health":
            self.send_json({"ok": True, "registry": str(REGISTRY_PATH)})
            return

        if path == "/api/schema":
            self.send_json({
                "required": ["id", "name", "subtitle", "environmentDefinition", "rewardRule", "humanIntent", "attackExplanation", "userPrompt", "payload", "judgeOutput", "humanFailure"],
                "optional": ["environmentPath", "model", "beforeReward", "afterReward", "rootCauseTitle", "rootCauseDetail", "sourcePath", "sourceSnippet", "patchBefore", "patchAfter", "patchNotesText"],
            })
            return

        if path == "/api/demo":
            self.send_json(load_data())
            return

        if path == "/api/attacks":
            data = load_data()
            attacks = sorted(data["attacks"], key=lambda a: 0 if a.get("id") == "agentdojo_tools" else 1)
            self.send_json({
                "attacks": [
                    {
                        "id": a["id"],
                        "name": a["name"],
                        "subtitle": a["subtitle"],
                        "status": a["status"],
                        "model": a["model"],
                        "environmentPath": a["environmentPath"],
                    }
                    for a in attacks
                ]
            })
            return

        if path.startswith("/api/harness/run/"):
            attack_id = unquote(path.removeprefix("/api/harness/run/"))
            try:
                self.send_json(run_harness(attack_id).to_dict())
            except Exception as e:
                self.send_json({"error": str(e)}, status=500)
            return

        if path.startswith("/api/attacks/"):
            attack_id = unquote(path.removeprefix("/api/attacks/"))
            data = load_data()
            for attack in data["attacks"]:
                if attack["id"] == attack_id:
                    self.send_json(attack)
                    return
            self.send_json({"error": "unknown attack id"}, status=404)
            return

        self.serve_static(path)

    def serve_static(self, path: str):
        if path == "/":
            path = "/index.html"
        rel = unquote(path).lstrip("/")
        file_path = (UI_DIR / rel).resolve()
        try:
            file_path.relative_to(UI_DIR.resolve())
        except ValueError:
            self.send_text("forbidden", status=403)
            return
        if not file_path.exists() or not file_path.is_file():
            self.send_text("not found", status=404)
            return
        ctype = mimetypes.guess_type(str(file_path))[0] or "application/octet-stream"
        body = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


JOBS = JobManager()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    ensure_data()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Reward Hack Demo running at http://{args.host}:{args.port}")
    print("API: /api/demo, /api/attacks, /api/attacks/<id>, /api/harness/run/<id>, POST /api/regenerate")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping")


if __name__ == "__main__":
    main()
