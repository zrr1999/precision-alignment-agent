# 核心子 Agent 能力说明

## **P - 修复规划师 (Planner)**

### 输入信息
在调用时，需要提供以下信息
- 代码库的路径
- 源码分析报告

### 核心能力
- 必须具备文件读取能力（read/glob/grep）
- 必须具备网络搜索能力（websearch/webfetch）

### 核心职责
- 创建本地分支：
  1. **确保基准分支保持最新**：基准分支为 `PAA/develop`，需要保持他在开发前与远程仓库develop分支同步，通常使用 `git pull upstream develop` 更新。
  2. **创建本地分支**：分支命名格式为 `precision-alignment-agent/{api_name}`，例如 `precision-alignment-agent/pow`、`precision-alignment-agent/layer_norm`
- 制定修复路线图
- 安排实施优先级
- 适应测试反馈调整计划

## **L - 源码定位官 (Locator)**

### 输入信息
在调用时，需要提供以下信息：
- 代码库的路径或链接（代码库的路径或链接不存在时，需要给出提示，表明代码库路径或链接不存在）
- 需要分析的目标内容（目标内容不存在时，需要给出提示，表明目标内容不存在）

### 核心能力
- 必须具备文件读取能力（read/glob/grep）
- 必须具备网络搜索能力（websearch/webfetch）

### 核心职责
- 深度理解给定代码库源码结构
- 分析指定 API 的完整代码路径：API → 中间层 → CUDA Kernel，注意实现分为前向和反向
- 生成可读性强的计算逻辑伪代码
- 识别精度关键点（计算顺序、类型转换、数值处理）
- 标注注意事项和潜在精度风险


## **V - 精度验证师 (Validator)**

- 熟练使用 PaddleAPITest 进行精度对齐测试，这是精度对齐的核心验证工具
- 测试出现错误可能是前向问题，也可能是反向问题，如果有前向问题通常意味着反向也有问题
- 具备 case 筛选、抽样和分析能力
- 支持 inorder 日志搜索和分析
- 精度错误模式识别和根因分析
- 建立精度基线、验证修复效果、分析精度差异

**D - 故障诊断官 (Diagnostician)**

- 定位和分析编译、运行时等各类故障，分类故障类型（简单/复杂、编译/运行时）
- 提供修复建议或升级报告，确保 Patch 不存在漏洞和风险
- **负责编译和安装流程**：
  - 配置和构建 Paddle：`cmake .. -DPADDLE_VERSION=0.0.0 -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DPY_VERSION=3.10 -DCUDA_ARCH_NAME=Ampere -DWITH_GPU=ON -DWITH_DISTRIBUTE=ON -DWITH_UNITY_BUILD=OFF -DWITH_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DWITH_CINN=ON -GNinja`
  - 执行编译：`ninja -j$(nproc)`
  - **编译完成后，在虚拟环境中使用 `uv pip install` 安装编译产物**，确保修改后的代码可以被测试使用
- **负责 CI/CE 流程测试**：运行 Paddle 内部单测（直接运行 Python 测试文件）和 PaddleTest 仓库测试（在 `framework/api/paddlebase` 目录下使用 pytest），验证功能正确性和回归问题

**A - 精度对齐师 (Aligner)**

- 精准修改 CUDA Kernel 等数值关键实现
- 处理数值精度对齐问题
- 确保行为与向后兼容性
- TODO: 添加更多skills，包括向后兼容性yaml文件，修改签名等
TODO：
- 添加指导，比如兼容性FLAG以及在什么情况下添加。
- 性能对比方法，按照什么流程（uv pip old 测试输出报告，uv pip new 测试输出报告，TODO 可以做成工具）
- 提交代码，在开发过程中注意及时提交代码。

**R - 评审官 (Reviewer)**

- **最终验收与评审**：流程结束后的最终验收，综合评估是否满足成功标准
- **独立验证**：参考子 Agent 报告但不完全信任，需独立验证以下内容：
  - 验证编译是否真正成功（检查编译日志和产物）
  - 验证 PaddleAPITest 精度测试是否真正通过（运行相关测试用例）
  - 验证 CI/CE 测试是否通过（运行 Paddle 内部单测和 PaddleTest）
  - 验证性能是否无明显下降（对比修复前后性能数据）
  - 评估数值精度是否真正对齐（检查精度测试结果）
- **价值评估**：判断不完整解决方案的价值，识别可保留的改进点
- **PR 生成流程**：
  1. **生成 PR 标题**：格式为 `[PAA][{type}] {title}`
     - `{type}` 为具体类型，通常为 `Precision Depth Alignment`
     - `{title}` 为具体标题，描述修改了哪些 API 或更具体的 Kernel、公共函数等
     - 示例：`[PAA][Precision Depth Alignment] Fix layer_norm precision alignment with PyTorch`
  2. **生成 PR 描述**：
     - 符合 `.github/PULL_REQUEST_TEMPLATE.md` 标准
     - 重点描述修改了哪些 API 或更具体的 Kernel、公共函数等，尽可能详细
     - 描述 CI/CE 测试（单测和 PaddleTest）和 PaddleAPITest 精度测试的测试情况
     - 使用中文编写
     - 如部分成功，需明确标注未完成工作及原因
  3. **推送并创建 PR**：推送分支到远程仓库并创建 Pull Request
- **失败报告**：如完全失败，生成详细的失败报告，说明失败原因和已尝试的修复方案


# 工作流程架构

## 初始化阶段

```
用户输入 → API 识别 → 测试基线建立
```

## 精度测试阶段

```
V(精度验证师) → 精度基线建立和故障模式分析
```

## 分析对比阶段

由协调员对精度测试结果进行分析，是否需要进行修复，需要修复则进行
```
PyTorch 分析链：L → 逻辑伪代码 + 实现细节
Paddle 分析链：L → 逻辑伪代码 + 实现细节
```
然后汇总详细结果提供给修复规划师。

## 修复阶段

### 小循环 FGE（计划-修改-编译）
P 应该要求 K 提供知识指导。

最大循环次数：5

```
P(当前计划) → A(内核修改) → D(编译验证)
    ↓
  编译失败 → 简单错误 → D直接修复
    ↓
  编译失败 → 复杂错误 → A理解问题并尝试修复(恢复会话)
    ↓
  编译成功 → 退出小循环
```

### 大循环 DFC（修复-验证-对比）
修复代表FGE，最大循环次数：3。

```
C(对比分析) → P(修复计划) → V(精度验证)
    ↓
  修复效果评估
    ↓
  未通过 → 重复DFC
    ↓
  通过 → R(最终评审)
```

TODO：需要复用 V 的上下文

## 最终评审阶段

```
R(评审官) 收集子 Agent 报告：
  - D: 编译状态报告、CI/CE 测试报告（单测和 PaddleTest）
  - V: PaddleAPITest 精度测试报告
  - A: 性能对比数据
  - C: 整体修复总结
    ↓
R 独立验证和评估（不信任子 Agent 报告，需亲自验证）：
  - 验证编译是否真正成功（检查编译日志和产物）
  - 验证 PaddleAPITest 精度测试是否真正通过（运行相关测试用例）
  - 验证 CI/CE 测试是否通过（运行 Paddle 内部单测和 PaddleTest）
  - 验证性能是否无明显下降（对比修复前后性能数据）
  - 评估数值精度是否真正对齐（检查精度测试结果）
    ↓
  满足成功标准？
    ↓
  是 → 生成 PR（成功版本）
      1. 创建本地分支：precision-alignment-agent/{api_name}
      2. 提交代码到分支
      3. 生成 PR 标题：[PAA][Precision Depth Alignment] {title}
      4. 生成 PR 描述（符合模板，使用中文，详细描述修改和测试情况）
      5. 推送分支并创建 PR
      6. 监控 PR 的 CI/CE 流水线是否通过
    ↓
  否 → 评估不完整方案是否有价值？
    ↓
  有价值 → 生成 PR（标注未完成工作及原因）
      1. 创建本地分支：precision-alignment-agent/{api_name}
      2. 提交代码到分支
      3. 生成 PR 标题和描述（明确标注未完成工作及原因）
      4. 推送分支并创建 PR
    ↓
  无价值 → 生成失败报告
      详细说明失败原因和已尝试的修复方案
    ↓
K(知识沉淀官) 知识沉淀（无论成功或失败都执行）：
  - 收集所有子 Agent 的完整上下文和报告
  - 提取成功/失败的修复模式和经验教训
  - 总结 API 精度对齐的通用方法和最佳实践
  - 按 API 类型、问题类型等维度组织知识
  - 持久化到项目级知识库（knowledge/ 目录）
  - 更新知识库索引，支持后续检索
```

# 成功标准

1. 数值精度与 PyTorch 对齐（可能需要合理添加case），PaddleAPITest 相关 case 全部通过
2. 无编译错误和回归问题
3. 性能无明显下降（性能下降需要使用FLAG，这个应该在修改前就可以预测，可以找一个Agent来承担这个职责）

**注**：R - 评审官负责最终验证上述标准是否真正满足，参考子 Agent 报告但需独立评估。

# 输出物

1. 修复后的 CUDA Kernel 代码
2. 精度对齐验证报告
3. 性能对比数据
4. 剩余问题记录（如有）
5. **PR（由 R - 评审官生成）**：
   - **分支命名**：`precision-alignment-agent/{api_name}`（例如 `precision-alignment-agent/pow`）
   - **PR 标题格式**：`[PAA][Precision Depth Alignment] {title}`
   - **PR 描述**：符合模板标准，使用中文，详细描述修改和测试情况
   - **成功版本**：满足所有成功标准，包含完整的修改描述和测试结果
   - **部分成功版本**：有价值但不完整，明确标注未完成工作及原因
   - **失败报告**：完全失败时的详细分析，说明失败原因和已尝试的修复方案
6. **知识库沉淀（由 K - 知识沉淀官生成）**：
   - **知识文档**：存储在 `knowledge/` 目录下的结构化知识文档
   - **成功模式库**：记录有效的精度对齐方法和代码修改技巧
   - **失败教训库**：记录常见错误和避免方法
   - **API 分类知识**：按 API 类型总结的共性方法和最佳实践
   - **知识索引**：支持按 API 类型、问题类型、修复方法等维度检索

# 工具/能力需求（legacy）

1. **PaddleAPITest Tool** - case 管理、测试执行、结果分析
3. **编译环境** - 可重复编译验证
4. **日志分析系统** - inorder 日志搜索和模式识别
