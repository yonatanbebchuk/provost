---
dataset_info:
  features:
  - name: prompt
    dtype: string
  splits:
  - name: train
    num_bytes: 89473
    num_examples: 1000
  download_size: 63899
  dataset_size: 89473
configs:
- config_name: default
  data_files:
  - split: train
    path: data/train-*
license: mit
task_categories:
- question-answering
- text-generation
language:
- en
tags:
- rl
- rl-environment
- verifiers
size_categories:
- 1K<n<10K
---
# Reverse-Text-RL

A small, scrappy RL dataset used in [prime-rl](https://github.com/PrimeIntellect-ai/prime-rl)'s CI to debug RL training asking a model to reverse small sentences character-by-character. Follows the general format of [PrimeIntellect/Reverse-Text-SFT](https://huggingface.co/datasets/PrimeIntellect/Reverse-Text-SFT)

The following script was used to generate the dataset.

```python
from datasets import Dataset, load_dataset

dataset = load_dataset("willcb/R1-reverse-wikipedia-paragraphs-v1-1000", split="train")
prompt = "Reverse the text character-by-character. Put your answer in <reversed_text> tags."
sentences_list = dataset.map(lambda example: {"sentences": [s for s in example["prompt"][1]["content"].split(". ") if 5 <= len(s.split(" ")) <= 20]})["sentences"]
sentences = [sentence for sentences in sentences_list for sentence in sentences] # Flatten
completions = [s[::-1] for s in sentences] # Reverse to get ground truth

examples = []
for sentence, completion in zip(sentences, completions):
    examples.append({"prompt": sentence})

small_rl = Dataset.from_list(examples).select(range(1000, 2000))
```