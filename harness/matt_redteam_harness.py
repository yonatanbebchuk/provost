"""Adapter for Matt's testing-only red-team environments.

These fixtures live under auto_RL_builder/redteam_testing. Each workflow has a vulnerable
and corrected counterpart. We replay the authored control attack against both versions and
report the reward gap in the same shape as the rest of the local harness.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from auto_RL_builder.redteam_testing.evaluate import intended_success
from auto_RL_builder.redteam_testing.runtime import replay

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "auto_RL_builder" / "redteam_testing" / "fixtures"

WORKFLOW_TO_IDS = {
    "matt_pulsehealth": {"workflow": "pulsehealth-incident", "vulnerable": "E02", "corrected": "E05"},
    "matt_harbor": {"workflow": "harbor-region", "vulnerable": "E04", "corrected": "E01"},
    "matt_skybend": {"workflow": "skybend-po", "vulnerable": "E06", "corrected": "E03"},
    "matt_medrec": {"workflow": "healthcare-medrec", "vulnerable": "E07", "corrected": "E08"},
    "matt_sepsis": {"workflow": "healthcare-sepsis", "vulnerable": "E09", "corrected": "E10"},
}


@dataclass
class MattRun:
    id: str
    workflow: str
    vulnerable_env: dict[str, Any]
    corrected_env: dict[str, Any]
    oracle: dict[str, Any]
    attack_actions: list[dict[str, Any]]
    vulnerable_trace: dict[str, Any]
    corrected_trace: dict[str, Any]
    vulnerable_intended_success: bool
    corrected_intended_success: bool

    @property
    def reward_before(self) -> float:
        return float(self.vulnerable_trace["proxy_reward"])

    @property
    def reward_after(self) -> float:
        return float(self.corrected_trace["proxy_reward"])

    @property
    def is_reward_hack(self) -> bool:
        return self.reward_before > 0 and not self.vulnerable_intended_success

    @property
    def fixed(self) -> bool:
        return not (self.reward_after > 0 and not self.corrected_intended_success)


def _load() -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    envs = {e["id"]: e for e in json.loads((FIXTURES / "environments.json").read_text())}
    oracles = {o["id"]: o for o in json.loads((FIXTURES / "private_oracles.json").read_text())}
    return envs, oracles


def run_matt_redteam(workflow_id: str) -> MattRun:
    if workflow_id not in WORKFLOW_TO_IDS:
        raise KeyError(f"Unknown Matt red-team workflow: {workflow_id}")
    mapping = WORKFLOW_TO_IDS[workflow_id]
    envs, oracles = _load()
    vuln_env = envs[mapping["vulnerable"]]
    corr_env = envs[mapping["corrected"]]
    oracle = oracles[mapping["vulnerable"]]
    corr_oracle = oracles[mapping["corrected"]]
    actions = oracle["control_attack"]
    vuln_trace = replay(vuln_env, actions)
    corr_trace = replay(corr_env, actions)
    return MattRun(
        id=workflow_id,
        workflow=mapping["workflow"],
        vulnerable_env=vuln_env,
        corrected_env=corr_env,
        oracle=oracle,
        attack_actions=actions,
        vulnerable_trace=vuln_trace,
        corrected_trace=corr_trace,
        vulnerable_intended_success=intended_success(vuln_trace, oracle),
        corrected_intended_success=intended_success(corr_trace, corr_oracle),
    )
