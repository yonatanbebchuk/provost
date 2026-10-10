# RL LLM-Judge Reward-Hack Red Team

This repo demonstrates a small reward-hacking exploit against an LLM-as-a-judge reward wrapper on an existing RL environment.

## Environment

The existing environment is `FrozenLake-v1` from Gymnasium.

```bash
python3 -m pip install -r requirements.txt
```

## Run the reproducible demo

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
