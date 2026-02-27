---
name: precision-alignment
description: >
  Precision Alignment Orchestrator. Directly plans, coordinates, and drives
  the entire precision alignment workflow by invoking specialized sub-agents.
role: primary

model:
  tier: reasoning
  temperature: 0.2

prompt_file: ../precision-alignment.md

skills:
  - paa-just-workflow
  - paa-knowledge-curation

capabilities:
  - read-code
  - write-report
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
      - aligner
      - diagnostician
      - validator
      - reviewer
---

Prompt content is in [precision-alignment.md](../precision-alignment.md).
