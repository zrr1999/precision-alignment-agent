# CMake Build Flags Reference

## Default Flags (used in `paddle-build.sh`)

| Flag | Value | Purpose |
|------|-------|---------|
| `PADDLE_VERSION` | `0.0.0` | Dev version marker |
| `CMAKE_EXPORT_COMPILE_COMMANDS` | `ON` | Generate `compile_commands.json` for IDEs |
| `CUDA_ARCH_NAME` | `Auto` | Detect GPU arch automatically |
| `WITH_GPU` | `ON` | Enable CUDA support |
| `WITH_DISTRIBUTE` | `ON` | Enable distributed training |
| `WITH_UNITY_BUILD` | `OFF` | Disable unity build (slower but more reliable) |
| `WITH_TESTING` | `OFF` | Skip test targets (faster build) |
| `CMAKE_BUILD_TYPE` | `Release` | Optimized build |
| `WITH_CINN` | `ON` | Enable CINN compiler |
| `GNinja` | - | Use Ninja generator |
| `PY_VERSION` | `3.12` | Python version |

## Common Adjustments

### Build for specific GPU arch (faster build)
Replace `CUDA_ARCH_NAME=Auto` with specific arch:
- `CUDA_ARCH_NAME=Ampere` — A100, A10, RTX 30xx
- `CUDA_ARCH_NAME=Hopper` — H100

### Debug build
Change `CMAKE_BUILD_TYPE=Release` to `CMAKE_BUILD_TYPE=Debug`

### Disable CINN (faster build)
Set `WITH_CINN=OFF` — saves significant build time if CINN is not needed.

### Reduce parallelism (OOM during build)
Edit the ninja command: `ninja -j4` instead of `ninja -j$(nproc)`
