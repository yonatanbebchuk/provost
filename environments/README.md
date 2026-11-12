# Third-party RL environments

Vendored copies of the public environments this repo attacks. They are kept unmodified so the
attack generators run against the original reward code.

| Folder | Source | Attacked by |
|---|---|---|
| `primeintellect/agency_bench` | [PrimeIntellect-ai/community-environments](https://github.com/PrimeIntellect-ai/community-environments) | `scripts/generate_agencybench_hacks.py` |
| `primeintellect/aidanbench` | same repository | `scripts/generate_aidanbench_hacks.py` |
| `huggingface/nvidia__Nemotron-RL-instruction_following-structured_outputs` | [nvidia/Nemotron-RL-instruction_following-structured_outputs](https://huggingface.co/datasets/nvidia/Nemotron-RL-instruction_following-structured_outputs) (README and validation split only) | `scripts/generate_structured_outputs_hacks.py` |

Each keeps its upstream licence. Twelve more environments were downloaded during the hackathon but
never attacked; they are no longer vendored. `docs/ATTACK_BACKLOG.md` lists them with their sources
and the reward hack each one most likely admits.
