---
name: paddle-build
description: Build and install PaddlePaddle in development venv. Use when setting up environment, rebuilding after code changes, or installing Paddle wheel.
---

# Paddle Build Pipeline

Build environment setup and Paddle compilation for development worktrees.

**All commands must be run from the agent project root** (the directory containing the justfile). Pass paths as parameters.

## Venv Setup

Create or update a relocatable venv with all Paddle dependencies (torch, numpy, etc.):

```bash
bash skills/paddle-build/scripts/venv-setup.sh PADDLE_PATH
```

- Creates `.venv` under `PADDLE_PATH` if not present
- Installs `python/requirements.txt` + runtime deps (torch 2.9.1, numpy <2.0, etc.)
- Idempotent — safe to re-run

## Build and Install

Full cmake + ninja build, then install wheel into the venv:

```bash
bash skills/paddle-build/scripts/paddle-build.sh PADDLE_PATH
```

- Runs cmake with GPU, CINN, Ninja, Python 3.12
- Builds with all available cores (`ninja -j$(nproc)`)
- Installs the built wheel via `uv pip install --no-deps --force-reinstall`

For cmake flag details, see [references/cmake-flags.md](references/cmake-flags.md).

## Parameters

| Parameter | Description |
|-----------|-------------|
| `PADDLE_PATH` | Absolute path to the Paddle source tree (worktree). Venv is at `PADDLE_PATH/.venv` |

## Typical Workflow

1. After code changes by Aligner: rebuild → `paddle-build.sh`
2. First-time setup: `venv-setup.sh` → `paddle-build.sh`
3. Incremental rebuild: just `paddle-build.sh` (ninja handles incremental)

## Build Failure Triage

- **Simple errors** (missing symbol, typo): fix in Aligner, rebuild
- **Complex errors** (cmake config, CUDA arch): check [references/cmake-flags.md](references/cmake-flags.md)
- **OOM during build**: reduce parallelism — edit `ninja -j$(nproc)` to `ninja -j4`

## Notes

- Venv is **relocatable** (`--relocatable` flag) — survives directory moves
- Build artifacts are under `PADDLE_PATH/build/` — preserved across rebuilds
- The venv includes `tensor_spec` for bug-fix validation workflows
