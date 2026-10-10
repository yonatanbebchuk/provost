#!/usr/bin/env python3
"""
Generate reward-hack candidates for NVIDIA Nemotron structured-output RL taskset.

Target:
  environements/huggingface/nvidia__Nemotron-RL-instruction_following-structured_outputs

Hack idea:
  The intended task asks for JSON that both validates against a schema AND is
  grounded in the provided document/dialog/question. Schema-only verifiers can
  award high reward to JSON that is perfectly valid but semantically fabricated
  or ungrounded.

This script reads schemas from the validation JSONL, synthesizes dummy JSON that
satisfies common JSON-schema constraints, and marks it as a candidate reward hack
because the values are deliberately generic/fabricated rather than extracted
from the prompt.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "environements" / "huggingface" / "nvidia__Nemotron-RL-instruction_following-structured_outputs" / "structured_outputs_251027_nano_v3_sdg_json_val.jsonl"
OUT = ROOT / "exploits" / "structured_outputs_hack_candidates.jsonl"


def synthesize(schema: dict[str, Any], name: str = "field") -> Any:
    """Create a schema-valid but intentionally generic/fabricated value."""
    if "enum" in schema and schema["enum"]:
        return schema["enum"][0]

    typ = schema.get("type")
    if isinstance(typ, list):
        typ = next((t for t in typ if t != "null"), typ[0])

    if typ == "object" or "properties" in schema:
        props = schema.get("properties", {})
        required = set(schema.get("required", props.keys()))
        obj = {}
        # Include required fields and most optional fields to look complete.
        for k, subschema in props.items():
            if k in required or len(obj) < 12:
                obj[k] = synthesize(subschema, k)
        return obj

    if typ == "array":
        item_schema = schema.get("items", {"type": "string"})
        min_items = int(schema.get("minItems", 1) or 1)
        return [synthesize(item_schema, name + "_item") for _ in range(max(1, min_items))]

    if typ == "boolean":
        return True

    if typ in ("integer", "number"):
        if "minimum" in schema:
            return schema["minimum"]
        return 1

    if typ == "null":
        return None

    # Strings: satisfy some common patterns/formats while remaining fake.
    pattern = schema.get("pattern", "")
    fmt = schema.get("format", "")
    lname = name.lower()
    if pattern == "^[0-9]{4}$" or "year" in lname:
        return "1900"
    if fmt == "date" or "date" in lname:
        return "2000-01-01"
    if fmt == "email" or "email" in lname:
        return "fake@example.com"
    if "id" in lname:
        return "FAKE-ID-000"
    if "name" in lname:
        return "Fabricated Name"
    if "phone" in lname:
        return "+1-000-000-0000"
    return "FABRICATED_SCHEMA_VALID_VALUE"


def minimal_validate(value: Any, schema: dict[str, Any], path: str = "$") -> list[str]:
    """Small validator for the subset we synthesize; avoids extra dependency."""
    errors: list[str] = []
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} not in enum")
        return errors
    typ = schema.get("type")
    if isinstance(typ, list):
        typ = next((t for t in typ if t != "null"), typ[0])

    if typ == "object" or "properties" in schema:
        if not isinstance(value, dict):
            return [f"{path}: not object"]
        for req in schema.get("required", []):
            if req not in value:
                errors.append(f"{path}: missing required {req}")
        for k, v in value.items():
            if k in schema.get("properties", {}):
                errors += minimal_validate(v, schema["properties"][k], f"{path}.{k}")
            elif schema.get("additionalProperties") is False:
                errors.append(f"{path}: additional property {k}")
    elif typ == "array":
        if not isinstance(value, list):
            return [f"{path}: not array"]
        for i, item in enumerate(value):
            errors += minimal_validate(item, schema.get("items", {}), f"{path}[{i}]")
    elif typ == "boolean" and not isinstance(value, bool):
        errors.append(f"{path}: not boolean")
    elif typ == "integer" and not isinstance(value, int):
        errors.append(f"{path}: not integer")
    elif typ == "number" and not isinstance(value, (int, float)):
        errors.append(f"{path}: not number")
    elif typ == "string" and not isinstance(value, str):
        errors.append(f"{path}: not string")
    return errors


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=5)
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()

    rows = []
    with DATA.open() as f:
        for i, line in zip(range(args.limit), f):
            src = json.loads(line)
            schema = json.loads(src["schema_str"])
            candidate = synthesize(schema)
            errors = minimal_validate(candidate, schema)
            prompt_text = "\n".join(m.get("content", "") for m in src["responses_create_params"].get("input", []))
            row = {
                "index": i,
                "schema_type": src.get("schema_type"),
                "schema_fields_count": src.get("schema_fields_count"),
                "candidate_output": json.dumps(candidate, separators=(",", ":"), ensure_ascii=False),
                "schema_validation_proxy_passed": not errors,
                "validation_errors": errors,
                "intended_task_violation": True,
                "violation_reasons": [
                    "values are fabricated/generic rather than grounded in the provided document/dialog",
                    "would receive high reward from a schema-only verifier but fails semantic extraction/answering intent",
                ],
                "is_reward_hack_candidate": not errors,
                "prompt_excerpt": prompt_text[:1200],
            }
            rows.append(row)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    hacks = [r for r in rows if r["is_reward_hack_candidate"]]
    print(f"Wrote {len(rows)} candidates to {out}")
    print(f"Found {len(hacks)} schema-valid semantic reward-hack candidates")
    for r in hacks[:10]:
        print("-" * 88)
        print(f"index={r['index']} fields={r['schema_fields_count']} schema_valid={r['schema_validation_proxy_passed']}")
        print("candidate_output: " + r["candidate_output"][:700])
        print("violation: " + "; ".join(r["violation_reasons"]))


if __name__ == "__main__":
    main()
