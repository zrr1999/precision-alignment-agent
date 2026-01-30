---
name: just-workflow
description: |
  Use Justfile commands to execute some workflows. Commands are prefixed with agentic.
  When in doubt, run `just` with no arguments to list all executable commands and their parameters.
---

# Just Workflow Skill

## Usage

- **List commands**: Run `just` with no arguments to show all recipes and their parameters.
- **Use only `agentic-` recipes**: Those are for agents; other recipes are for human use.
- **On failure**: Check the error output, then verify paths and environment variables.
