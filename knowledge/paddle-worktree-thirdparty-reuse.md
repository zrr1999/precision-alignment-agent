# Paddle Worktree 第三方依赖复用设计文档

> 解决 git worktree 场景下 Paddle cmake 重复下载/编译第三方依赖的问题，支持大规模并行构建。

## 1. 问题描述

### 1.1 背景

精度对齐智能体（PAA）通过 `git worktree` 为每个 API 创建独立的 Paddle 工作目录，并在其中执行 cmake 构建和安装。当前 Justfile 中的流程如下：

```
Paddle (main repo)
  ├── .paa/worktree/Paddle_avg_pool2d/    ← worktree, 独立 build/
  ├── .paa/worktree/Paddle_conv2d/        ← worktree, 独立 build/
  └── .paa/worktree/Paddle_batch_norm/    ← worktree, 独立 build/
```

### 1.2 核心矛盾

每个 worktree 执行 `cmake .. && ninja` 时，会在各自的 `build/third_party/` 下重新编译所有第三方依赖。这导致：

| 问题 | 影响 |
|------|------|
| 编译时间浪费 | 每个 worktree 的 third_party 编译耗时 10-30 分钟 |
| 磁盘空间爆炸 | 每份 third_party 约 2-5 GB，N 个 worktree = N × 5 GB |
| 无法大规模并行 | 想并行处理 10+ API 时资源瓶颈明显 |

### 1.3 Paddle 的实际依赖管理方式

通过代码分析，Paddle 第三方依赖分为两类：

**类型 A：Git Submodule 源码（大多数依赖）**

gflags、glog、eigen、protobuf、onednn、zlib、pybind11、gloo、gtest 等约 30+ 个依赖以 git submodule 方式存放在 `${PADDLE_SOURCE_DIR}/third_party/` 下。`ExternalProject_Add` 使用 `SOURCE_DIR` 指向 submodule，不涉及 git clone，但**每个 build 目录都会重新编译**。

**类型 B：URL 下载预编译二进制**

jemalloc、magma、mklml、cudnn-frontend 等通过 URL 下载到 `${PADDLE_SOURCE_DIR}/third_party/<dep>/`，带 MD5 校验缓存。由于下载位置在源码树内，跨 build 天然复用。

### 1.4 现有缓存机制

| 机制 | 状态 | 说明 |
|------|------|------|
| `THIRD_PARTY_PATH` cmake 变量 | 可用 | 默认 `${CMAKE_BINARY_DIR}/third_party`，可外部覆盖 |
| `WITH_TP_CACHE` + `cache_third_party()` | 几乎未使用 | 仅 sleef 调用，基于 URL+TAG 的 MD5 哈希缓存 |
| `THIRD_PARTY_TAR_URL` 回退 | CI 专用 | submodule 失败时下载预打包 tarball |
| `GIT_URL` 镜像 | 可用 | 覆盖 GitHub URL 为镜像地址 |
| 类型 B 的 MD5 文件缓存 | 默认启用 | 下载到源码树，跨 build 复用 |

**关键发现**：瓶颈不在"下载"（submodule 源码在源码树内共享），而在**每个 build 目录都重新编译 third_party 的 C++ 源码**（protobuf、glog、eigen 等的编译产物不共享）。

## 2. 目标

| 目标 | 度量 |
|------|------|
| 消除重复编译 | 第 2+ 个 worktree 的 third_party 阶段耗时 < 1 分钟 |
| 支持并行构建 | 10+ worktree 可同时 cmake+ninja，无写冲突 |
| 磁盘高效 | N 个 worktree 的 third_party 总占用 ≈ 1 份 + N × 极少增量 |
| 零侵入 | 不修改 Paddle 上游 cmake 代码 |
| 与 PAA 集成 | 改动限于 Justfile 和可选的 shell 脚本 |

## 3. 方案设计

### 3.1 方案概览：Golden Template + 硬链接复制

```
[一次性] 构建 Golden Third-Party
         │
         ▼
┌─────────────────────┐
│  $GOLDEN_TP_PATH    │  ← 完整编译过的 third_party
│  (single source)    │
└────────┬────────────┘
         │ cp -rl (硬链接, 秒级)
         ├──────────────────┬──────────────────┐
         ▼                  ▼                  ▼
  paddle_tp_api_a/    paddle_tp_api_b/   paddle_tp_api_c/
  (worktree A 专属)   (worktree B 专属)  (worktree C 专属)
```

**核心思路**：

1. **Golden Build**：预先编译一份完整的 third_party 作为模板
2. **硬链接分发**：每个 worktree 通过 `cp -rl` 获得独立但几乎零磁盘开销的副本
3. **写时断链**：任何 worktree 修改文件时，硬链接自动断开（文件系统语义），不影响其他 worktree
4. **`-DTHIRD_PARTY_PATH`**：利用 Paddle 现有的 cmake 变量指向各自的副本

### 3.2 详细流程

#### Phase 0：Golden Third-Party 构建（一次性）

```bash
# 在 Paddle 主仓库中执行，只需要编译 third_party 目标
GOLDEN_TP="$HOME/.paddle/golden_third_party"

mkdir -p /tmp/paddle_golden_build && cd /tmp/paddle_golden_build
cmake ${PADDLE_SOURCE_DIR} \
    -DTHIRD_PARTY_PATH="$GOLDEN_TP" \
    -DWITH_GPU=ON \
    -DWITH_TESTING=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -GNinja

# 只编译第三方依赖，不编译 Paddle 本体
ninja third_party

# 清理临时 build 目录
rm -rf /tmp/paddle_golden_build
```

**触发条件**：
- 首次使用
- Paddle 上游更新了 third_party submodule 版本
- 开关了构建选项（如 WITH_CINN、WITH_DISTRIBUTE）

#### Phase 1：Worktree 创建 + Third-Party 分发

```bash
setup_worktree_thirdparty() {
    local api_name="$1"
    local paddle_path="$2"
    local golden_tp="${GOLDEN_TP_PATH:-$HOME/.paddle/golden_third_party}"
    local wt_tp="${paddle_path}/build/third_party"  # cmake 默认路径

    if [ ! -d "$golden_tp" ]; then
        echo "ERROR: Golden third_party not found at $golden_tp"
        echo "Run 'just golden-tp-build' first."
        return 1
    fi

    mkdir -p "${paddle_path}/build"

    # 硬链接复制：秒级完成，磁盘零开销
    cp -rl "$golden_tp" "$wt_tp"

    echo "Third-party linked for $api_name → $wt_tp"
}
```

#### Phase 2：cmake 配置 + 增量编译

```bash
cd ${paddle_path}/build
cmake .. \
    -DTHIRD_PARTY_PATH="${paddle_path}/build/third_party" \
    -DWITH_GPU=ON \
    -DWITH_TESTING=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -GNinja

# cmake 检测到 third_party 已编译完成，直接跳过 → 进入 Paddle 本体编译
ninja -j$(nproc)
```

### 3.3 文件系统选择策略

| 文件系统 | 命令 | 优点 | 缺点 |
|----------|------|------|------|
| ext4/xfs（通用） | `cp -rl` | 零额外磁盘，无需特殊FS | 跨设备不可用，inode 有上限 |
| btrfs/xfs (reflink) | `cp --reflink=auto -r` | 真正 CoW，修改文件不影响源 | 需要文件系统支持 |
| 任意 | `rsync -a` | 最安全，完全独立 | 全量复制，磁盘 ×N |

**推荐**：默认使用 `cp -rl`，通过环境变量允许切换。

```bash
TP_COPY_CMD="${TP_COPY_CMD:-cp -rl}"
$TP_COPY_CMD "$golden_tp" "$wt_tp"
```

### 3.4 Golden Third-Party 版本管理

Golden 模板需要与当前 Paddle 代码保持一致。策略：

```bash
# 计算当前 third_party submodule 的 "指纹"
tp_fingerprint() {
    local paddle_path="$1"
    cd "$paddle_path"
    # 基于 third_party/ 下所有 submodule 的 commit hash + cmake 构建选项
    (git submodule status third_party/ 2>/dev/null; \
     echo "GPU=${WITH_GPU:-ON} CINN=${WITH_CINN:-ON} DIST=${WITH_DISTRIBUTE:-ON}") \
    | md5sum | cut -d' ' -f1
}

# Golden 目录按指纹存储
GOLDEN_TP="$HOME/.paddle/golden_tp_$(tp_fingerprint $PADDLE_PATH)"
```

这样不同版本的 Paddle 可以共存不同的 Golden 模板，避免版本冲突。

## 4. Justfile 集成设计

### 4.1 新增 Recipe

```just
# 构建 Golden Third-Party 模板（一次性）
golden-tp-build:
    #!/usr/bin/env bash
    set -euo pipefail
    PADDLE_PATH="${PADDLE_PATH:=.paa/repos/Paddle}"
    PADDLE_PATH="$(cd "$PADDLE_PATH" && pwd)"
    GOLDEN_TP="${GOLDEN_TP_PATH:-$HOME/.paddle/golden_third_party}"

    echo "Building golden third_party → $GOLDEN_TP"
    tmpdir=$(mktemp -d)
    cd "$tmpdir"

    cmake "$PADDLE_PATH" \
        -DTHIRD_PARTY_PATH="$GOLDEN_TP" \
        -DWITH_GPU=ON -DWITH_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release -GNinja

    ninja third_party
    rm -rf "$tmpdir"
    echo "Golden third_party ready: $GOLDEN_TP"

# 查看 Golden Third-Party 状态
golden-tp-status:
    #!/usr/bin/env bash
    GOLDEN_TP="${GOLDEN_TP_PATH:-$HOME/.paddle/golden_third_party}"
    if [ -d "$GOLDEN_TP" ]; then
        echo "Golden TP: $GOLDEN_TP"
        echo "Size: $(du -sh "$GOLDEN_TP" | cut -f1)"
        echo "Last modified: $(stat -c '%y' "$GOLDEN_TP" 2>/dev/null || stat -f '%Sm' "$GOLDEN_TP")"
    else
        echo "Golden TP not found. Run 'just golden-tp-build' first."
    fi
```

### 4.2 修改 `agentic-paddle-build-and-install`

```just
# Build and install Paddle in virtual environment (with third-party reuse)
agentic-paddle-build-and-install PADDLE_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    VENV_PATH="{{ PADDLE_PATH }}/.venv"
    GOLDEN_TP="${GOLDEN_TP_PATH:-$HOME/.paddle/golden_third_party}"
    TP_COPY_CMD="${TP_COPY_CMD:-cp -rl}"
    BUILD_DIR="{{ PADDLE_PATH }}/build"

    echo "Building Paddle..."
    cd "$VENV_PATH"
    source bin/activate

    # 复用 golden third_party（如果存在）
    if [ -d "$GOLDEN_TP" ] && [ ! -d "$BUILD_DIR/third_party" ]; then
        echo "Linking golden third_party..."
        mkdir -p "$BUILD_DIR"
        $TP_COPY_CMD "$GOLDEN_TP" "$BUILD_DIR/third_party"
        echo "Third-party linked in $(du -sh "$BUILD_DIR/third_party" | cut -f1)"
    fi

    cd "$BUILD_DIR"
    cmake .. \
        -DPADDLE_VERSION=0.0.0 \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
        -DPY_VERSION=3.10 \
        -DCUDA_ARCH_NAME=Auto \
        -DWITH_GPU=ON \
        -DWITH_DISTRIBUTE=ON \
        -DWITH_UNITY_BUILD=OFF \
        -DWITH_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DWITH_CINN=ON \
        -GNinja

    ninja -j$(nproc)

    echo "Installing Paddle..."
    cd "$VENV_PATH/.."
    uv pip install {{ PADDLE_PATH }}/build/python/dist/*.whl \
        --no-deps --force-reinstall
    echo "Paddle build and install completed successfully."
```

### 4.3 修改 `alignment-start`（并行感知）

关键改动点标注 `# [NEW]`：

```just
alignment-start api_name tool="opencode" additional_prompt="":
    #!/usr/bin/env bash
    set -euo pipefail
    # ... (existing path resolution code) ...

    echo "Setting up worktree"
    mkdir -p .paa/worktree
    cd $PADDLE_PATH
    git switch -c PAA/develop 2>/dev/null || git switch PAA/develop
    git pull upstream develop
    if [ -d "$PAA_ROOT/.paa/worktree/Paddle_{{ api_name }}" ]; then
        cd "$PAA_ROOT/.paa/worktree/Paddle_{{ api_name }}"
    else
        git worktree add \
            $PAA_ROOT/.paa/worktree/Paddle_{{ api_name }} \
            -b precision-alignment-agent/{{ api_name }}
    fi

    PADDLE_PATH=$PAA_ROOT/.paa/worktree/Paddle_{{ api_name }}
    VENV_PATH=$PADDLE_PATH/.venv

    cd $PADDLE_PATH
    just agentic-venv-setup $PADDLE_PATH
    mkdir -p build

    # [NEW] 复用 golden third-party
    GOLDEN_TP="${GOLDEN_TP_PATH:-$HOME/.paddle/golden_third_party}"
    if [ -d "$GOLDEN_TP" ] && [ ! -d "$PADDLE_PATH/build/third_party" ]; then
        echo "Reusing golden third_party..."
        ${TP_COPY_CMD:-cp -rl} "$GOLDEN_TP" "$PADDLE_PATH/build/third_party"
    fi

    cd build
    just agentic-paddle-build-and-install $PADDLE_PATH
    # ... (rest unchanged) ...
```

## 5. 并行构建执行方案

### 5.1 批量并行启动脚本

```bash
#!/usr/bin/env bash
# parallel-alignment.sh — 批量并行精度对齐
set -euo pipefail

API_LIST=("avg_pool2d" "conv2d" "batch_norm" "relu" "softmax" \
          "layer_norm" "linear" "dropout" "embedding" "cross_entropy")
MAX_PARALLEL="${MAX_PARALLEL:-4}"  # 并行度，受限于 GPU 显存和 CPU 核数
TOOL="${TOOL:-opencode}"

# 前置：确保 golden third_party 就绪
just golden-tp-build

echo "Starting parallel alignment for ${#API_LIST[@]} APIs (max $MAX_PARALLEL parallel)..."

# 使用 GNU parallel 或 xargs 控制并发
printf '%s\n' "${API_LIST[@]}" | \
    xargs -P "$MAX_PARALLEL" -I {} \
    bash -c 'echo "▶ Starting {}..."; just alignment-start {} '"$TOOL"' 2>&1 | tee .paa/logs/{}.log; echo "✅ {} done"'

echo "All alignments completed."
```

### 5.2 资源隔离

| 资源 | 隔离方式 |
|------|----------|
| 源码 | 每个 worktree 独立 (`git worktree add`) |
| build 目录 | 每个 worktree 独立 (`worktree/Paddle_xxx/build/`) |
| third_party | 每个 worktree 独立副本（硬链接自 golden） |
| venv | 每个 worktree 独立 (`worktree/Paddle_xxx/.venv/`) |
| GPU | 通过 `CUDA_VISIBLE_DEVICES` 分配 |
| 日志 | `.paa/logs/<api_name>.log` |

### 5.3 GPU 资源分配

多个编译任务可以共享 GPU（编译主要用 CPU），但精度测试需要独占 GPU：

```bash
# 编译阶段：所有 worktree 共享 GPU（cmake 需要探测 CUDA）
CUDA_VISIBLE_DEVICES=0 ninja -j$(nproc)

# 测试阶段：按 GPU 分配
CUDA_VISIBLE_DEVICES=$((task_index % num_gpus)) python engineV2.py ...
```

## 6. 潜在风险与缓解

| 风险 | 概率 | 缓解措施 |
|------|------|----------|
| cmake 构建选项不一致导致 golden 不可用 | 中 | 指纹化 golden 目录（§3.4），按选项组合分别缓存 |
| 硬链接跨文件系统不可用 | 低 | 回退到 `cp -r`，通过 `TP_COPY_CMD` 环境变量控制 |
| inode 耗尽（大量小文件 × 多 worktree） | 低 | 监控 `df -i`；reflink 方案无此问题 |
| Golden 模板与 worktree 分支的 third_party 版本不匹配 | 中 | 对于精度对齐场景，worktree 通常基于同一 develop 分支，风险可控 |
| 并行 cmake 配置同时写同一 golden 目录 | 低 | golden build 是单独步骤，不与 worktree 构建并行 |

## 7. 收益预估

以 10 个 API 的并行精度对齐为例：

| 指标 | 当前（无复用） | 方案实施后 |
|------|---------------|-----------|
| Third-party 编译总时间 | 10 × 20min = 200min | 1 × 20min + 10 × <1min ≈ 21min |
| 磁盘占用 | 10 × 4GB = 40GB | 4GB + 10 × ~50MB ≈ 4.5GB |
| 端到端时间（4路并行） | ~3 × 50min = 150min | ~3 × 30min = 90min |
| Golden 构建一次性成本 | 0 | 20min（只需一次） |

## 8. 实施步骤

1. **在 Justfile 中新增 `golden-tp-build` 和 `golden-tp-status` recipe**
2. **修改 `agentic-paddle-build-and-install` 支持 golden TP 复用**
3. **修改 `alignment-start` 在 worktree 创建后自动链接 golden TP**
4. **新增 `parallel-alignment` recipe 支持批量并行启动**
5. **文档更新**：README 中增加 golden third-party 使用说明

## 9. 环境变量汇总

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `GOLDEN_TP_PATH` | `$HOME/.paddle/golden_third_party` | Golden 模板路径 |
| `TP_COPY_CMD` | `cp -rl` | 复制命令（可选 `cp --reflink=auto -r`、`rsync -a`） |
| `MAX_PARALLEL` | `4` | 最大并行 worktree 数 |
| `PADDLE_PATH` | `.paa/repos/Paddle` | Paddle 主仓库路径 |
