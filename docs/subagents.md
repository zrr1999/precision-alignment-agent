# 核心子 Agent 能力说明


## P - 修复规划师 (Planner)

- **输入**：`paddle_path` / `pytorch_path`、目标 `api_name`、Locator 报告或验证结果（基线通过/失败、Validator 拒绝原因等），以及会话/记忆路径（`session_id`）。
- **职责**：只负责**小循环 AD（A→D）**（规划 → Aligner → Diagnostician，最多 5 轮），在当前功能分支上，根据定位与记忆制定修复路线，按计划协调并依次调用 Aligner、Diagnostician（AD 循环）；不负责选择或切换 Git 分支。
- **输出**：一轮 AD 的修复计划与执行摘要、需要下一轮验证/规划的结论，以及写入 `.paa/sessions/{session_id}/planner/...` 的简要报告。



## L - 源码定位官 (Locator)

- **输入**：`paddle_path` 和/或 `pytorch_path`，目标 API 名（或明确的文件/作用域），以及 `session_id`。
- **职责**：从高层 API 出发，静态追踪到 CUDA/CPU 内核，分别梳理前向与反向路径，只读分析、不改代码、无 bash、不 spawn。
- **输出**：包含层次结构、前向/反向完整路径（文件:行号）、可读伪代码、精度关键点与风险、相关 API 与推荐修复入口的报告，并写入 `.paa/sessions/{session_id}/locator/...`。



## V - 精度验证师 (Validator)

- **输入**：Paddle 相关仓库路径（`paddle_path`、`paddletest_path` 等）、`api_name`、待跑的 config 或 config 文件、`VENV_PATH` 以及 `session_id`。
- **职责**：直接使用 `just agentic-run-precision-test` 跑基线与修复后测试，分析失败/回归模式；**不负责检查或切换 Git 分支**。
- **输出**：基线与修复后精度结果的对比（通过/失败/回归数量与代表性 case）、模式与下一步建议；并将基线/修复/拒绝等结果写入 `.paa/sessions/{session_id}/validator/...`。



## D - 故障诊断官 (Diagnostician)

- **输入**：`paddle_path`（及其 build 目录）、`VENV_PATH`、`api_name`、必要时 `PADDLETEST_PATH` 和 `session_id`。
- **职责**：在 build 目录配置并编译 Paddle，使用 `just agentic-paddle-build-and-install` 完成构建与安装；对编译/运行时故障做分级诊断，简单问题直接修复，复杂问题整理上下文后升级给 Aligner，并在每轮 AD 后用 Just 跑冒烟或指定测试。
- **输出**：构建/安装状态、故障类型与关键信息、已尝试修复与是否升级的信息，以及写入 `.paa/sessions/{session_id}/diagnostician/...` 的诊断报告。



## A - 精度对齐师 (Aligner)

- **输入**：明确的目标 `api_name`，要修改的文件/函数位置，来自 Locator/Validator/D 的精度问题描述（如 dtype 提升、累加顺序、常数差异等），以及 `session_id`。
- **职责**：在 `*.cu`/`*.cuh`/`*.cc`/`*.h` 中对前向/反向实现做**最小化变更**，以实现 Paddle 与 PyTorch 的数值/比特级对齐，优先保证正确性，其次关注性能与兼容性，不负责构建/测试/git。
- **输出**：本轮修改涉及的文件/函数、解决的精度问题与预期影响（包括可能的性能/兼容性影响），并写入 `.paa/sessions/{session_id}/aligner/...` 的对齐报告。



## R - 评审官 (Reviewer)

- **输入**：`paddle_path`、`PADDLETEST_PATH`、`VENV_PATH`、`api_name`、各子 Agent 的会话报告（尤其是 V/D/A）、目标 PR 分支名及 `session_id`。
- **职责**：独立复核编译（含 `just agentic-verify-paddle-install`）、精度（重跑部分高信号 config）、CI/CE（unittest + PaddleTest）、性能与兼容性；根据结果决定是生成完整 PR、带限制说明的 PR，还是只写失败报告。
- **输出**：最终验收结论（成功/部分成功/失败）、若成功则对应 PR（分支、标题、正文）及其 URL，若失败则写入 `.paa/sessions/{session_id}/reviewer/{api_name}/failure_report.md` 的失败报告。



# 工作流程架构（主 Agent 视角）

- **初始化**：用户输入 → API 识别 → 建立测试基线（V）。
- **分析**：L（Paddle + PyTorch）→ 逻辑伪代码与精度关键点 → 汇总给 P。
- **小循环 AD（A→D，P 协调，最多 5 次）**：P 规划 → A 改代码 → D 构建+冒烟；编译失败则 D 简单修或升级 A，通过则提交并退出。
- **大循环 PV（P→V，主 Agent 驱动多轮，最多 10 次）**：对比/验证结果 → P 再规划 → V 精度验证 → 未过则重复，过则交 R。
- **终审**：R 独立验证（不采信子 Agent 报告）→ 满足则 PR，否则价值评估 → 部分成功则 PR 注明未完成，无价值则失败报告。知识沉淀通过各子 Agent 的 paa-knowledge-curation 与 `.paa/sessions`/`.paa/memory` 完成，无单独 K Agent。



# 成功标准

1. 数值精度与 PyTorch 对齐，PaddleAPITest 相关 case 通过。
2. 无编译错误与功能回归。
3. 性能无明显下降（需 FLAG 或说明时由 R 标注）。

R 负责最终独立验证上述标准。



# 输出物

1. 修复后的内核/算子代码（A）
2. 精度验证报告（V）
3. 性能与兼容性说明（R 验证）
4. 剩余问题记录（若有）
5. PR 或失败报告（R）：分支 `precision-alignment-agent/{api_name}`，标题 `[PAA][Precision Depth Alignment] {title}`，正文符合模板
6. 会话与长期记忆：`.paa/sessions/`、`.paa/memory/`（各子 Agent 通过 skill 与报告写入）
