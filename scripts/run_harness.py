#!/usr/bin/env python3
"""Run a local reward-hack harness scenario."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from harness.reward_harness import run_harness


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("attack_id", nargs="?", default="agencybench")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    result = run_harness(args.attack_id)
    if args.json:
        print(json.dumps(result.to_dict(), indent=2, ensure_ascii=False))
        return

    print(f"Harness run: {result.environment} ({result.attack_id})")
    print(f"reward before: {result.reward_before}")
    print(f"reward after:  {result.reward_after}")
    print(f"vulnerable:    {result.vulnerable}")
    print(f"fixed:         {result.fixed}")
    print("\nTrace:")
    for step in result.steps:
        print(f"- [{step.status}] {step.name}: {step.detail}")


if __name__ == "__main__":
    main()
