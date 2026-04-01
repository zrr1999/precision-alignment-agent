# Docker 容器内使用 OverlayFS：环境要求与限制

> 实测环境：Linux 5.10.0-1.0.0.42（百度定制内核），Docker overlay2 存储驱动。
> 日期：2026-03-10

## 1. 核心结论

**核心约束**：OverlayFS 要求 **upperdir** 和 **workdir** 所在的文件系统支持特定 POSIX 特性（`d_type`、trusted xattrs、file-handle API 等）。在 5.10 内核上，**overlay 不支持嵌套** —— upper/work 目录不能位于另一个 overlayfs 挂载之上。lower 目录没有此限制。

**Docker 容器的实际规则**：由于容器内的根文件系统 `/` 始终是 overlayfs（Docker 使用 overlay2 存储驱动时），**不能**在 `/tmp`、`/root`、`/home` 或任何位于 `/` 下且未被单独挂载为真实文件系统的路径上创建 overlay 挂载的 upper/work 目录。

## 2. 内核版本与嵌套 Overlay 支持

### 当前环境

```
$ uname -r
5.10.0-1.0.0.42

$ cat /proc/version
Linux version 5.10.0-1.0.0.42 (root@bddwd-matrix-rd-dev01.bddwd.baidu.com)
(gcc (GCC) 8.3.1 20191121 (Red Hat 8.3.1-5))
```

### Overlay 模块参数

```
$ cat /sys/module/overlay/parameters/*
check_copy_up = N
index         = Y
metacopy      = Y        # <-- metacopy 已启用
nfs_export    = N
redirect_always_follow = Y
redirect_dir  = Y        # <-- redirect_dir 已启用
redirect_max  = 256
xino_auto     = N
```

### 内核版本对嵌套 Overlay 的支持矩阵

| 内核版本 | 嵌套 Overlay 支持 | 说明 |
|----------|-------------------|------|
| < 5.11 | **不支持** | `upperdir` 在 overlayfs 上时始终报错 "not supported as upperdir" |
| 5.11 - 5.18 | **部分支持** | 仅 lower 层可以在 overlayfs 上。upper 在 overlay 上在多数配置下仍被拒绝 |
| 5.19+ | **部分支持** | 新增 `uuid=off` 参数，使嵌套 overlay 的 lower 层不再产生警告 |
| 6.5+ | **实验性** | 部分补丁允许在 `metacopy=off,redirect_dir=off` 时嵌套 upper，但未作为稳定特性合入主线 |

**关键认识**：即使在"支持"嵌套 overlay 的内核（5.11+）上，支持也主要针对 **lower** 目录位于 overlayfs 的场景。**upper/work** 位于 overlayfs 上至少到 6.5 内核仍不受支持或处于实验状态。

### `metacopy` 和 `redirect_dir` 的影响

- **`metacopy=Y`**（当前已启用）：启用时使用仅元数据的 copy-up，会创建基于 xattr 的特殊元数据，需要真实文件系统支撑。在 5.10 内核上，设置 `metacopy=off` 挂载选项**无法**解决嵌套问题。
- **`redirect_dir=Y`**（当前已启用）：启用重命名目录的重定向，同样存储 xattr 元数据。在 5.10 内核上，设置 `redirect_dir=off` **无法**解决嵌套问题。
- **`overlay.metacopy=N` 内核引导参数**：可在启动时全局禁用 metacopy。但这**不能**启用 overlay-on-overlay 嵌套。嵌套限制在更底层执行 —— 内核直接检查 upperdir 的文件系统类型是否为 overlayfs，如果是则直接拒绝。

### 实测验证：5.10 内核上任何挂载选项都无法启用嵌套

```bash
# 以下命令在 5.10 内核上 upper/work 位于 overlayfs (/tmp) 时全部失败：

$ mount -t overlay overlay -o lowerdir=lower,upperdir=upper,workdir=work,index=off merged
# dmesg: overlayfs: filesystem on '/tmp/.../upper' not supported as upperdir

$ mount -t overlay overlay -o lowerdir=lower,upperdir=upper,workdir=work,metacopy=off merged
# dmesg: overlayfs: filesystem on '/tmp/.../upper' not supported as upperdir

$ mount -t overlay overlay -o lowerdir=lower,upperdir=upper,workdir=work,index=off,metacopy=off,redirect_dir=off merged
# dmesg: overlayfs: filesystem on '/tmp/.../upper' not supported as upperdir
```

## 3. 测试结果：哪些可行，哪些不行

### 测试矩阵

| Lower 目录所在 FS | Upper/Work 所在 FS | 结果 | 说明 |
|---|---|---|---|
| overlayfs (/) | overlayfs (/) | **失败** | "not supported as upperdir" |
| ext4 (/ssd1) | ext4 (/ssd1) | **通过** | 完美运行 |
| overlayfs (/) | ext4 (/ssd1) | **通过** | 混合模式可行！ |
| ext4 (/ssd1) | overlayfs (/) | **失败** | upper 必须在真实 FS 上 |
| overlayfs (/) | tmpfs | **通过** | tmpfs 是真实 FS |
| overlayfs (/) | /dev/shm (tmpfs) | **通过** | Docker 的共享内存 tmpfs 可用 |
| ext4 (/host_home) | ext4 (/host_home) | **通过** | 宿主机 bind mount 目录可用 |
| 任意 | loopback ext4 | **通过** | 需要 loop 设备可用 |

### 关键发现：Lower 目录无限制

内核仅校验 **upper** 和 **work** 目录。lower 目录可以在**任何**文件系统上，包括 overlayfs。这意味着：

```bash
# 以下命令可行 —— lower 在 overlayfs (/)，upper+work 在 ext4 (/ssd1)：
mount -t overlay overlay \
  -o lowerdir=/path/on/root/fs,upperdir=/ssd1/upper,workdir=/ssd1/work \
  /ssd1/merged

# 以下命令可行 —— lower 在 overlayfs (/)，upper+work 在 tmpfs：
mount -t overlay overlay \
  -o lowerdir=/path/on/root/fs,upperdir=/dev/shm/upper,workdir=/dev/shm/work \
  /dev/shm/merged
```

## 4. Docker 卷挂载类型与 Overlay 兼容性

### 4.1 Bind Mount（`-v /宿主机路径:/容器路径`）

```bash
docker run -v /host/data:/data myimage
```

- **Overlay 兼容**：是（容器内看到的是宿主机的真实文件系统，通常为 ext4/xfs）
- **已验证**：`/ssd1`（设备挂载）和 `/host_home`（宿主机 ext4 的 bind mount）均可用
- **持久化缓存存储的最佳选择**

### 4.2 Docker 命名卷（`--mount type=volume`）

```bash
docker run --mount type=volume,source=myvolume,target=/data myimage
```

- **Overlay 兼容**：是 —— Docker 卷存储在宿主机的真实文件系统上（通常在 `/var/lib/docker/volumes/`）
- **卷在容器内表现为真实 ext4/xfs 目录的 bind mount**

### 4.3 tmpfs 挂载（`--mount type=tmpfs`）

```bash
docker run --mount type=tmpfs,destination=/fast-cache,tmpfs-size=1G myimage
```

- **Overlay 兼容**：是
- **已验证**：新挂载的 tmpfs 和 `/dev/shm` 均支持 overlay 的 upper/work 目录
- **注意**：容器重启后数据丢失，不适合持久化缓存
- **性能**：顺序写入比 NVMe SSD 快约 25 倍（1.2 GB/s vs 47.9 MB/s，4K dsync）

### 4.4 设备挂载（`--device`）

```bash
docker run --device /dev/sdb:/dev/sdb myimage
# 容器内：mount /dev/sdb /mnt
```

- **Overlay 兼容**：是 —— 提供了真实的块设备
- **CI 环境中较少使用**

### 4.5 Docker 存储选项（`--storage-opt`）

```bash
docker run --storage-opt size=20G myimage
```

- **控制的是容器根文件系统的大小限制**（overlay2 + quota）
- **不会改变文件系统类型** —— 根目录仍是 overlayfs
- **对 overlay 嵌套无帮助**

### 总结：Docker 容器内可用的真实文件系统

| 挂载点 | 文件系统类型 | 可作为 Overlay 基底 | 来源 |
|--------|-------------|-------------------|------|
| `/` | overlayfs | 否（不可作为 upper） | Docker overlay2 驱动 |
| `/ssd1` | ext4 | 是 | 宿主机设备挂载 |
| `/host_home` | ext4 | 是 | 宿主机 bind mount |
| `/dev/shm` | tmpfs | 是（易失） | Docker 默认 |
| 任意 `-v` 挂载 | 宿主机 FS | 是 | 宿主机 bind mount |
| 任意命名卷 | 宿主机 FS | 是 | Docker 管理的卷 |
| 任意 tmpfs 挂载 | tmpfs | 是（易失） | `--mount type=tmpfs` |

## 5. 无真实文件系统时的替代方案

### 5.1 Loopback ext4 设备

创建文件，格式化为 ext4，通过 loop 设备挂载：

```bash
# 创建 1GB 的后备文件（可以在 overlayfs 上）
dd if=/dev/zero of=/tmp/cache.img bs=1M count=1024

# 设置 loop 设备（需要 /dev/loopN 存在）
mknod /dev/loop1 b 7 1       # 可能需要手动创建设备节点
losetup /dev/loop1 /tmp/cache.img

# 格式化并挂载
mkfs.ext4 -q /dev/loop1
mkdir -p /mnt/cache
mount /dev/loop1 /mnt/cache

# 现在可以在 /mnt/cache 上使用 overlay
mkdir -p /mnt/cache/{lower,upper,work,merged}
mount -t overlay overlay \
  -o lowerdir=/mnt/cache/lower,upperdir=/mnt/cache/upper,workdir=/mnt/cache/work \
  /mnt/cache/merged   # 成功
```

**前提条件**：
- 容器需要 `CAP_SYS_ADMIN` 权限（或 `--privileged`）
- `/dev/` 下需要有 loop 设备（可能需要 `mknod` 创建）
- 后备文件**可以**在 overlayfs 上 —— loop 设备抽象掉了底层 FS
- **已验证可行**

**局限性**：
- 固定大小（需预先分配）
- 部分 CI 环境禁止 `mknod` 或 `losetup`
- 增加延迟层（文件 → loop → ext4 → overlay）

### 5.2 fuse-overlayfs

```bash
# 安装（当前环境未安装）
apt-get install fuse-overlayfs   # 或：dnf install fuse-overlayfs

# 使用 —— 无需真实 FS
fuse-overlayfs -o lowerdir=lower,upperdir=upper,workdir=work merged
```

**优点**：
- 完全在用户态通过 FUSE 运行
- **不要求** upper/work 在真实文件系统上
- 无需 `CAP_SYS_ADMIN`（仅需 `/dev/fuse` 访问权限）
- 被 rootless Docker/Podman 使用

**缺点**：
- FUSE 带来的性能开销（用户态上下文切换）
- 需要额外安装（当前环境未安装）
- `/dev/fuse` 必须可用（当前环境**可用**：`crw-rw-rw- root root /dev/fuse`）

### 5.3 tmpfs 作为 Upper/Work 目录

**已验证可行**。无持久真实 FS 时最简单的降级方案：

```bash
# 方案 A：使用 /dev/shm（默认已存在，通常 64MB-64GB）
mkdir -p /dev/shm/overlay/{upper,work}
mount -t overlay overlay \
  -o lowerdir=/path/to/source,upperdir=/dev/shm/overlay/upper,workdir=/dev/shm/overlay/work \
  /path/to/merged

# 方案 B：挂载新的 tmpfs
mount -t tmpfs -o size=2G tmpfs /mnt/tmpfs
mkdir -p /mnt/tmpfs/{upper,work}
mount -t overlay overlay \
  -o lowerdir=/path/to/source,upperdir=/mnt/tmpfs/upper,workdir=/mnt/tmpfs/work \
  /path/to/merged
```

**取舍**：
- **易失**：容器重启后所有数据丢失
- **内存支撑**：占用 RAM（或 swap），受 `tmpfs-size` 和可用内存限制
- **极快**：写入 1.2 GB/s+（对比 NVMe SSD 的 4K 同步写约 48 MB/s）

## 6. Kubernetes / 云端 CI 影响

### 6.1 Kubernetes 卷类型

| 卷类型 | 文件系统 | Overlay 可用 | 持久性 |
|--------|---------|-------------|--------|
| `emptyDir: {}` | 容器根 FS（overlayfs） | **否** | Pod 生命周期 |
| `emptyDir: { medium: Memory }` | tmpfs | **是** | Pod 生命周期 |
| `hostPath` | 宿主机 FS（ext4/xfs） | **是** | 节点生命周期 |
| PVC（块设备） | ext4/xfs | **是** | 持久 |
| PVC（NFS） | NFS | **可能**（NFS v3 可行，v4 通常不行） | 持久 |
| `configMap`/`secret` | tmpfs | **是**（但只读） | Pod 生命周期 |

### 6.2 推荐的 Kubernetes 构建缓存配置

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: builder
    securityContext:
      privileged: true  # overlay mount 系统调用需要
    volumeMounts:
    - name: build-cache
      mountPath: /cache
    - name: overlay-workspace
      mountPath: /workspace-overlay
  volumes:
  # 方案 1：PVC（最佳持久共享缓存）
  - name: build-cache
    persistentVolumeClaim:
      claimName: build-cache-pvc

  # 方案 2：tmpfs emptyDir（易失但快速）
  - name: overlay-workspace
    emptyDir:
      medium: Memory
      sizeLimit: 4Gi

  # 方案 3：hostPath（节点级缓存）
  # - name: build-cache
  #   hostPath:
  #     path: /data/build-cache
  #     type: DirectoryOrCreate
```

### 6.3 CI 平台考量

| 平台 | 可用的真实 FS | 说明 |
|------|-------------|------|
| 自建 k8s | PVC、hostPath、emptyDir(Memory) | 灵活度最高 |
| GKE/EKS/AKS | PVC（pd-ssd、gp3 等） | 需要预配 PV |
| GitHub Actions | Runner 磁盘为真实 FS | 默认不在 Docker 内 |
| GitLab CI（Docker executor） | 仅 /dev/shm + 配置的卷 | 受限 |
| 百度 CI（当前环境） | `/ssd1`（NVMe ext4） | 理想选择 |

## 7. 构建缓存工具的决策树

```
是否有已挂载的真实文件系统（ext4/xfs/btrfs）？
├── 是（如 /ssd1、bind mount、PVC）
│   └── 用它作为 upper/work 目录。lower 目录可以在任何位置。
│       性能：约 48 MB/s（NVMe），跨构建持久化。
│
├── 否，但 tmpfs / /dev/shm 有足够空间？
│   └── 用 tmpfs 作为 upper/work 目录。
│       性能：约 1.2 GB/s，但**易失**（重启后缓存丢失）。
│
├── 无真实 FS，无 tmpfs 空间，但可以创建 loop 设备？
│   └── 创建 loopback ext4：
│       dd + losetup + mkfs.ext4 + mount
│       性能：有额外开销，但可用。文件持久则缓存持久。
│
├── 以上都不行，但有 fuse-overlayfs？
│   └── 使用 fuse-overlayfs（用户态 overlay，在任何 FS 上都能工作）。
│       性能：FUSE 开销，但兼容性最广。
│
└── 以上全部不可行
    └── 降级为 rsync/cp 全量复制（无 overlay）。
```

## 8. 环境检测脚本

构建缓存工具应运行以下脚本来自动选择最佳策略：

```bash
#!/bin/bash
# detect-overlay-capability.sh
# 返回可用的最佳 overlay 挂载策略

detect_overlay_strategy() {
    local target_path="${1:-/cache}"

    # 检查 1：目标路径是否在真实文件系统上？
    local fs_type
    fs_type=$(stat -f -c '%T' "$target_path" 2>/dev/null)

    case "$fs_type" in
        ext2/ext3|xfs|btrfs|ext4)
            echo "REAL_FS:$target_path"
            return 0
            ;;
        tmpfs)
            echo "TMPFS:$target_path"
            return 0
            ;;
    esac

    # 检查 2：是否有其他真实文件系统挂载？
    while IFS= read -r line; do
        local mnt_point fs
        mnt_point=$(echo "$line" | awk '{print $5}')
        fs=$(echo "$line" | awk '{print $9}')
        if [[ "$fs" == "ext4" || "$fs" == "xfs" || "$fs" == "btrfs" ]]; then
            echo "REAL_FS:$mnt_point"
            return 0
        fi
    done < /proc/self/mountinfo

    # 检查 3：能否使用 /dev/shm？
    if [ -d /dev/shm ] && [ -w /dev/shm ]; then
        local shm_size
        shm_size=$(df -BM /dev/shm | tail -1 | awk '{print $4}' | tr -d 'M')
        if [ "$shm_size" -gt 1024 ]; then  # 可用空间 > 1GB
            echo "TMPFS:/dev/shm"
            return 0
        fi
    fi

    # 检查 4：能否创建 loop 设备？
    if command -v losetup &>/dev/null && [ -w /dev ]; then
        echo "LOOPBACK"
        return 0
    fi

    # 检查 5：fuse-overlayfs 是否可用？
    if command -v fuse-overlayfs &>/dev/null && [ -c /dev/fuse ]; then
        echo "FUSE_OVERLAY"
        return 0
    fi

    echo "NONE"
    return 1
}

detect_overlay_strategy "$@"
```

## 9. 性能基准测试

在当前环境实测（4K 块大小，dsync 写入，10000 块 = 40MB）：

| 存储后端 | 写入速度 | 相对基准 | 持久化 |
|----------|---------|---------|--------|
| ext4 on NVMe (`/ssd1`) | 47.9 MB/s | 1.0x（基准） | 是 |
| overlay on ext4 | 47.4 MB/s | 0.99x | 是 |
| tmpfs 直写 | 1,200 MB/s | 25x | 否 |
| overlay on tmpfs | 1,300 MB/s | 27x | 否 |

**核心结论**：Overlay 层的性能开销可以忽略（约 1%）。底层存储的选择远比 overlay 层本身重要。

## 10. 构建缓存工具推荐架构

```
容器文件系统布局：
/                          (overlayfs - Docker 根目录 - 不能在此创建 overlay upper)
├── /ssd1/                 (ext4 NVMe - 最佳 overlay upper/work 位置)
│   └── /ssd1/build-cache/
│       ├── shared/        (lower：来自之前构建的只读共享缓存)
│       ├── upper/         (upper：当前构建的修改)
│       ├── work/          (work：overlay 内部使用)
│       └── merged/        (merged：构建进程看到的工作目录)
├── /dev/shm/              (tmpfs - 易失 overlay 的降级方案)
└── /workspace/            (在 overlayfs 根上 - 源代码放这里作为 LOWER 完全没问题)
```

构建工具应当：
1. **自动检测**可用的真实文件系统（使用上述检测脚本）
2. **使用真实 FS** 作为 upper/work 目录（持久化缓存）
3. **源代码**在 overlayfs (/) 上作为 **lower** 目录完全没问题
4. **降级方案**：无真实 FS 时使用 tmpfs（易失但功能正常）
5. **最后手段**：loopback ext4 或 fuse-overlayfs
