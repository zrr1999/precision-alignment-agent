# Paddle Pilot

This prompt has **two distinct usage modes**:

1. Using this project as a **tool** to perform Paddle development tasks (precision alignment, bug fixing, etc.).
2. **Developing or evolving this project itself** (changing agents, skills, tools, workflows, etc.).

The instructions below are split accordingly.

---

## 1. Using this project as a Paddle development tool

When you are performing **Paddle development tasks** (precision alignment, bug fixing, etc.), you **must** follow these rules:

1. **Do not modify agent definitions, skills, or project configuration during the task workflow.**

   - If you need to update these, do it **only after** the current task is fully completed, in a separate workflow.

2. If you need reference information to guide the process, you should:
   - Read the relevant documents **before** starting the task.
   - During the task itself, focus exclusively on the work.

---

## 2. Developing the paddle-pilot project itself

When you are **developing, refactoring, or extending this project** (for example, editing agents in `roles/`, skills, tools, or project configuration), the goal is to improve this repository as a tool.

In this mode:

1. **You are not required to follow the workflow described in `precision-alignment.md`.**
2. You **may** read and modify any project files as needed.

---

## Architecture Overview

The system uses a **flat orchestration** model: a single Main Agent (Orchestrator) directly coordinates all sub-agents.

```
Main Agent (Orchestrator)
  ├── @tracer          Code tracing (read-only)
  ├── @researcher      PR prior art (read-only)
  ├── @aligner         Code changes (write)
  ├── @builder         Build + smoke test + commit (bash)
  ├── @validator       Precision test (bash)
  └── @reviewer        Final review + PR (bash+git)
```

There is also a `precision-analysis` orchestrator (`roles/precision-analysis.md`) which delegates only to `@tracer` and `@researcher` for read-only analysis.

There is no intermediate planning layer. The Main Agent reads knowledge, plans the fix strategy, orchestrates the fix-validate loop (Aligner → Builder → Validator), and makes all strategic decisions with full session context.

---

## Adapter Pattern

Agent definitions are maintained in a **platform-agnostic canonical format** under `roles/` (YAML frontmatter + Markdown prompt), and platform-specific configurations (`.opencode/`, `.claude/`) are **generated** by [role-forge](https://github.com/zrr1999/role-forge). Generation is configured in `roles.toml`.

### Editing agents

1. Edit the canonical definition in `roles/{name}.md` (YAML frontmatter = metadata, body = prompt)
2. Run `just adapt` to regenerate platform-specific configs
3. **Do not edit `.opencode/agents/*.md` or `.claude/agents/*.md` directly** — they are generated artifacts

### Adding a new adapter target

Add a new `[targets.{platform}]` section to `roles.toml` with the appropriate model mappings and output directory. Then run `just adapt`.
