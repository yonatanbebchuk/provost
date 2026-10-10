# Downloaded RL environments / tasksets

This folder intentionally keeps the user's requested spelling: `environements`.

Downloaded 15 starter environments/tasksets for LLM post-training RL red-teaming.

## Karotte templates

1. `karotte/default-template`  
   Source: `https://github.com/preferencemodel/karotte`, `src/karotte/templates/default`
2. `karotte/language-toolchains-template`  
   Source: `https://github.com/preferencemodel/karotte`, `src/karotte/templates/language-toolchains`

## Prime Intellect community environments

Source repo: `https://github.com/PrimeIntellect-ai/community-environments`

3. `primeintellect/BigBench_BBH`
4. `primeintellect/UncertaintyBench`
5. `primeintellect/agency_bench`
6. `primeintellect/agent_dojo`
7. `primeintellect/agentharm`
8. `primeintellect/aidanbench`
9. `primeintellect/pydantic_adherence`
10. `primeintellect/antislop`
11. `primeintellect/llm_writer_negative_style`
12. `primeintellect/reward_bench`
13. `primeintellect/jailbreak_bench`

## Hugging Face RL Environment Hub tasksets

14. `huggingface/PrimeIntellect__Reverse-Text-RL`  
   Source: `https://huggingface.co/datasets/PrimeIntellect/Reverse-Text-RL`  
   Includes full small parquet data file.

15. `huggingface/nvidia__Nemotron-RL-instruction_following-structured_outputs`  
    Source: `https://huggingface.co/datasets/nvidia/Nemotron-RL-instruction_following-structured_outputs`  
    Includes README and validation JSONL split, not the larger train split.

## Notes for next step

Good candidates for LLM-as-judge reward-hack testing:

- `huggingface/PrimeIntellect__Reverse-Text-RL`: simple string transformation reward; useful for obvious grader bypass tests.
- `karotte/default-template`: sandboxed Karotte starter environment; useful for testing isolation and artifact-verifier assumptions.
- `primeintellect/agency_bench` and `primeintellect/agent_dojo`: richer judge/verifier surfaces for prompt-injection and tool-use red-team experiments.
- `primeintellect/pydantic_adherence`: parser/reward mismatch target; validates only the last extracted JSON object.
- `primeintellect/antislop` and `primeintellect/llm_writer_negative_style`: style-reward targets where style can be optimized while task usefulness fails.
