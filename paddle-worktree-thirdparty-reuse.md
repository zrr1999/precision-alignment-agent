# Paddle Worktree 第三方依赖复用设计文档

> 解决 git worktree 场景下 Paddle cmake 重复编译第三方依赖的问题，支持大规模并行构建。

## 1. 问题描述

### 1.1 背景

Paddle Pilot 通过 `git worktree` 为每个 API 创建独立的 Paddle 工作目录，并在其中执行 cmake 构建和安装。当前 justfile 中的流程如下：

```
Paddle (main repo)
  ├── .paddle-pilot/worktree/Paddle_avg_pool2d/    ← worktree, 独立 build/
  ├── .paddle-pilot/worktree/Paddle_conv2d/        ← worktree, 独立 build/
  └── .paddle-pilot/worktree/Paddle_batch_norm/    ← worktree, 独立 build/
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
| 与 Paddle Pilot 集成 | 改动限于 justfile 和可选的 shell 脚本 |

## 3. 业界调研

### 3.1 结论

**没有找到直接竞品。** 没有现成的开源工具使用 overlayfs（或任何 CoW 机制）在并行构建目录/git worktree 之间共享预编译的 CMake ExternalProject 第三方依赖。这是一个真实的空白。

但 "只读黄金基底 + 每消费者 overlay" 这一架构模式在相邻领域被广泛验证：

### 3.2 相关工具

| 工具 | Stars | 用了 overlayfs? | 场景 | 与本方案关系 |
|------|-------|----------------|------|-------------|
| **Mock (RPM)** | 424 | **是（plugin）** | RPM 构建 chroot 快照 | **最接近的类比**：层叠快照 + 引用计数 |
| **BuildKit** | 9.8k | 间接 (overlay2) | `RUN --mount=type=cache` | Docker 内的构建缓存，不适用 host worktree |
| **poudriere (ZFS)** | 439 | 否 (ZFS clone) | FreeBSD ports 构建 | 架构完全一致，只是 ZFS 而非 overlayfs |
| **Nix** | 16k | 否 (bind mount) | 内容寻址包管理 | 概念上的理想解，但需要全生态 Nix 化 |
| **composefs** | 623 | **是** | 容器镜像共享 backing store | 验证了 page cache 跨挂载共享的收益 |
| **fuse-overlayfs** | 644 | **是（用户态）** | rootless 容器 | 可作为无 root 环境的降级方案 |
| **ccache / sccache** | 7k / 2.8k | 否 | 编译对象缓存 | 互补关系：overlay 共享库级缓存，ccache 共享对象级缓存 |
| **overlayfs-tools** | 153 | N/A（工具集） | vacuum/diff/merge | 可用于清理 upper 层不必要的 copy-up |
| **poof** | 148 | **是** | 临时文件系统沙箱 | 概念相似但目标是隔离而非共享 |

### 3.3 关键 takeaway

1. **Mock 的 overlayfs plugin** 是架构上最接近的实现 — 分层快照+引用计数管理 chroot 环境
2. **poudriere** 的 ZFS clone 模型与本方案概念完全一致（golden jail → clone → 构建 → 丢弃）
3. **ccache/sccache** 可与本方案叠加使用 — overlay 节省 cmake configure + link 时间，ccache 节省单文件重编时间
4. **composefs** 证实了一个重要优化：多个 overlay 挂载共享同一 golden 目录时，内核 page cache 自动去重
5. **fuse-overlayfs** 可作为无 root 权限环境的降级方案（替代 `cp -r`）

### 3.4 通用化潜力

本方案可解耦为通用工具，适用于所有 "昂贵一次性构建 + 多并行消费者" 场景：

- 任何使用 cmake `ExternalProject_Add` 的大型 C++ 项目（LLVM、TensorFlow、PyTorch）
- monorepo 多分支并行 CI
- 插件/扩展开发（共享主项目构建产物，各插件独立编译）

建议命名：**buildcow**（Build Copy-on-Write），核心 API：

```bash
buildcow init   --golden /ssd1/golden_tp --from ./build/third_party
buildcow mount  --golden /ssd1/golden_tp --target ./worktree_A/build/third_party
buildcow umount ./worktree_A/build/third_party
buildcow status
buildcow cleanup
```

## 4. 方案选型

### 3.1 为什么不能用硬链接（`cp -rl`）

硬链接（`cp -rl`）多个文件名指向同一 inode。当某个 worktree 的 cmake 重新编译某个 third_party 依赖时（例如分支间 protobuf 版本不同），truncate/写入会直接修改共享的 inode，**所有 worktree 同时被污染**：

```
Golden: libprotobuf.a  →  inode #12345
worktree_A: libprotobuf.a ────┘  ← 硬链接，同一 inode
worktree_B: libprotobuf.a ────┘

# worktree_A 的 cmake 重新编译 protobuf：
#   open("libprotobuf.a", O_WRONLY|O_TRUNC) → truncate 共享 inode
#   ⚠️ worktree_B 同时被破坏！
```

硬链接不是 Copy-on-Write，**并行 + 不同分支 = 数据竞争**。

### 3.2 方案对比

| | `cp -r` 全量复制 | overlayfs | btrfs on loop |
|---|---|---|---|
| CoW 安全 | ✅（完全独立） | ✅（upper 层隔离） | ✅（reflink/snapshot） |
| 磁盘开销 | ~4GB × N | 极少（仅 diff） | 极少（仅 diff） |
| 创建速度 | ~30s/份 (SSD) | 瞬间 | 瞬间 |
| 需要 root | 否 | **是** | **是** |
| 运维复杂度 | 零 | 低 | 中（需管理 loop 设备） |
| Docker 可用 | ✅ | ✅（privileged） | ✅（privileged） |

### 3.3 最终选择：overlayfs

**overlayfs 语义与场景完美匹配**：golden third_party 作为只读 lowerdir，每个 worktree 的修改写入独立 upperdir。

当前环境为超级权限 Docker 容器，overlayfs 可直接使用。

## 4. 方案设计：Golden Template + overlayfs

### 4.1 架构概览

```
[一次性] 构建 Golden Third-Party (lowerdir, 只读)
         │
         ▼
┌─────────────────────────────────┐
│  $GOLDEN_TP_PATH (只读基底)      │
│  protobuf/ glog/ eigen/ ...     │
└────────┬────────────────────────┘
         │ mount -t overlay (瞬间, 零拷贝)
         ├──────────────────┬──────────────────┐
         ▼                  ▼                  ▼
  worktree_A/build/tp/   worktree_B/build/tp/  worktree_C/build/tp/
  upper_A/ (仅 diff)     upper_B/ (仅 diff)    upper_C/ (仅 diff)
```

**工作原理**：

```
读取文件 → 直接从 lowerdir (golden) 读取，零拷贝
修改文件 → 自动 copy-up 到 upperdir，不影响 golden 和其他 worktree
删除文件 → 在 upperdir 创建 whiteout 标记，不影响 golden
新增文件 → 直接写入 upperdir
```

### 4.2 详细流程

#### Phase 0：Golden Third-Party 构建（一次性）

```bash
GOLDEN_TP="${GOLDEN_TP_PATH:-$HOME/.paddle/golden_third_party}"

tmpdir=$(mktemp -d)
cd "$tmpdir"

cmake ${PADDLE_SOURCE_DIR} \
    -DTHIRD_PARTY_PATH="$GOLDEN_TP" \
    -DWITH_GPU=ON \
    -DWITH_TESTING=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_CINN=ON \
    -DWITH_DISTRIBUTE=ON \
    -GNinja

# 只编译第三方依赖
ninja third_party

rm -rf "$tmpdir"
```

**触发条件**：
- 首次使用
- Paddle 上游更新了 third_party submodule 版本
- 变更了构建选项（如 WITH_CINN、WITH_DISTRIBUTE）

#### Phase 1：overlayfs 挂载

```bash
# 为每个 worktree 创建 overlay 挂载
mount_tp_overlay() {
    local wt_name="$1"
    local mount_point="$2"   # worktree 的 build/third_party
    local golden_tp="$3"     # golden 模板路径

    local overlay_base="/tmp/paddle_overlay/${wt_name}"
    local upper="${overlay_base}/upper"
    local work="${overlay_base}/work"

    mkdir -p "$upper" "$work" "$mount_point"

    mount -t overlay overlay \
        -o "lowerdir=${golden_tp},upperdir=${upper},workdir=${work}" \
        "$mount_point"
}

# 示例
mount_tp_overlay "avg_pool2d" \
    "/path/to/worktree/Paddle_avg_pool2d/build/third_party" \
    "$HOME/.paddle/golden_third_party"
```

#### Phase 2：cmake 配置 + 构建

```bash
cd ${paddle_path}/build

# THIRD_PARTY_PATH 指向 overlay 挂载点（即 build/third_party）
# cmake 检测到 third_party 已编译完成 → 跳过
# 如果某个 dep 版本不同 → cmake 只重编该 dep → 写入 upperdir，不影响其他 worktree
cmake .. \
    -DTHIRD_PARTY_PATH="${paddle_path}/build/third_party" \
    -DWITH_GPU=ON \
    -DWITH_TESTING=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_CINN=ON \
    -GNinja

ninja -j$(nproc)
```

#### Phase 3：清理

```bash
# 卸载 overlay
umount_tp_overlay() {
    local wt_name="$1"
    local mount_point="$2"

    umount "$mount_point" 2>/dev/null || true
    rm -rf "/tmp/paddle_overlay/${wt_name}"
}
```

### 4.3 Golden Third-Party 版本管理

Golden 模板需要与当前 Paddle 代码保持一致。通过指纹机制自动管理：

```bash
tp_fingerprint() {
    local paddle_path="$1"
    cd "$paddle_path"
    # 基于 third_party/ 下所有 submodule 的 commit hash + cmake 构建选项
    (git submodule status third_party/ 2>/dev/null; \
     echo "GPU=${WITH_GPU:-ON} CINN=${WITH_CINN:-ON} DIST=${WITH_DISTRIBUTE:-ON}") \
    | md5sum | cut -d' ' -f1
}

# Golden 目录按指纹存储，不同版本共存
GOLDEN_TP="$HOME/.paddle/golden_tp_$(tp_fingerprint $PADDLE_PATH)"
```

### 4.4 降级策略

overlayfs 的 upper/work **不能位于另一个 overlayfs 上**（Docker 容器的 `/` 就是 overlayfs）。需要自动探测可用的真实文件系统：

```bash
setup_tp_for_worktree() {
    local wt_name="$1"
    local mount_point="$2"
    local golden_tp="$3"

    # 探测可用的真实 FS（用于 overlay 的 upper/work）
    local overlay_base=""
    for candidate in /ssd1 /data /cache /host_home /dev/shm; do
        if [ -d "$candidate" ] && [ -w "$candidate" ]; then
            local fstype=$(stat -f -c '%T' "$candidate" 2>/dev/null)
            if [ "$fstype" != "overlayfs" ] && [ "$fstype" != "OVERLAYFS" ]; then
                overlay_base="${candidate}/paddle_overlay/${wt_name}"
                break
            fi
        fi
    done

    if [ -n "$overlay_base" ]; then
        mkdir -p "${overlay_base}/upper" "${overlay_base}/work" "$mount_point"
        if mount -t overlay overlay \
            -o "lowerdir=${golden_tp},upperdir=${overlay_base}/upper,workdir=${overlay_base}/work" \
            "$mount_point" 2>/dev/null; then
            echo "overlay mounted for $wt_name (backing: $(dirname "$overlay_base"))"
            return 0
        fi
    fi

    # 降级：全量复制（安全但慢）
    echo "overlayfs unavailable, falling back to cp -r..."
    cp -r "$golden_tp" "$mount_point"
}
```

**探测优先级**：持久真实 FS (`/ssd1`, `/data`) > tmpfs (`/dev/shm`, 易失) > `cp -r`

## 5. justfile 集成设计

### 5.1 新增 Recipe

```just
# 构建 Golden Third-Party 模板（一次性）
golden-tp-build:
    #!/usr/bin/env bash
    set -euo pipefail
    PADDLE_PATH="${PADDLE_PATH:=.paddle-pilot/repos/Paddle}"
    PADDLE_PATH="$(cd "$PADDLE_PATH" && pwd)"
    GOLDEN_TP="${GOLDEN_TP_PATH:-$HOME/.paddle/golden_third_party}"

    if [ -d "$GOLDEN_TP" ]; then
        echo "Golden TP already exists: $GOLDEN_TP ($(du -sh "$GOLDEN_TP" | cut -f1))"
        read -rp "Rebuild? [y/N] " ans
        [[ "${ans:-N}" =~ ^[Yy]$ ]] || exit 0
        rm -rf "$GOLDEN_TP"
    fi

    echo "Building golden third_party → $GOLDEN_TP"
    mkdir -p "$GOLDEN_TP"
    tmpdir=$(mktemp -d)

    cmake -S "$PADDLE_PATH" -B "$tmpdir" \
        -DTHIRD_PARTY_PATH="$GOLDEN_TP" \
        -DPADDLE_VERSION=0.0.0 \
        -DPY_VERSION=3.12 \
        -DCUDA_ARCH_NAME=Auto \
        -DWITH_GPU=ON \
        -DWITH_DISTRIBUTE=ON \
        -DWITH_UNITY_BUILD=OFF \
        -DWITH_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DWITH_CINN=ON \
        -GNinja

    cmake --build "$tmpdir" --target third_party -j$(nproc)
    rm -rf "$tmpdir"
    echo "Golden third_party ready: $GOLDEN_TP ($(du -sh "$GOLDEN_TP" | cut -f1))"

# 查看 Golden Third-Party 状态
golden-tp-status:
    #!/usr/bin/env bash
    GOLDEN_TP="${GOLDEN_TP_PATH:-$HOME/.paddle/golden_third_party}"
    if [ -d "$GOLDEN_TP" ]; then
        echo "Path:     $GOLDEN_TP"
        echo "Size:     $(du -sh "$GOLDEN_TP" | cut -f1)"
        echo "Modified: $(stat -c '%y' "$GOLDEN_TP")"
        echo "Overlays: $(mount -t overlay 2>/dev/null | grep -c paddle_overlay || echo 0) active"
    else
        echo "Golden TP not found. Run 'just golden-tp-build' first."
    fi

# 清理所有 overlay 挂载
golden-tp-cleanup:
    #!/usr/bin/env bash
    echo "Unmounting all paddle overlay mounts..."
    mount -t overlay | grep paddle_overlay | awk '{print $3}' | while read mp; do
        umount "$mp" && echo "  unmounted: $mp"
    done
    rm -rf /tmp/paddle_overlay
    echo "Cleanup done."
```

### 5.2 修改 `agentic-paddle-build-and-install`

```just
# Build and install Paddle in virtual environment (with third-party reuse via overlayfs)
agentic-paddle-build-and-install PADDLE_PATH:
    #!/usr/bin/env bash
    set -euo pipefail
    GOLDEN_TP="${GOLDEN_TP_PATH:-$HOME/.paddle/golden_third_party}"
    BUILD_DIR="{{ PADDLE_PATH }}/build"
    TP_DIR="${BUILD_DIR}/third_party"

    echo "Building Paddle..."
    cd "{{ PADDLE_PATH }}"
    source .venv/bin/activate
    mkdir -p build

    # 复用 golden third_party（如果存在且尚未挂载）
    if [ -d "$GOLDEN_TP" ] && ! mountpoint -q "$TP_DIR" 2>/dev/null && [ ! -d "$TP_DIR/install" ]; then
        WT_NAME=$(basename "{{ PADDLE_PATH }}")

        # 探测可用的真实 FS（overlay 的 upper/work 不能在 overlayfs 上）
        OVERLAY_BACKING=""
        for candidate in /ssd1 /data /cache /host_home /dev/shm; do
            if [ -d "$candidate" ] && [ -w "$candidate" ]; then
                fstype=$(stat -f -c '%T' "$candidate" 2>/dev/null)
                if [ "$fstype" != "overlayfs" ] && [ "$fstype" != "OVERLAYFS" ]; then
                    OVERLAY_BACKING="$candidate/paddle_overlay/${WT_NAME}"
                    break
                fi
            fi
        done

        if [ -n "$OVERLAY_BACKING" ]; then
            mkdir -p "${OVERLAY_BACKING}/upper" "${OVERLAY_BACKING}/work" "$TP_DIR"
            if mount -t overlay overlay \
                -o "lowerdir=${GOLDEN_TP},upperdir=${OVERLAY_BACKING}/upper,workdir=${OVERLAY_BACKING}/work" \
                "$TP_DIR" 2>/dev/null; then
                echo "Overlay mounted: golden → $TP_DIR (backing: $(dirname "$OVERLAY_BACKING"))"
            else
                echo "overlay mount failed, falling back to cp -r..."
                rmdir "$TP_DIR" 2>/dev/null || true
                cp -r "$GOLDEN_TP" "$TP_DIR"
            fi
        else
            echo "No real FS found for overlay, falling back to cp -r..."
            cp -r "$GOLDEN_TP" "$TP_DIR"
        fi
    fi

    cd build
    cmake .. \
        -DPADDLE_VERSION=0.0.0 \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
        -DPY_VERSION=3.12 \
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
    cd "{{ PADDLE_PATH }}"
    uv pip install {{ PADDLE_PATH }}/build/python/dist/*.whl --no-deps --force-reinstall
    echo "Paddle build and install completed successfully."
```

## 6. 并行构建执行方案

### 6.1 资源隔离

```
worktree_A/
├── build/
│   ├── third_party/          ← overlayfs mount (golden + upper_A)
│   ├── paddle/               ← 独立编译产物
│   └── python/dist/*.whl     ← 独立安装包
├── .venv/                    ← 独立虚拟环境
└── (source files)            ← git worktree 管理

/tmp/paddle_overlay/
├── Paddle_avg_pool2d/
│   ├── upper/                ← 仅存放与 golden 的差异文件
│   └── work/                 ← overlayfs 工作目录
├── Paddle_conv2d/
│   ├── upper/
│   └── work/
...
```

| 资源 | 隔离方式 |
|------|----------|
| 源码 | 每个 worktree 独立 (`git worktree add`) |
| build 目录 | 每个 worktree 独立 (`worktree/Paddle_xxx/build/`) |
| third_party | overlayfs（共享只读 golden + 独立可写 upper） |
| venv | 每个 worktree 独立 (`worktree/Paddle_xxx/.venv/`) |
| GPU | 通过 `CUDA_VISIBLE_DEVICES` 分配 |
| 日志 | `.paddle-pilot/logs/<api_name>.log` |

### 6.2 GPU 资源分配

编译阶段主要用 CPU（共享 GPU 即可），精度测试需按 GPU 分配：

```bash
# 编译阶段：所有 worktree 共享 GPU（cmake 仅用于 CUDA 架构探测）
CUDA_VISIBLE_DEVICES=0 ninja -j$(nproc)

# 测试阶段：按 GPU 轮转分配
CUDA_VISIBLE_DEVICES=$((task_index % num_gpus)) python engineV2.py ...
```

### 6.3 批量并行启动

```bash
#!/usr/bin/env bash
# parallel-alignment.sh
set -euo pipefail

API_LIST=("avg_pool2d" "conv2d" "batch_norm" "relu" "softmax" \
          "layer_norm" "linear" "dropout" "embedding" "cross_entropy")
MAX_PARALLEL="${MAX_PARALLEL:-4}"
TOOL="${TOOL:-opencode}"

# 前置：确保 golden third_party 就绪
just golden-tp-build

mkdir -p .paddle-pilot/logs
echo "Starting parallel alignment for ${#API_LIST[@]} APIs (max $MAX_PARALLEL)..."

printf '%s\n' "${API_LIST[@]}" | \
    xargs -P "$MAX_PARALLEL" -I {} \
    bash -c 'echo "▶ Starting {}..."; just alignment-start {} '"$TOOL"' 2>&1 | tee .paddle-pilot/logs/{}.log; echo "✅ {} done"'

# 清理 overlay
just golden-tp-cleanup
echo "All alignments completed."
```

## 7. 潜在风险与缓解

| 风险 | 概率 | 缓解措施 |
|------|------|----------|
| Docker 未开启 privileged | 中 | 启动时加 `--privileged`，或 `--cap-add SYS_ADMIN`；降级用 `cp -r` |
| cmake 构建选项不一致导致 golden 不可用 | 中 | 指纹化 golden 目录（§4.3），按选项组合分别缓存 |
| overlay 上限（嵌套层数） | 极低 | 单层 overlay 足够，不涉及嵌套 |
| `/tmp` 空间不足（upper 膨胀） | 低 | 监控 `df /tmp`；大部分 dep 版本一致时 upper 极小 |
| 进程崩溃后 overlay 未卸载 | 中 | `golden-tp-cleanup` recipe 统一清理；trap EXIT 自动清理 |
| Golden 与 worktree 分支的 third_party 版本不匹配 | 中 | overlayfs 自动处理：cmake 重编的 dep 写入 upper，不影响 golden |

## 8. 收益预估

以 10 个 API 的并行精度对齐为例：

| 指标 | 当前（无复用） | overlayfs 方案 |
|------|---------------|----------------|
| Third-party 编译总时间 | 10 × 20min = 200min | 1 × 20min + 10 × <1min ≈ 21min |
| 磁盘占用 | 10 × 4GB = 40GB | 4GB + 10 × ~50MB ≈ 4.5GB |
| 端到端时间（4路并行） | ~3 × 50min = 150min | ~3 × 30min = 90min |
| 版本差异场景 | 每个 worktree 全量重编 | 仅重编差异 dep（增量 copy-up） |
| Golden 构建一次性成本 | - | 20min（只需一次） |

## 9. 实施步骤

1. **在 justfile 中新增 `golden-tp-build`、`golden-tp-status`、`golden-tp-cleanup` recipe**
2. **修改 `agentic-paddle-build-and-install`**：构建前自动挂载 overlay
3. **修改 `alignment-start`**：集成 golden TP 流程（由 `agentic-paddle-build-and-install` 内部处理，无需额外改动）
4. **测试**：单 worktree 验证 overlay 挂载 → cmake 跳过 third_party → ninja 正常编译
5. **并行测试**：多 worktree 同时构建，验证隔离性

## 10. 环境变量汇总

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `GOLDEN_TP_PATH` | `$HOME/.paddle/golden_third_party` | Golden 模板路径 |
| `MAX_PARALLEL` | `4` | 最大并行 worktree 数 |
| `PADDLE_PATH` | `.paddle-pilot/repos/Paddle` | Paddle 主仓库路径 |

## 11. 环境要求与限制（PoC 验证结论）

### 11.1 核心约束：overlay 不能嵌套

Docker 容器的 `/` 是 overlay2 文件系统。在 Linux 5.10 内核上，**overlayfs 的 upperdir/workdir 不能位于另一个 overlayfs 上**。这意味着：

```
✗ upper/work 在 /tmp（容器 rootfs = overlayfs）  → mount 失败
✓ upper/work 在 /ssd1（ext4 真实设备）            → mount 成功
✓ upper/work 在 /dev/shm（tmpfs）                → mount 成功
✓ lowerdir（golden）在 /（overlayfs）             → 没有限制
```

**PoC 验证结果**（24/24 测试通过）：
- 读穿透 ✓ | 写隔离 ✓ | 并行 3 路写 ✓ | 新增文件 ✓ | 删除 whiteout ✓
- 模拟并行 cmake 构建 ✓ | 未修改的 dep upper 为 0 文件 ✓
- overlay mount point 可以在容器 rootfs 上 ✓

### 11.2 Docker 启动要求

```bash
# 方式一：完整特权（开发环境推荐）
docker run --privileged ...

# 方式二：最小权限
docker run --cap-add SYS_ADMIN --security-opt apparmor:unconfined ...
```

### 11.3 真实文件系统的获取方式

| 方式 | 命令 | 持久性 | 是否需要重建 Docker |
|------|------|--------|-------------------|
| 设备挂载（当前环境） | `-v /dev/nvme0n1:/ssd1` 或设备映射 | 持久 | 否（已有） |
| bind mount 宿主机目录 | `docker run -v /host/data:/data` | 持久 | **是** |
| Docker named volume | `docker run --mount type=volume,source=cache,target=/cache` | 持久 | **是** |
| tmpfs | `docker run --mount type=tmpfs,destination=/fast,tmpfs-size=8G` | **易失** | **是** |
| /dev/shm（已存在） | 无需额外操作 | **易失** | 否 |
| loopback ext4 | 容器内 `dd + losetup + mkfs.ext4` | 取决于 backing file | 否 |

### 11.4 无挂载 SSD 时的解决方案

```
是否有已挂载的真实文件系统（ext4/xfs/btrfs）?
├── 有（如 /ssd1, /data, bind mount）
│   └── 直接用，最佳方案。golden + upper + work 放在上面。
│
├── 没有，但 /dev/shm 空间 > 2GB?
│   └── 用 /dev/shm（tmpfs），upper/work 放在上面。
│       注意：容器重启后 upper 丢失，golden 需重建。
│       适合：CI 一次性构建场景。
│
├── 没有，但可以重建 Docker 容器?
│   └── 添加 -v /host/path:/cache 或 --mount type=volume
│       然后 golden + upper + work 放在 /cache。
│       推荐的生产方案。
│
├── 都没有，但有 root + loop 设备?
│   └── 在容器内创建 loopback ext4：
│       dd if=/dev/zero of=/tmp/cache.img bs=1M count=8192
│       losetup /dev/loop0 /tmp/cache.img
│       mkfs.ext4 -q /dev/loop0
│       mount /dev/loop0 /mnt/cache
│       性能有损耗，但可用。
│
├── 有 /dev/fuse 且可安装 fuse-overlayfs?
│   └── fuse-overlayfs 无需真实 FS，用户态实现。
│       fuse-overlayfs -o lowerdir=...,upperdir=...,workdir=... merged
│       FUSE 开销约 10-20%。
│
└── 以上都不行
    └── 降级为 cp -r 全量复制（安全但慢+费磁盘）。
```

### 11.5 环境检测脚本

构建工具应自动选择最佳策略：

```bash
detect_overlay_strategy() {
    # 优先级: 真实 FS > tmpfs > loopback > fuse-overlayfs > cp -r
    for candidate in /ssd1 /data /cache /mnt/data; do
        if [ -d "$candidate" ] && [ -w "$candidate" ]; then
            fstype=$(stat -f -c '%T' "$candidate" 2>/dev/null)
            case "$fstype" in
                ext2/ext3|xfs|btrfs) echo "OVERLAY:$candidate"; return 0 ;;
            esac
        fi
    done

    # tmpfs 检测
    if [ -d /dev/shm ] && [ -w /dev/shm ]; then
        avail=$(df -BM /dev/shm | tail -1 | awk '{print $4}' | tr -d 'M')
        [ "$avail" -gt 2048 ] && echo "OVERLAY_TMPFS:/dev/shm" && return 0
    fi

    # fuse-overlayfs
    command -v fuse-overlayfs &>/dev/null && [ -c /dev/fuse ] && \
        echo "FUSE_OVERLAY" && return 0

    echo "FALLBACK_CP"
}
```

### 11.6 内核版本兼容性

| 内核版本 | 嵌套 overlay 支持 | 说明 |
|----------|-------------------|------|
| < 5.11（当前 5.10） | **不支持** | upper 在 overlayfs 上始终失败 |
| 5.11 - 5.18 | 部分 | 仅 lower 可在 overlayfs 上 |
| 5.19+ | 部分 | 增加 `uuid=off` 参数 |
| 6.5+ | 实验性 | 有补丁但未稳定合入 |

**注意**：即使内核升级到 6.5+，嵌套 overlay 的 upper 支持仍是实验性质。推荐始终使用真实文件系统。

### 11.7 性能基准（当前环境实测）

| 配置 | 写入速度 | 相对基准 | 持久性 |
|------|----------|---------|--------|
| ext4 on NVMe (`/ssd1`) | 47.9 MB/s | 1.0x | 是 |
| overlay on ext4 | 47.4 MB/s | 0.99x | 是 |
| tmpfs 直写 | 1,200 MB/s | 25x | 否 |
| overlay on tmpfs | 1,300 MB/s | 27x | 否 |

**结论**：overlay 层几乎零开销（~1%），底层存储的选择才是关键。

### 11.8 Kubernetes 部署指南

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: builder
    securityContext:
      privileged: true  # overlayfs mount 需要
    volumeMounts:
    - name: build-cache
      mountPath: /cache   # golden + upper + work 放这里
  volumes:
  # 方案 A: PVC（推荐，持久共享）
  - name: build-cache
    persistentVolumeClaim:
      claimName: build-cache-pvc  # ext4/xfs 格式

  # 方案 B: emptyDir tmpfs（CI 一次性构建）
  # - name: build-cache
  #   emptyDir:
  #     medium: Memory
  #     sizeLimit: 8Gi

  # 方案 C: hostPath（节点级缓存）
  # - name: build-cache
  #   hostPath:
  #     path: /data/build-cache
  #     type: DirectoryOrCreate
```

| K8s Volume 类型 | 文件系统 | overlay 可用 | 持久性 |
|-----------------|---------|-------------|--------|
| PVC (block) | ext4/xfs | ✅ | 持久 |
| hostPath | 宿主机 FS | ✅ | 节点级 |
| emptyDir (Memory) | tmpfs | ✅ | Pod 生命周期 |
| emptyDir (default) | 容器 rootfs | ❌ | Pod 生命周期 |
| NFS PVC | NFS | ⚠️ v3 可能可以 | 持久 |





