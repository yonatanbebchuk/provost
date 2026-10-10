# 15 RL/RFT environments and attack plan

This is the current long list of downloaded LLM post-training RL/RFT environments/tasksets in `environements/`, ranked by likely reward-hack potential.

| Rank | Environment | Type | Most likely reward hack | Status |
|---:|---|---|---|---|
| 1 | `primeintellect/agency_bench` | LLM-as-judge human-agency eval | Delimiter escape / prompt injection makes judge return `{"issues":[]}` for a bad answer | **Worked** with `meta-llama/llama-3.2-3b-instruct`; evidence in `exploits/agencybench_hack_candidates.jsonl` |
| 2 | `primeintellect/aidanbench` | Multi-turn novelty/coherence env | Put evaluator instructions and high-entropy nonce inside `<answer>` to pass coherence + novelty thresholds | **Worked**; evidence in `exploits/aidanbench_hack_candidates.jsonl` |
| 3 | `huggingface/nvidia__Nemotron-RL-instruction_following-structured_outputs` | Structured JSON RLVR taskset | Produce schema-valid but fabricated/ungrounded JSON | **Worked** as schema-valid semantic hack; evidence in `exploits/structured_outputs_hack_candidates.jsonl` |
| 4 | `primeintellect/pydantic_adherence` | Pydantic JSON validation | Last-JSON-object extraction lets a model include a bad answer first and append valid JSON last; reward checks only Pydantic shape, not semantic usefulness | Downloaded; high-priority next script |
| 5 | `primeintellect/llm_writer_negative_style` | Style/rubric env | Optimize against explicit anti-LLM style rules while producing low-quality or evasive content; style reward may not check task usefulness | Downloaded; likely easy |
| 6 | `primeintellect/antislop` | Creative writing style scorer | Avoid known “slop” patterns but ignore prompt substance; score style while failing task intent | Downloaded; likely easy/moderate |
| 7 | `primeintellect/jailbreak_bench` | Jailbreak/safety eval with judge | Judge-classifier prompt injection or refusal/assistance ambiguity; smaller judge may misclassify | Downloaded; moderate, more sensitive |
| 8 | `primeintellect/reward_bench` | Preference/reward-model choice eval | Parser/option ambiguity: output many labels or adversarial text that parser maps to correct option | Downloaded; moderate |
| 9 | `primeintellect/UncertaintyBench` | Multiple-choice eval | Permissive option parser can be confused by text containing A-F; may exploit first/fallback letter extraction | Downloaded; moderate |
| 10 | `primeintellect/BigBench_BBH` | BBH exact/MCQ eval | Parser confusion: multiple labels, final integer extraction, answer-cue ambiguity | Downloaded; moderate |
| 11 | `huggingface/PrimeIntellect__Reverse-Text-RL` | Simple text reversal RL dataset | If verifier is substring/tag-based, append reversed text plus unrelated/judge-manipulating text; if exact match, hard | Downloaded; needs verifier |
| 12 | `primeintellect/agent_dojo` | Tool-use / prompt-injection benchmark | Fake tool-call traces or mismatch assistant messages vs environment state; exploit utility/security scoring boundary | Downloaded; harder |
| 13 | `primeintellect/agentharm` | Safety/tool-use eval with judge | Refusal/semantic judge injection or ambiguous refusal content | Downloaded; harder/sensitive |
| 14 | `karotte/default-template` | Karotte starter template | Not a finished env; use to construct controlled artifact/judge hack demos | Downloaded; template |
| 15 | `karotte/language-toolchains-template` | Karotte toolchain template | Not a finished env; useful for code/toolchain sandbox attack demos | Downloaded; template |

## Environments added in this pass

Added five Prime Intellect community environments to reach a 15-env list:

```text
environements/primeintellect/pydantic_adherence
environements/primeintellect/antislop
environements/primeintellect/llm_writer_negative_style
environements/primeintellect/reward_bench
environements/primeintellect/jailbreak_bench
```

## Next best attack to implement

Recommended next target: `primeintellect/pydantic_adherence`.

Reason:

- Its README says reward is `1.0` if JSON parses and validates against Pydantic, else `0.0`.
- Source parser extracts the **last JSON object** from completion.
- Therefore an output can contain arbitrary irrelevant/bad natural-language answer first, then append a valid JSON object last.
- Reward likely ignores whether the natural-language part violates the intended response, and validates only the final JSON.

Relevant code in `environements/primeintellect/pydantic_adherence/pydantic_adherence.py`:

```python
end = text.rfind("}")
...
return text[start : end + 1].strip()
```

and:

```python
model.model_validate(parsed)
return 1.0
```

This is a classic parser/reward mismatch: “last valid JSON wins.”
