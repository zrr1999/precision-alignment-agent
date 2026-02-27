---
name: precision-analysis
description: >
  Precision Analysis (read-only). Explore-only mode for research
  and code tracing without making any changes.
role: primary

model:
  tier: reasoning
  temperature: 0.2

prompt_file: ../precision-analysis.md

skills:
  - paa-just-workflow
  - paa-knowledge-curation

capabilities:
  - read-code
  - web-read
  - bash:
      - "ls*"
      - "cat*"
      - "head*"
      - "tail*"
      - "grep*"
      - "wc*"
      - "pwd"
      - "date*"
      - "echo*"
      - "git status*"
      - "git log*"
      - "git diff*"
      - "git rev-parse*"
      - "git branch*"
  - delegate:
      - explorer
      - learner
---

Prompt content is in [precision-analysis.md](../precision-analysis.md).
