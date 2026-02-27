# Precision Alignment Agent

This prompt has **two distinct usage modes**:

1. Using this project as a **tool** to perform precision alignment work.
2. **Developing or evolving this project itself** (changing agents, skills, tools, workflows, etc.).

The instructions below are split accordingly.

---

## 1. Using this project as a precision alignment tool

When you are performing **precision alignment work**, you **must** follow these rules:

1. **Do not read or modify the `docs/` directory or any of its contents during the precision alignment workflow.**

   - This includes, but is not limited to: design docs, guides, examples, and any other files under `docs/`.
   - If you need to update documentation, you must do it **only after** the current precision alignment task is fully completed, in a separate, explicit documentation update workflow.

2. If you need information from documentation to guide the precision alignment process, you should:
   - Read the relevant documents **before** starting the precision alignment task.
   - Take notes or extract the needed information in advance.
   - During the precision alignment task itself, **do not access or modify** any content under `docs/` again.

---

## 2. Developing the precision-alignment-agent project itself

When you are **developing, refactoring, or extending this project** (for example, editing agents in `.opencode/agents`, skills, tools, or project configuration), the goal is to improve this repository as a tool.

In this mode:

1. **You are not required to follow the workflow described in `precision-alignment.md`.**
2. You **may** read and modify `docs/` and other project files as needed.

---

## Architecture Overview

The system uses a **flat orchestration** model: a single Main Agent (defined in `precision-alignment.md` + `opencode.json`) directly coordinates all sub-agents.

```
Main Agent (Orchestrator, claude-opus-4.6)
  ├── @explorer      Code tracing (read-only)
  ├── @learner       PR prior art (read-only)
  ├── @aligner       Code changes (write)
  ├── @diagnostician Build + smoke test + commit (bash)
  ├── @validator     Precision test (bash)
  └── @reviewer      Final review + PR (bash+git)
```

There is no intermediate planning layer. The Main Agent reads knowledge, plans the fix strategy, drives both the AD loop (Aligner → Diagnostician) and the PV loop (fix → Validator), and makes all strategic decisions with full session context.
