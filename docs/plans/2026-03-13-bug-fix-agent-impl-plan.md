# Bug-Fix Agent Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend paddle-pilot with a `@bug-fix` orchestrator that handles large-tensor, 0-size tensor, and crash fixes via a new `@debugger` specialist and tensor-spec integration.

**Architecture:** New `@bug-fix` orchestrator sits alongside existing `@precision-alignment` and `@precision-analysis`. It reuses 5 existing specialists (tracer, researcher, aligner, builder, reviewer) and adds 1 new one (`@debugger`). Validation uses tensor-spec (process-isolated) instead of PaddleAPITest. paddle-agent gains a third routing path.

**Tech Stack:** Markdown role definitions (YAML frontmatter), Justfile commands, role-forge for platform config generation, tensor-spec CLI for testing.

**Design doc:** `docs/plans/2026-03-13-bug-fix-agent-design.md`

---

### Task 1: Create debugger specialist role

**Files:**
- Create: `roles/specialists/debugger.md`

**Step 1: Write the debugger role definition**

Create `roles/specialists/debugger.md` with this exact content:

```markdown
---
name: debugger
description: >
  Bug Debugger. Reproduces crashes, investigates root causes with
  runtime observation, and produces analysis reports with fix recommendations.
role: subagent

model:
  tier: reasoning
  temperature: 0.1

skills:
  - paddle-debug
  - just-workflow

capabilities:
  - read
  - write
  - safe-bash
  - bash:
      - "python*"
      - "just"
      - "just agentic*"
      - "uv*"
---

# D - Bug Debugger

Reproduce crashes, investigate root causes with runtime observation, and produce analysis reports with specific fix recommendations.

**You MUST follow the `paddle-debug` skill exactly.** The skill defines the full debugging workflow: minimal repro, multi-hypothesis investigation, observation points, and analysis report structure.

## Required Inputs

- **`api_name`**: Target API (e.g. `paddle.abs`)
- **`paddle_path`**: Paddle source code path
- **`venv_path`**: Virtual environment path
- **`bug_type`**: One of `large-tensor`, `0-size`, `crash`, `general`
- **Tracer report**: Call chain report from @tracer (`.paddle-pilot/sessions/{api_name}/tracer/`)
- **Error context**: Crash logs, error configs, or user-provided failure description

Optional:
- **`tensor_spec_path`**: Path to tensor-spec for running validation
- **Previous validator failure patterns** (for iterations > 1)

## Workflow

Follow the `paddle-debug` skill phases:

### 1. Construct Minimal Reproduction

- Based on `bug_type`, create a standalone Python script:
  - `large-tensor`: Use shape that exceeds INT32 numel (>2^31)
  - `0-size`: Use shape with a 0 dimension (e.g. `[0, 100]` or `[3, 0, 5]`)
  - `crash` / `general`: Reproduce from the error context provided
- Script must be runnable with: `python reproduce_{api_name}.py`
- Fixed random seed, minimal dependencies
- Save to `.paddle-pilot/sessions/{api_name}/debugger/reproduce.py`

### 2. Multi-Hypothesis Investigation

- Read the tracer's call chain report to understand the code path
- List **at least 3 hypotheses** for the crash root cause. Common patterns:
  - `large-tensor`: int32 index overflow, numel exceeds INT_MAX, grid/block dimension overflow, memory allocation failure
  - `0-size`: missing empty-tensor guard, division by zero in shape computation, nullptr dereference on empty buffer, kernel launch with 0 threads
- For each hypothesis, add observation points (print, assert) and run the repro script
- Record which hypotheses are confirmed/eliminated

### 3. Root Cause Analysis Report

Write to `.paddle-pilot/sessions/{api_name}/debugger/analysis.md`:

```
## Root Cause Analysis: {api_name} ({bug_type})

### Reproduction
- Command: `python reproduce_{api_name}.py`
- Error: [exact error message]

### Hypotheses Tested
1. [hypothesis] — [confirmed/eliminated] — [evidence]
2. ...

### Root Cause
[Precise description of what's wrong and where]

### Fix Recommendations
For each fix item:
- **File**: `exact/path/to/file.cu:line`
- **Function**: `exact_function_name`
- **Current behavior**: [what happens now]
- **Expected behavior**: [what should happen]
- **Suggested change**: [specific code change description]

### Affected Related APIs
[List any other APIs that share the same kernel/code path]
```

## Boundary with @tracer

- `@tracer`: **Static** — reads source code, traces call paths, never runs any code
- `@debugger` (you): **Dynamic** — runs code, reproduces bugs, adds observation points, observes runtime behavior

## Constraints

- Bash: `python*`, `just`, `just agentic*`, `uv*` only.
- Write analysis reports and repro scripts only. Do NOT modify Paddle source code — that's @aligner's job.
- Do NOT spawn sub-agents.
- If the bug cannot be reproduced, write a report explaining what was tried and why, then suggest environment/setup steps needed.
```

**Step 2: Verify the file was created correctly**

Run: `head -5 roles/specialists/debugger.md`
Expected: YAML frontmatter starting with `---` and `name: debugger`

**Step 3: Commit**

```bash
git add roles/specialists/debugger.md
git commit -m "feat: add debugger specialist role for bug-fix workflow"
```

---

### Task 2: Create bug-fix orchestrator role

**Files:**
- Create: `roles/bug-fix.md`

**Step 1: Write the bug-fix orchestrator role**

Create `roles/bug-fix.md` with this exact content:

```markdown
---
name: bug-fix
description: >
  Bug-Fix Orchestrator. Plans, coordinates, and drives the bug-fix
  workflow for large-tensor, 0-size, and crash issues by invoking
  specialized sub-agents.
role: all

model:
  tier: coding
  temperature: 0.2

skills:
  - just-workflow
  - knowledge-curation

capabilities:
  - read
  - write
  - web-access
  - safe-bash
  - delegate:
      - specialists/tracer
      - specialists/researcher
      - specialists/debugger
      - specialists/aligner
      - specialists/builder
      - specialists/validator
      - specialists/reviewer
---

# Bug-Fix Orchestrator

You are the **Bug-Fix Orchestrator**. Your sole job is to **plan, coordinate, and delegate** the bug-fix workflow for large-tensor, 0-size tensor, and crash issues. You own the full session context and make all strategic decisions.

**You are a coordinator, not an executor.** You MUST delegate all implementation work to the appropriate sub-agent. Your direct actions are limited to: reading files for decision-making, writing session reports/plans, and invoking sub-agents.

## Architecture

```
You (Orchestrator)
  ├── @tracer         Code tracing — Paddle side only (read-only)
  ├── @researcher     PR prior art (read-only)
  ├── @debugger       Runtime debugging, repro, root cause analysis (NEW)
  ├── @aligner        Code changes based on debugger's analysis (write)
  ├── @builder        Build + smoke test (bash)
  ├── @validator      Validation — tensor-spec paddleonly + accuracy (bash)
  └── @reviewer       Final review + PR (bash+git)
```

## Required Inputs

| Input | Description |
|-------|-------------|
| `api_name` | Target API (e.g. `paddle.abs`) |
| `paddle_path` | Paddle source code path |
| `pytorch_path` | PyTorch source code path (for accuracy comparison only) |
| `paddletest_path` | PaddleTest repo (functional tests) |
| `paddleapitest_path` | PaddleAPITest repo (config generation) |
| `tensor_spec_path` | tensor-spec tool path |
| `venv_path` | Virtual environment path |
| `bug_type` | `large-tensor` / `0-size` / `crash` / `general` |
| `error_config` | Error config file or crash description (optional) |

## Session Setup

At workflow start, create the session directory:
- Write a brief context summary to `.paddle-pilot/sessions/{api_name}/context.md` containing all inputs and task description.
- Sub-agents write their reports under `.paddle-pilot/sessions/{api_name}/...`.

## Workflow

### Phase 1: Explore (parallel)

**Goal**: Understand the Paddle-side implementation + gather prior art.

Launch **in parallel**:
1. `@tracer` with `paddle_path` + `api_name` → Paddle implementation report
2. `@researcher` with `api_name` + `bug_type` keywords → prior art from existing Paddle PRs

**Also do yourself** (while sub-agents are running):
- Read `knowledge/commons/` for domain knowledge
- Search `.paddle-pilot/memory/` for relevant topic files
- Check if `bug_type` relates to known patterns (e.g. int32 overflow for large tensors, empty guard for 0-size)

**Key difference from precision-alignment**: No PyTorch tracing. This is a Paddle-side investigation.

### Phase 2: Debug

**Goal**: Reproduce the bug and identify the root cause.

`@debugger` with:
- Tracer's call chain report
- Error configs / crash logs (if provided)
- `bug_type`, `api_name`, `paddle_path`, `venv_path`
- `tensor_spec_path` (for running validation)

Read the debugger's analysis report. It should contain:
- Minimal reproduction script
- Root cause analysis
- Specific fix recommendations (files, functions, changes)

If the debugger cannot reproduce: ask user for more context or adjust environment.

### Phase 3: Fix & Validate Loop (max 5 iterations)

**Goal**: Implement fixes and validate they resolve the crash + maintain correctness.

Each iteration:

1. **@aligner**: Provide exact instructions from debugger's analysis:
   - Which file(s) and function(s) to modify
   - What bug to fix (e.g. "add 0-size tensor guard before kernel launch")
   - Expected outcome
   - If iteration > 1: include @validator failure patterns from previous iteration

2. **@builder**: After Aligner completes:
   - Build Paddle (`just agentic-paddle-build-and-install`)
   - Run smoke test (`just agentic-run-paddle-unittest`)
   - If build fails: Builder fixes directly or report back for re-invoke @aligner
   - On success: commit with `[PADDLE-PILOT]` prefix

3. **@validator**: After build + smoke pass, **two-stage validation**:
   - **Stage A — paddleonly**: Run `just agentic-run-tensorspec-paddleonly` with the repro cases
     - Ensures the API doesn't crash / segfault / CUDA error
     - **Must pass before Stage B**
   - **Stage B — accuracy**: Run `just agentic-run-tensorspec-accuracy` with the same cases
     - Cross-framework comparison for behavioral correctness
     - Uses Paddle vs PyTorch comparison

4. **Assess result** (this is the ONLY step you do yourself):
   - **Both stages pass** → Phase 4
   - **Paddleonly fails** → feed error back to @debugger for re-analysis (counts as iteration)
   - **Accuracy fails** → feed diff back to @aligner for adjustment (counts as iteration)
   - **After 5 iterations with no meaningful progress** → Phase 4 with failure report

### Phase 4: Review

**Goal**: Independent verification and PR creation.

`@reviewer` with:
- `api_name`, `venv_path`, all paths
- Whether Phase 3 ended in success, partial success, or failure
- Summary of what was fixed and what gaps remain
- `bug_type` for PR categorization

Reviewer independently verifies and produces PR or failure report.

## Sub-Agent Invocation Rules

1. **Always pass**: `api_name`, `venv_path`, `paddle_path`, and relevant paths.
2. **Be specific**: Never send vague tasks. Always include exact files, functions, error messages.
3. **Parallel when independent**: @tracer + @researcher can run in parallel. Others are sequential.
4. **Read sub-agent reports**: Read files under `.paddle-pilot/sessions/{api_name}/` to make decisions.
5. **Pass debugger's analysis to aligner**: The debugger's report is the primary input for @aligner in this workflow.

## Delegation Boundaries

**You MUST NOT do the following yourself — always delegate:**

| Action | Delegate to |
|--------|------------|
| Trace or analyze Paddle source code | @tracer |
| Search for prior art or existing PRs | @researcher |
| Reproduce bugs, runtime investigation | @debugger |
| Modify source code | @aligner |
| Build Paddle, run smoke tests, commit | @builder |
| Run tensor-spec validation | @validator |
| Create PR or generate final report | @reviewer |

**You MAY do directly:**
- Read files under `.paddle-pilot/sessions/`, `knowledge/`, `.paddle-pilot/memory/`
- Write session plans and context files under `.paddle-pilot/sessions/`
- Assess sub-agent results and decide next steps

## Rules

- **You are a coordinator** — Plan and delegate.
- **No PyTorch deep-dive** — This workflow focuses on Paddle-side bugs. PyTorch is only used for accuracy comparison in validation.
- **Debugger first, aligner second** — Never send @aligner to fix code without @debugger's analysis.
- **Two-stage validation** — Always paddleonly first, accuracy second.
- **Track your phase** — Always know which phase you're in (1-4).
- **Success** = @reviewer produces PR. **Failure** = @reviewer produces failure report.
```

**Step 2: Verify file structure**

Run: `head -10 roles/bug-fix.md`
Expected: YAML frontmatter with `name: bug-fix`

**Step 3: Commit**

```bash
git add roles/bug-fix.md
git commit -m "feat: add bug-fix orchestrator role"
```

---

### Task 3: Update paddle-agent routing

**Files:**
- Modify: `roles/paddle-agent.md`

**Step 1: Add bug-fix to delegate list in frontmatter**

In `roles/paddle-agent.md`, replace the capabilities block:

```yaml
capabilities:
  - read
  - web-access
  - safe-bash
  - delegate:
    - precision-alignment
    - precision-analysis
```

With:

```yaml
capabilities:
  - read
  - web-access
  - safe-bash
  - delegate:
    - precision-alignment
    - precision-analysis
    - bug-fix
```

**Step 2: Update the routing description**

Replace the line:

```markdown
- `@precision-alignment` — Full workflow: explore, plan, fix, validate, and create PR.
- `@precision-analysis` — Read-only: explore and analyze without making any changes.
```

With:

```markdown
- `@precision-alignment` — Full workflow: explore, plan, fix, validate, and create PR for precision gaps.
- `@precision-analysis` — Read-only: explore and analyze without making any changes.
- `@bug-fix` — Fix workflow for crashes, large-tensor issues, 0-size tensor issues, and other bugs.
```

**Step 3: Update the routing decision table**

Replace the existing routing table:

```markdown
| User Intent | Route to |
|-------------|----------|
| Fix precision, align with PyTorch, create PR | `@precision-alignment` |
| Investigate, understand, trace, compare, research | `@precision-analysis` |
| Unclear or ambiguous | Ask the user to clarify |
```

With:

```markdown
| User Intent | Route to |
|-------------|----------|
| Fix precision, align with PyTorch, create PR | `@precision-alignment` |
| Fix crash, large tensor, 0-size tensor, bug fix | `@bug-fix` |
| Investigate, understand, trace, compare, research | `@precision-analysis` |
| Unclear or ambiguous | Ask the user to clarify |
```

**Step 4: Add routing signals for bug-fix**

After the existing "Signals for `precision-analysis`" block, add:

```markdown
**Signals for `bug-fix`:**
- "修 bug", "crash", "报错", "fix crash", "fix error", "大 tensor", "large tensor", "0-size", "zero-size", "segfault", "CUDA error", "OOM"
- User describes a crash, error, or edge-case failure (not a precision mismatch)
- User provides error configs or crash logs
```

**Step 5: Add bug-fix inputs to the Required Inputs table**

Add these rows to the existing inputs table:

```markdown
| `bug_type` | Bug type: `large-tensor` / `0-size` / `crash` / `general` | Inferred from context |
| `tensor_spec_path` | tensor-spec tool path | `$TENSOR_SPEC_PATH` or `/workspace/tensor-spec` |
| `error_config` | Error config file or crash description | Optional |
```

**Step 6: Add delegation format for bug-fix**

After the existing delegation format blocks, add:

```markdown
**For `@bug-fix`:**
> Start bug-fix workflow for {api_name}.
> Bug type: {bug_type}. Additional context: {user_notes}.
> Error config: {error_config}.
> Inputs: paddle_path={paddle_path}, pytorch_path={pytorch_path},
> paddletest_path={paddletest_path}, paddleapitest_path={paddleapitest_path},
> tensor_spec_path={tensor_spec_path}, venv_path={venv_path}
```

**Step 7: Verify and commit**

Run: `grep -c "bug-fix" roles/paddle-agent.md`
Expected: At least 5 occurrences

```bash
git add roles/paddle-agent.md
git commit -m "feat: add bug-fix routing to paddle-agent"
```

---

### Task 4: Extend validator with tensor-spec support

**Files:**
- Modify: `roles/specialists/validator.md`

**Step 1: Update the description in frontmatter**

Replace:

```yaml
description: >
  Precision Validator. Runs PaddleAPITest precision validation,
  analyzes results, reports pass/fail patterns.
```

With:

```yaml
description: >
  Validator. Runs precision validation (PaddleAPITest) and bug-fix
  validation (tensor-spec paddleonly + accuracy). Analyzes results,
  reports pass/fail patterns.
```

**Step 2: Add tensor-spec section after the existing content**

Append before the `## Constraints` section:

```markdown
## tensor-spec Validation (for bug-fix workflow)

When invoked from the `@bug-fix` orchestrator, use tensor-spec instead of PaddleAPITest.

### Two-Stage Validation

**Stage A — paddleonly (crash detection):**

```bash
just agentic-run-tensorspec-paddleonly $TENSOR_SPEC_PATH $CASE_FILE $VENV_PATH $LOG_DIR
```

- Runs each case on Paddle only (no PyTorch comparison)
- Detects: crash, segfault, CUDA error, OOM
- **Must pass before Stage B**
- Parse results from JSON Lines log: look for `PADDLE_ERROR`, `CUDA_ERROR`, `OOM_ERROR` statuses

**Stage B — accuracy (behavioral correctness):**

```bash
just agentic-run-tensorspec-accuracy $TENSOR_SPEC_PATH $CASE_FILE $VENV_PATH $LOG_DIR
```

- Compares Paddle output against PyTorch output
- Detects: accuracy differences, shape mismatches, dtype mismatches
- Parse results from JSON Lines log: look for `ACCURACY_ERROR` status

### tensor-spec Result Statuses

| Status | Meaning |
|--------|---------|
| `pass` | Test case passed |
| `accuracy_error` | Output differs between backends |
| `paddle_error` | Paddle raised an exception |
| `torch_error` | PyTorch raised an exception (not a Paddle bug) |
| `cuda_error` | CUDA runtime error |
| `oom` | Out of memory |
| `error` | Other error |

### Report Format (tensor-spec)

Same structure as PaddleAPITest reports, but include:
- **Stage A results**: total, passed, crashed (paddle_error + cuda_error + oom)
- **Stage B results**: total, passed, accuracy_error
- **Crash patterns**: which shapes/dtypes/operations crash
- **Recommendation**: focused on crash fixes first, accuracy second
```

**Step 3: Update the Constraints section**

Replace:

```markdown
## Constraints

- Bash: permitted commands only. PaddleAPITest only. No spawning agents. Same config for before/after comparison.
```

With:

```markdown
## Constraints

- Bash: permitted commands only. PaddleAPITest or tensor-spec depending on workflow. No spawning agents. Same config for before/after comparison.
```

**Step 4: Commit**

```bash
git add roles/specialists/validator.md
git commit -m "feat: extend validator with tensor-spec support for bug-fix workflow"
```

---

### Task 5: Add Justfile agentic commands for tensor-spec

**Files:**
- Modify: `Justfile`

**Step 1: Add tensor-spec commands at the end of the Justfile**

Append these commands after the last existing recipe (`agentic-run-precision-cpu-test`):

```just
# Run tensor-spec paddleonly test (single backend, crash detection). For bug-fix validation Stage A.
agentic-run-tensorspec-paddleonly TENSOR_SPEC_PATH VENV_PATH CASE_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ LOG_DIR }}"
    cd "{{ TENSOR_SPEC_PATH }}"
    echo "Running tensor-spec paddleonly test..."
    echo "Case file: {{ CASE_FILE }}"
    echo "Log dir: {{ LOG_DIR }}"
    uv run tensor-spec run \
        --backend paddle \
        --case-file "{{ CASE_FILE }}" \
        --python-a "{{ VENV_PATH }}/bin/python" \
        --log-file "{{ LOG_DIR }}/paddleonly.jsonl" \
        --verbose || true
    echo "---"
    echo "Results: {{ LOG_DIR }}/paddleonly.jsonl"

# Run tensor-spec accuracy test (dual backend comparison). For bug-fix validation Stage B.
agentic-run-tensorspec-accuracy TENSOR_SPEC_PATH VENV_PATH CASE_FILE LOG_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ LOG_DIR }}"
    cd "{{ TENSOR_SPEC_PATH }}"
    echo "Running tensor-spec accuracy test..."
    echo "Case file: {{ CASE_FILE }}"
    echo "Log dir: {{ LOG_DIR }}"
    uv run tensor-spec accuracy \
        --backend-a paddle --backend-b torch \
        --case-file "{{ CASE_FILE }}" \
        --python-a "{{ VENV_PATH }}/bin/python" \
        --log-file "{{ LOG_DIR }}/accuracy.jsonl" \
        --verbose || true
    echo "---"
    echo "Results: {{ LOG_DIR }}/accuracy.jsonl"
```

**Step 2: Add the bugfix-start convenience command**

Add this after the `alignment-start` recipe (around line 323), before the internal recipes section:

```just
# 快速启动 Bug 修复流程
bugfix-start api_name bug_type="general" tool="opencode" additional_prompt="":
    #!/usr/bin/env bash
    set -euo pipefail

    PADDLE_PILOT_ROOT=$(pwd)

    PADDLE_PATH="${PADDLE_PATH:=.paddle-pilot/repos/Paddle}"
    PYTORCH_PATH="${PYTORCH_PATH:=.paddle-pilot/repos/pytorch}"
    PADDLETEST_PATH="${PADDLETEST_PATH:=.paddle-pilot/repos/PaddleTest}"
    PADDLEAPITEST_PATH="${PADDLEAPITEST_PATH:=.paddle-pilot/repos/PaddleAPITest}"
    TENSOR_SPEC_PATH="${TENSOR_SPEC_PATH:=/workspace/tensor-spec}"

    PADDLE_PATH="$(cd "$PADDLE_PATH" && pwd)"
    PYTORCH_PATH="$(cd "$PYTORCH_PATH" && pwd)"
    PADDLETEST_PATH="$(cd "$PADDLETEST_PATH" && pwd)"
    PADDLEAPITEST_PATH="$(cd "$PADDLEAPITEST_PATH" && pwd)"
    TENSOR_SPEC_PATH="$(cd "$TENSOR_SPEC_PATH" && pwd)"

    echo "PADDLE_PATH: $PADDLE_PATH"
    echo "PYTORCH_PATH: $PYTORCH_PATH"
    echo "PADDLETEST_PATH: $PADDLETEST_PATH"
    echo "PADDLEAPITEST_PATH: $PADDLEAPITEST_PATH"
    echo "TENSOR_SPEC_PATH: $TENSOR_SPEC_PATH"

    echo "Setting up worktree"
    mkdir -p .paddle-pilot/worktree
    cd $PADDLE_PATH
    git switch -c PAA/develop 2>/dev/null || git switch PAA/develop
    git pull upstream develop
    if [ -d "$PADDLE_PILOT_ROOT/.paddle-pilot/worktree/Paddle_{{ api_name }}" ]; then
        cd "$PADDLE_PILOT_ROOT/.paddle-pilot/worktree/Paddle_{{ api_name }}"
    else
        git worktree add $PADDLE_PILOT_ROOT/.paddle-pilot/worktree/Paddle_{{ api_name }} -b paddle-pilot/{{ api_name }}
    fi

    PADDLE_PATH=$PADDLE_PILOT_ROOT/.paddle-pilot/worktree/Paddle_{{ api_name }}
    VENV_PATH=$PADDLE_PATH/.venv
    echo "PADDLE_PATH: $PADDLE_PATH"

    cd $PADDLE_PATH
    just agentic-venv-setup $PADDLE_PATH
    just agentic-paddle-build-and-install $PADDLE_PATH

    echo "Successfully setup worktree and created venv"

    cd $PADDLE_PILOT_ROOT

    AGENT="bug-fix"
    PROMPT="Start bug-fix workflow for {{ api_name }}. \
        Bug type: {{ bug_type }}. \
        Additional context: {{ additional_prompt }}. \
        Inputs: paddle_path=$PADDLE_PATH, \
        pytorch_path=$PYTORCH_PATH, \
        paddletest_path=$PADDLETEST_PATH, \
        paddleapitest_path=$PADDLEAPITEST_PATH, \
        tensor_spec_path=$TENSOR_SPEC_PATH, \
        venv_path=$VENV_PATH"

    just _launch-agent "{{ tool }}" "$AGENT" "$PROMPT"
```

**Step 3: Verify Justfile syntax**

Run: `just --list 2>&1 | grep -E "(bugfix|tensorspec)"`
Expected: `bugfix-start`, `agentic-run-tensorspec-paddleonly`, `agentic-run-tensorspec-accuracy` listed

**Step 4: Commit**

```bash
git add Justfile
git commit -m "feat: add Justfile commands for bug-fix workflow and tensor-spec integration"
```

---

### Task 6: Regenerate platform configs and verify

**Files:**
- Generated: `.claude/agents/bug-fix.md`, `.claude/agents/specialists/debugger.md`
- Generated: `.opencode/agents/bug-fix.md`, `.opencode/agents/specialists/debugger.md`
- Generated: Updates to `.claude/agents/paddle-agent.md`, `.claude/agents/specialists/validator.md`, etc.

**Step 1: Run role-forge to regenerate all platform configs**

```bash
just adapt
```

Expected: `uvx role-forge render` succeeds without errors. New files appear under `.claude/agents/` and `.opencode/agents/`.

**Step 2: Verify the generated files exist**

```bash
ls -la .claude/agents/bug-fix.md .claude/agents/specialists/debugger.md
ls -la .opencode/agents/bug-fix.md .opencode/agents/specialists/debugger.md
```

Expected: All 4 files exist and are non-empty.

**Step 3: Spot-check generated content**

```bash
head -20 .claude/agents/bug-fix.md
head -20 .claude/agents/specialists/debugger.md
```

Expected: Claude-flavored agent definitions with correct model mapping (reasoning → opus for debugger, coding → sonnet for bug-fix).

**Step 4: No commit needed** — generated files are in `.gitignore`.

---

### Task 7: Final integration verification

**Step 1: Verify all role files parse correctly**

```bash
uvx role-forge render --dry-run 2>&1
```

Expected: No errors, all roles listed.

**Step 2: Verify routing completeness**

```bash
grep -c "bug-fix" roles/paddle-agent.md
grep -c "debugger" roles/bug-fix.md
grep -c "tensor-spec" roles/specialists/validator.md
grep -c "tensorspec" Justfile
```

Expected: All counts > 0.

**Step 3: Verify Justfile commands**

```bash
just --list | grep -E "bugfix|tensorspec"
```

Expected: 3 commands listed.

**Step 4: Final commit with all changes**

```bash
git log --oneline -5
```

Verify the commit history looks clean with 4-5 commits from this implementation.

No squash needed — each commit is a logical unit.
