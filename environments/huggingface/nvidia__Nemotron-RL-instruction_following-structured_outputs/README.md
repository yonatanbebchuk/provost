---
license: cc-by-4.0
tags:
- nemo-gym
---
## Dataset Description:

The Nemotron-RL-instruction_following-structured_outputs dataset tests the ability of the model to follow output formatting instructions under schema constraints under the JSON format. Each problem consists of three components: The document, output formatting Instruction (Schema), and question. The dataset varies the difficulty of each problem by varying the location of instructions, the comprehensiveness of instructions, the complexity of the schema, and the type of document/user message. 

This dataset is released as part of NVIDIA [NeMo Gym](https://github.com/NVIDIA-NeMo/Gym), a framework for building reinforcement learning environments to train large language models. NeMo Gym contains a growing collection of training environments and datasets to enable Reinforcement Learning from Verifiable Reward (RLVR).

NeMo Gym is an open-source library within the [NVIDIA NeMo framework](https://github.com/NVIDIA-NeMo/), NVIDIA's GPU accelerated, end-to-end training framework for large language models (LLMs), multi-modal models and speech models.

This dataset is part of the [Nemo Gym Collection](https://huggingface.co/collections/nvidia/nemo-gym).

This dataset is ready for commercial use.

## Dataset Owner(s):
NVIDIA Corporation

## Dataset Creation Date:
October 2025

## License/Terms of Use: 
CC BY 4.0

## Intended Usage:
To be used with [NeMo Gym](https://github.com/NVIDIA-NeMo/Gym) for post-training LLMs. 

## Dataset Characterization
Data Collection Method<br>
* Seed [Synthetic] <br>
* Prompts [Synthetic] <br>


Labeling Method<br>
* [Synthetic] <br>

## Dataset Format
Text Only, Compatible with [NeMo Gym](https://github.com/NVIDIA-NeMo/Gym)

## Dataset Quantification
Record Count: Train: 9437 prompts, Validation: 512 prompts (Total 9949 prompts).
Feature Count: 4 (responses_create_params, schema_type, schema_fields_count)
Measurement of Total Data Storage: Train: 86.77 MiB, Validation: 4.70 MiB(Total 91.47 MiB)

## Reference(s):
[NeMo Gym](https://github.com/NVIDIA-NeMo/Gym)


## Ethical Considerations:
NVIDIA believes Trustworthy AI is a shared responsibility and we have established policies and practices to enable development for a wide array of AI applications.  When downloaded or used in accordance with our terms of service, developers should work with their internal model team to ensure this model meets requirements for the relevant industry and use case and addresses unforeseen product misuse.   
Please report model quality, risk, security vulnerabilities or NVIDIA AI Concerns [here](https://www.nvidia.com/en-us/support/submit-security-vulnerability/).