# Bug-Fix Agent Design

## Background

The paddle-pilot currently supports two workflows:

1. **Precision Alignment** (`@precision-alignment`) — Full fix loop aligning Paddle with PyTorch.
2. **Precision Analysis** (`@precision-analysis`) — Read-only code exploration.

We need to extend the system to support **large tensor** and **0-size tensor** bug fixes. These are fundamentally different from precision alignment:

- **Nature**: Crash/error fixes + behavioral alignment (not numeric precision).
- **Root cause**: Paddle-side bugs (index overflow, missing guards, unhandled edge cases), not PyTorch comparison gaps.
- **Key challenge**: Diagnosing *why* the crash happens, not *what* the correct value is.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Architecture | New `@bug-fix` orchestrator (Approach A) | Clean separation, no pollution of precision-alignment flow |
| Debug capability | New `@debugger` specialist with `paddle-debug` skill | Runtime investigation needs different tools than static tracing |
| Test tool for bug-fix | tensor-spec | Process isolation (CUDA crash safe), structured output, framework-agnostic |
| Test tool for precision | PaddleAPITest (unchanged) | Proven, large existing config library |
| Generalization level | Small step — reuse existing specialists | Only two scenarios; avoid over-abstraction |
| Reviewer PR format | `paddle-pull-request` skill (enforced) | Already updated in reviewer.md |

## Architecture

```
@paddle-agent (Router — 3 routes)
  │
  ├─ "精度对齐" → @precision-alignment (unchanged)
  │     ├── @tracer (Paddle + PyTorch)
  │     ├── @researcher
  │     ├── @aligner → @builder → @validator → @benchmarker
  │     ├── @optimizer
  │     └── @reviewer
  │
  ├─ "只读分析" → @precision-analysis (unchanged)
  │     ├── @tracer
  │     └── @researcher
  │
  └─ "Bug 修复" → @bug-fix (NEW)
        ├── @tracer          Reuse: static Paddle-side code tracing
        ├── @researcher      Reuse: find related PRs/issues
        ├── @debugger        NEW: runtime debugging, repro, root cause analysis
        ├── @aligner         Reuse: code changes based on debugger's analysis
        ├── @builder         Reuse: build + smoke test
        ├── @validator       Reuse (extended): tensor-spec paddleonly + accuracy
        └── @reviewer        Reuse: PR submission (paddle-pull-request skill)
```

## New Files

| File | Type | Description |
|------|------|-------------|
| `roles/bug-fix.md` | NEW | Bug-fix orchestrator role definition |
| `roles/specialists/debugger.md` | NEW | Debugger specialist with paddle-debug skill |

## Modified Files

| File | Change |
|------|--------|
| `roles/paddle-agent.md` | Add `@bug-fix` route + routing signals |
| `roles/specialists/validator.md` | Add tensor-spec test modes (paddleonly, accuracy) |
| `Justfile` | Add agentic commands for tensor-spec integration |

## Unchanged Files

All other specialists (aligner, builder, reviewer, tracer, researcher, optimizer, benchmarker) remain unchanged.

## Detailed Design

### 1. paddle-agent Routing Updates

New routing entry:

| User Intent | Route to |
|-------------|----------|
| Fix crash, fix large tensor, fix 0-size tensor, fix bug | `@bug-fix` |

Routing signals for `@bug-fix`:

- "修 bug", "crash", "报错", "fix crash", "fix error", "大 tensor", "large tensor", "0-size", "zero-size", "segfault", "CUDA error"
- User describes a crash, error, or edge-case failure (not a precision mismatch)

New required/optional inputs:

| Input | Description | Default |
|-------|-------------|---------|
| `api_name` | Target API | **Required** |
| `bug_type` | `large-tensor` / `0-size` / `crash` / `general` | Inferred from context |
| `error_config` | PaddleAPITest error config file (optional) | None |
| `tensor_spec_path` | Path to tensor-spec | `$TENSOR_SPEC_PATH` or `/workspace/tensor-spec` |

### 2. bug-fix Orchestrator (roles/bug-fix.md)

#### Phase 1: Explore (parallel)

Launch in parallel:

1. `@tracer` with `paddle_path` + `api_name` → Paddle call chain report
2. `@researcher` with `api_name` → related PRs, issues, fix patterns

Orchestrator reads `knowledge/` and `.paddle-pilot/memory/` for domain context.

**Key difference from precision-alignment**: No PyTorch tracing. This is a Paddle-side investigation.

#### Phase 2: Debug (NEW — core phase)

`@debugger` receives:

- Tracer's call chain report
- Error configs / crash logs (if provided by user)
- Bug type (large-tensor / 0-size / etc.)
- `tensor_spec_path` for running validation

`@debugger` produces:

- Minimal reproduction script
- Root cause analysis report (`.paddle-pilot/sessions/{api_name}/debugger/analysis.md`)
- Specific fix recommendations (which file, which function, what logic to change)

The debugger follows the `paddle-debug` skill workflow:

1. Construct minimal repro
2. Multi-hypothesis investigation with observation points
3. Runtime analysis (print, assert, CPU/GPU comparison)
4. Write analysis report before recommending any fix

#### Phase 3: Fix & Validate Loop (max 5 iterations)

Each iteration:

1. **@aligner**: Receives debugger's analysis report + specific fix instructions
2. **@builder**: Build Paddle, run smoke test
3. **@validator**: Two-stage validation using tensor-spec:
   - **Stage A — paddleonly**: `tensor-spec run --backend paddle --case '...'`
     - Ensures the API doesn't crash / segfault / CUDA error
     - Must pass before proceeding to Stage B
   - **Stage B — accuracy** (if paddleonly passes): `tensor-spec accuracy --backend-a paddle --backend-b torch --case-file ...`
     - Cross-framework comparison for behavioral correctness
4. **Assess result** (orchestrator):
   - Both stages pass → Phase 4
   - Paddleonly fails → feed error back to @debugger for re-analysis
   - Accuracy fails → feed diff back to @aligner for adjustment

#### Phase 4: Review

`@reviewer` with standard flow → PR via `paddle-pull-request` skill.

### 3. Debugger Specialist (roles/specialists/debugger.md)

```yaml
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
```

#### Responsibilities

- Construct minimal reproduction scripts
- Run the API with observation points (print, assert)
- Compare behavior across CPU/GPU, different shapes
- Write structured analysis report
- Provide specific fix recommendations to @aligner

#### Boundary with @tracer

- `@tracer`: Static analysis — reads source code, traces call paths, never runs code
- `@debugger`: Dynamic analysis — runs code, reproduces bugs, observes runtime behavior

### 4. Validator Extensions

The validator currently only supports PaddleAPITest precision tests. Extend it with tensor-spec capabilities:

#### New Justfile Commands

```just
# Generate 0-size test cases from existing configs
agentic-gen-0size-cases PADDLEAPITEST_PATH API_NAME OUTPUT_FILE:
    cd {{PADDLEAPITEST_PATH}} && python tester/api_config/to_0_size_config.py ...

# Generate large-tensor test cases from existing configs
agentic-gen-bigtensor-cases PADDLEAPITEST_PATH API_NAME OUTPUT_FILE:
    cd {{PADDLEAPITEST_PATH}} && python tester/api_config/to_big_size_config.py ...

# Run tensor-spec paddleonly test (single backend, crash detection)
agentic-run-tensorspec-paddleonly TENSOR_SPEC_PATH CASE_FILE VENV_PATH LOG_DIR:
    cd {{TENSOR_SPEC_PATH}} && uv run tensor-spec run \
      --backend paddle \
      --case-file {{CASE_FILE}} \
      --python-a {{VENV_PATH}}/bin/python \
      > {{LOG_DIR}}/paddleonly.jsonl

# Run tensor-spec accuracy test (dual backend comparison)
agentic-run-tensorspec-accuracy TENSOR_SPEC_PATH CASE_FILE VENV_PATH LOG_DIR:
    cd {{TENSOR_SPEC_PATH}} && uv run tensor-spec accuracy \
      --backend-a paddle --backend-b torch \
      --case-file {{CASE_FILE}} \
      --python-a {{VENV_PATH}}/bin/python \
      --log-file {{LOG_DIR}}/accuracy.jsonl
```

#### Validator Role Update

Add to validator.md:

- Knowledge of tensor-spec CLI commands
- Two-stage validation logic (paddleonly first, then accuracy)
- Structured result parsing from JSON Lines logs
- New test status types: `PADDLE_ERROR`, `CUDA_ERROR`, `OOM_ERROR`

### 5. Case Format Bridging

PaddleAPITest uses Paddle-specific case format:
```
paddle.abs(Tensor(shape=[0, 100], dtype=float32))
```

tensor-spec uses framework-agnostic format:
```
abs(x=Tensor.float32((0, 100)))
```

For the bug-fix workflow:

- Config generation still uses PaddleAPITest's `to_0_size_config` / `to_big_tensor_config` (mature, covers hundreds of APIs)
- A conversion step transforms PaddleAPITest configs → tensor-spec case format
- Alternatively, tensor-spec cases can be written directly for specific APIs

This bridging can be a simple script or Justfile command. Not a priority for v1 — the debugger and validator can work with either format.

## Non-Goals (v1)

- Migrating precision-alignment to tensor-spec (future work)
- Auto-generating tensor-spec cases from scratch (use PaddleAPITest generators)
- Supporting bug types beyond large-tensor / 0-size / crash

## Success Criteria

1. `just start {api_name}` → user says "fix 0-size crash" → paddle-agent routes to `@bug-fix`
2. `@debugger` produces a root cause analysis with minimal repro
3. `@aligner` fixes the code based on debugger's report
4. `@validator` confirms no crash (paddleonly) + correct behavior (accuracy) via tensor-spec
5. `@reviewer` creates PR following Paddle official template
