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

When you are **developing, refactoring, or extending this project** (for example, editing agents in `.opencode/agents`, skills, tools like `paddle_apitest.ts`, or project configuration), the goal is to improve this repository as a tool.

In this mode:

1. **You are not required to follow the workflow described in `precision-alignment.md`.**  
   - That document describes how to use this project as a precision alignment tool, not how to develop the tool itself.
   - You may change, reorganize, or extend the implementation even if it temporarily diverges from the processes described in `precision-alignment.md`.

2. You **may** read and modify `docs/` (and other project files) as needed to support the evolution of this project, as long as you are not simultaneously running an actual precision alignment task as described in section 1.
