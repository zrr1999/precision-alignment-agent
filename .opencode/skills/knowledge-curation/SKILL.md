---
name: paa-knowledge-curation
description: Curate, read, and persist precision-alignment knowledge into `.paa-knowledge/`, organized by report category for Planner, Diagnostician, and Validator. This skill is used directly by agents (for example, the Planner) to query and update the knowledge base.
---

# `.paa-knowledge/` directory layout

All knowledge generated during precision-alignment tasks MUST be persisted under the repository root directory `.paa-knowledge/`, organized by **report category**:

- **Precision comparison reports** (owned by `Planner`)
  - Path: `.paa-knowledge/precision-comparison/`
  - Content: Paddle vs PyTorch behavior/precision comparison, gap analysis, patterns, fix priorities, and decision records.
- **Basic diagnosis reports** (owned by `Diagnostician`)
  - Path: `.paa-knowledge/basic-diagnosis/`
  - Content: compilation/runtime error categories, unit/CI/CE diagnostics, high-value failure examples, and debugging paths.
- **Precision testing reports** (owned by `Validator`)
  - Path: `.paa-knowledge/precision-testing/`
  - Content: PaddleAPITest precision results, error patterns, clustered failing cases, and baseline vs fixed comparisons.

Each category directory is further grouped by API name:

- `.paa-knowledge/precision-comparison/{api_name}/`
- `.paa-knowledge/basic-diagnosis/{api_name}/`
- `.paa-knowledge/precision-testing/{api_name}/`

For example:

```text
.paa-knowledge/
  precision-comparison/
    paddle.pow/
      20260129-1030_initial-gap-analysis.md
  basic-diagnosis/
    paddle.pow/
      20260130-0930_ci-failures-on-gpu.md
  precision-testing/
    paddle.pow/
      20260131-1415_paddleapitest-baseline.md
```

# File naming and metadata

Within each `{api_name}` directory, each report is a standalone Markdown file.

Recommended filename pattern:

- `{yyyyMMdd-HHmm}_{short-title}.md`, for example:
  - `.paa-knowledge/precision-comparison/paddle.pow/20260129-1030_initial-gap-analysis.md`

Each report SHOULD start with a minimal YAML frontmatter block to support later search and aggregation:

```markdown
---
api: paddle.pow
category: precision-comparison    # or: basic-diagnosis | precision-testing
owner: P                         # P | D | V
created_at: 2026-01-29T10:30:00+08:00
tags: [broadcast, float32, gpu, backward]
summary: Short, outcome-focused summary of the key finding or lesson.
---
```

The body after the frontmatter is free-form Markdown, but should ideally include:

- **Summary & recommendations** (top of file)
- **Key observations / logs / configs / commands**
- **Representative failing / passing examples**
- **Reusable debugging / fixing procedures**

# Reading knowledge (used by agents)

When starting or updating a precision-alignment task, agents (typically `Planner`, `Diagnostician`, or `Validator`) use this skill to query existing knowledge:

- Search within the relevant category directories using `glob` + `grep` (or equivalent) by:
  - `api` name
  - file path (e.g., `paddle.pow`)
  - tags (e.g., `broadcast`, `float16`, `grad`, `gpu`)
- Prioritize:
  - Reports for the **same API**
  - Reports for **related operator families** (e.g., normalization, activation, reduction, elementwise, etc.)
- Extract and summarize:
  - Common error or precision patterns and validated fix strategies
  - Known pitfalls to avoid (e.g., specific shapes/dtypes/devices that are fragile)
  - Proven testing combinations (Paddle unit tests, PaddleTest, PaddleAPITest) that catch real issues

The output of this reading step should be a **short, actionable knowledge brief** that can be fed into planning or diagnosis:

- 3–7 bullet points of key lessons and constraints
- Explicit links to the most relevant report files

# Writing and updating knowledge (multi-agent collaboration)

At the end of a task (or when an intermediate milestone produces high-value insight), agents MUST persist knowledge into `.paa-knowledge/` via this skill.

Responsibilities by agent:

- **Planner → precision comparison reports**
  - Provides: comparison conclusions, fix decisions, prioritization, trade-offs, and open questions.
  - Writes/updates files under `.paa-knowledge/precision-comparison/{api_name}/...`.
- **Diagnostician → basic diagnosis reports**
  - Provides: key error patterns, triggers, minimal repro cases, recommended debugging steps.
  - Writes/updates files under `.paa-knowledge/basic-diagnosis/{api_name}/...`.
- **Validator → precision testing reports**
  - Provides: PaddleAPITest results, error clustering, precision gap analysis, baseline vs fixed comparison.
  - Writes/updates files under `.paa-knowledge/precision-testing/{api_name}/...`.

When writing or updating reports, agents should:

- Prefer **updating an existing file** for the same API and topic when appropriate (search with `glob` + `grep` first) instead of blindly creating many near-duplicate files.
- Use consistent section structure where possible, for example:
  - `Summary`
  - `Context`
  - `Key Findings`
  - `Reproduction`
  - `Fix Strategy`
  - `Verification`
- Maintain a stable, reusable **tag vocabulary** in the frontmatter to enable automated querying and aggregation.

---
name: paa-knowledge-curation
description: Read and persist precision-alignment knowledge into .paa-knowledge/, organized by report category for Planner, Diagnostician, and Validator.
---

# `.paa-knowledge/` 知识库结构

所有与精度对齐任务相关的沉淀知识统一保存在仓库根目录下的 `.paa-knowledge/` 目录中，并按「报告类别」拆分为子文件夹：

- 精度对比报告（由 Planner 管理）
  - 目录：`.paa-knowledge/precision-comparison/`
  - 内容：Paddle vs PyTorch 的精度/行为对比结论、模式归纳、修复优先级和决策记录
- 基本测试诊断报告（由 Diagnostician 管理）
  - 目录：`.paa-knowledge/basic-diagnosis/`
  - 内容：编译/运行错误分类、单测/CI/CE 诊断结果、高价值失败样例和排查路径
- 精度测试报告（由 Validator 管理）
  - 目录：`.paa-knowledge/precision-testing/`
  - 内容：PaddleAPITest 精度结果、误差模式、失败用例聚类、基线与修复后对比

# 文件命名与元信息约定

在每个子目录下，每一份知识/报告对应一个独立的 Markdown 文件，推荐命名格式：

- `{$api_name}/{$category}/{$yyyymmdd-HHMM}_{short-title}.md`，例如：
  - `.paa-knowledge/precision-comparison/paddle.pow/20260129-1030_initial-gap-analysis.md`

推荐在文件开头使用简单的 YAML frontmatter，方便后续检索和聚合：

```markdown
---
api: paddle.pow
category: precision-comparison | basic-diagnosis | precision-testing
agents: [P, D, V]
created_at: 2026-01-29T10:30:00+08:00
tags: [broadcast, float32, gpu, backward]
summary: 简要描述本报告的核心结论或教训
---
```

frontmatter 之后为自由格式正文，可以包含：

- 结论 & 建议（优先）
- 关键日志/配置/命令
- 典型失败/成功样例
- 可复用的排查/修复流程

# 读取知识的使用方式（Curator 主导）

在每个精度对齐任务开始阶段，Curator 使用本 skill 读取历史知识：

- 根据当前目标 API / kernel 名称，在三个子目录中按 `api`、文件名和标签进行搜索（使用 `glob` + `grep`）
- 优先返回：
  - 同一 API 的历史报告
  - 相同算子类别（如归一化、激活、reduce、elementwise 等）的高相关报告
- 抽取并总结：
  - 常见误差模式和已验证的修复策略
  - 已踩过的坑和需要提前规避的问题
  - 已验证有效的测试/验证组合（Paddle 单测、PaddleTest、PaddleAPITest）

# 写入/更新知识的使用方式（多 Agent 协同）

在一次完整任务结束（或形成阶段性高价值信息）后，Curator 协调各 Agent 将知识沉淀到 `.paa-knowledge/`：

- Planner（精度对比报告）
  - 提供：对比分析结论、修复决策过程、优先级和权衡
  - 由 Curator 归档到 `.paa-knowledge/precision-comparison/{$api_name}/...`
- Diagnostician（基本测试诊断报告）
  - 提供：关键错误模式、触发路径、最小复现、推荐排查步骤
  - 由 Curator 归档到 `.paa-knowledge/basic-diagnosis/{$api_name}/...`
- Validator（精度测试报告）
  - 提供：PaddleAPITest 结果、失败 case 聚类、精度差异分析、基线与修复对比
  - 由 Curator 归档到 `.paa-knowledge/precision-testing/{$api_name}/...`

Curator 在写入时应做到：

- 尽量使用结构化的小节（如「结论」「关键现象」「复现步骤」「建议」）
- 复用/更新同一 API 既有文件而不是无控制地新增重复报告（通过 `grep` 查重后选择「更新」或「新建」）
- 在 frontmatter 中维护统一的标签体系，便于后续自动检索和统计

