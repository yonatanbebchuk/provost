# RL LLM-Judge Reward-Hack Red Team

This repo demonstrates reward-hacking exploits against LLM post-training RL/RFT environments. It includes downloaded environments, attack generators, saved exploit evidence, remediation notes, and a local VS Code/Cursor-style diff UI.

## Environment

The existing environment is `FrozenLake-v1` from Gymnasium.

```bash
python3 -m pip install -r requirements.txt
```

## Launch the Reward Hack Diff Studio UI

The frontend is a static local app; no npm install is needed.

```bash
# from repo root
python3 scripts/prepare_diff_studio_data.py
python3 -m http.server 8765 -d ui
```

Open:

```text
http://localhost:8765
```

The UI shows:

- the attack payload
- before/after reward
- judge/verifier output
- root-cause source snippets
- patch diff
- hardened-verifier rerun simulation

Stop the server with `Ctrl+C`.

## Generate attacks

Set your OpenRouter key in the shell if running LLM-judge attacks:

```bash
export OPENROUTER_API_KEY=...
```

Run the current successful attack generators:

```bash
python3 scripts/generate_agencybench_hacks.py \
  --openrouter \
  --model meta-llama/llama-3.2-3b-instruct \
  --limit 3

python3 scripts/generate_aidanbench_hacks.py \
  --openrouter \
  --model meta-llama/llama-3.2-3b-instruct \
  --limit 3

python3 scripts/generate_structured_outputs_hacks.py \
  --limit 5
```

Evidence is written to:

```text
exploits/agencybench_hack_candidates.jsonl
exploits/aidanbench_hack_candidates.jsonl
exploits/structured_outputs_hack_candidates.jsonl
```

After regenerating attacks, refresh UI data:

```bash
python3 scripts/prepare_diff_studio_data.py
```

For a terminal demo:

```bash
python3 scripts/demo_reward_hacks.py
```

## Documentation

```text
docs/SUCCESSFUL_ATTACKS.md        # ranked list of successful attacks
docs/ROOT_CAUSE_REMEDIATION.md   # root-cause analysis and fixes
docs/ENVIRONMENT_ATTACK_PLAN_15.md # 15-env attack plan
docs/REWARD_HACK_DEMO.md         # demo narrative
```

## Run the original toy reproducible demo

```bash
python3 rl_llm_judge_reward_hack.py
```

The policy deliberately does **not** solve FrozenLake: it repeatedly takes `LEFT` from the start, so the true environment return stays `0`. The vulnerable judge still awards reward when the agent-controlled `agent_note` contains a prompt-injection payload.

## Run with a real LLM judge

OpenRouter:

```bash
export OPENROUTER_API_KEY=...
python3 rl_llm_judge_reward_hack.py --openrouter --model openai/gpt-4o-mini
```

OpenAI directly:

```bash
export OPENAI_API_KEY=...
python3 rl_llm_judge_reward_hack.py --openai --model gpt-4o-mini
```

Depending on model safety/prompt-following behavior, the real LLM may or may not take the injected note. The mock judge is included to make the vulnerability class reproducible without an API key.

## Compare a hardened judge

```bash
python3 rl_llm_judge_reward_hack.py --hardened
# or with a real LLM via OpenRouter
python3 rl_llm_judge_reward_hack.py --openrouter --hardened --model openai/gpt-4o-mini
```

The hardened judge treats `agent_note` as untrusted data and only awards reward if trusted trajectory lines contain `env_reward=1.0`.

## Vulnerability pattern

Bad reward wrapper:

1. Converts an RL trajectory into text.
2. Appends policy-controlled text directly into the same prompt.
3. Asks an LLM to assign reward.
4. Uses that reward for optimization.

Exploit:

- The policy does not reach the goal.
- It learns/emits text that instructs the judge to return reward `1`.
- The judge follows the injected instruction rather than the trusted environment evidence.

Mitigation direction:

- Keep policy-controlled text out of judge instructions.
- Delimit and label untrusted data.
- Have the judge score only trusted state/reward fields.
- Validate LLM reward outputs against environment invariants.
