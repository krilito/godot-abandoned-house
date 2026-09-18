# AI 项目研发协议 · 完整细则

本文件是 game-dev-protocol 技能的完整参考。SKILL.md 是执行摘要；本文件用于需要细则时加载（设计文档模板、完整要求清单、边界规定）。

---

## §1 C 类任务设计文档模板

复杂功能/架构修改（Inventory、Save/Load、Quest、战斗、AI 系统、大型交互框架、改核心数据结构、改系统间接口）必须先写设计文档并存入 `docs/`，用户确认后再写代码。实现中设计变化必须同步修改文档，禁止代码与文档长期不一致。

```markdown
# <功能名> 设计文档
## 1. 目标
## 2. 非目标（明确不做什么）
## 3. 当前架构（相关既有系统现状）
## 4. 新架构
## 5. 数据流
## 6. 节点/模块职责
## 7. 文件变化（新增/修改/删除清单）
## 8. 接口变化
## 9. 测试方案（分层：unit/scene/runtime/regression）
## 10. 兼容性风险
```

## §2 修改前必须先理解现有代码

不要看到任务就创建新脚本。先：搜索现有代码→查类似功能→查相关 Scene/Node/Script→查调用关系→查编码风格→查现有测试→查 Git 状态。
优先**扩展现有机制**，而不是另造一套类似机制。例：项目已有 `Player → InteractionRay → Interactable → interact()`，新 Door 必须进这个体系；除非现有体系确实无法满足，否则禁止另建 DoorRay/DoorInteractionManager 等平行系统。

## §3 严格控制修改范围

开工前列出：
```
EXPECTED_FILES_TO_CHANGE
EXPECTED_FILES_TO_ADD
FILES_THAT_SHOULD_NOT_CHANGE
```
禁止修改任务无关文件；扩大范围需先说明理由。不要为小功能顺便重构 Player、批量重命名、调整整个目录、改写其他系统或格式化全项目。遵守 minimum necessary change。

## §4 分层测试策略

- **Unit**：纯函数、数值算法、状态转换、Inventory 数据操作、数据解析。
- **Scene/Integration**：Godot 节点、玩家交互、Door、Item、UI、碰撞、动画、场景生命周期。例：Door 验证 `交互 → door.interact() → AnimationPlayer → 门旋转 → 碰撞跟随`。
- **Runtime/Play**：涉及真实游戏行为必须实际运行（启动游戏→移动到门前→对准→按 E→门开→玩家通过）。不能因为"没有语法错误"就宣布成功。
- **Regression**：改过的系统必须验证原有功能仍工作（改交互系统不仅要测 Door，还要验证 Key 能拾取、UI 提示正常、玩家移动正常、原 Interactable 正常）。

## §5 测试数量服从风险

不为凑数造无价值 getter 测试。必须覆盖：正常路径、边界情况、快速重复输入、非法状态、原有功能回归。例 Door：正常按 E / 动画中重复按 E / 动画结束再按 E / 碰撞是否跟随 / 门洞是否可通过。

## §6 优先实际运行，不猜测

有 MCP/终端/GUI 控制/键鼠模拟时优先用它们验证真实行为。流程：修改→启动项目→读 stdout/stderr→读错误堆栈→进入对应场景→模拟输入（WASD、视角、E、Esc、UI 点击）→观察结果→修复。不要只读代码就说"应该可以工作"。

## §7 MCP 是增强工具，不是硬依赖

MCP/GUI 工具可用则优先用；不可用时**明确区分 STATIC_VERIFIED 与 RUNTIME_VERIFIED**，如实说明未完成真实运行验证，不得假装做过。

## §8 Debug 必须基于证据

优先收集：Error message、Stack trace、Scene tree、Node path、Runtime state、相关代码、Git diff。流程：复现→获取错误→定位原因→最小修复→重新运行→回归测试。禁止"猜一个原因→改十个地方→看能不能好"。

## §9 Git 作为安全边界

重要修改前 `git status` 确认工作区，避免覆盖用户未提交修改。普通功能：clean state→feature change→tests→commit。复杂功能可用 `feature/<name>` 分支。Commit 小而明确：`feat: add door open animation` / `test: add door interaction regression` / `fix: prevent repeated door animation trigger`。禁止把十几个无关功能塞进一次 commit。

## §10 禁止危险 Git 操作

未经用户明确允许禁止 `git reset --hard`、`git clean -fd`、`git checkout -- .` 及任何可能删除用户工作成果的操作。撤销优先用：diff、恢复指定文件、新 commit 修正。保留可追踪历史。

## §11 目录职责

```
scenes/{levels,player,interactables,ui}
scripts/{player,interactables,systems,ui}
assets/{models,textures,materials,audio,animations}
tests/
docs/
```
禁止 scripts2/、new_scripts/、misc/、temp/、test2/、door_new_final/ 这类目录。

## §12 单一职责

Player=移动/输入/自身状态；Door=门自身交互和状态；Inventory=物品状态；UI=显示。禁止把所有功能写进 player.gd，禁止 Door 管理 Inventory UI/Quest/玩家移动。系统间通过明确接口通信。

## §13 统一编码规范（GDScript）

变量/函数 snake_case；类 PascalCase；常量 UPPER_SNAKE_CASE。优先类型标注（`var is_open: bool = false`）。函数尽量短、一个函数一个主要职责。避免巨型函数、无意义全局变量、魔法数字、重复代码、无解释硬编码 NodePath、无意义 abstraction。

## §14 禁止过度设计（YAGNI）

简单任务保持简单。`door.gd + AnimationPlayer` 能清楚完成需求就用它，不要创建 DoorManager/Repository/Factory/StateMachine/EventBus/Service。

## §15 文档与代码同步

C 类文档存入 `docs/`，至少含：Purpose、Architecture、Responsibilities、Public Interfaces、Important Constraints、Testing Strategy。代码改变 API/场景结构/数据结构/核心行为时必须同步更新文档，不留过期说明。

## §16 完成前必须验证

不能因为"代码写完"就宣布 COMPLETE。按任务范围逐项执行：Build/Parse、Unit、Integration、Runtime、Regression、Git diff 检查。

## §17 最终汇报必须提供证据

禁止只回 "Done."。必须包含：CHANGED（文件清单）/ IMPLEMENTATION（实际方式）/ TESTS（实际执行结果，如 unit 12/12 PASS）/ RUNTIME（是否真实运行+看到什么，如 "Player looked at Puerta, E interaction detected, open animation completed"）/ GIT（分支、commit、工作区状态）/ UNVERIFIED（仍未验证的内容）。推测正确≠PASS。

## §18 不擅自扩大任务

实际项目与任务描述不符（节点不存在、API 不同、场景结构变了、测试暴露更大架构问题）时：收集证据→描述冲突→判断能否最小修复。需要重大架构调整时停止小任务，升级为 C 类先更新设计再继续。

## 核心开发循环

```
理解现状 → 分类任务 → 锁定修改范围 → 设计/测试 → 最小实现 → 运行
→ 读取日志和错误 → 修复 → 回归验证 → 检查 Git diff → 更新必要文档
→ 提交 → 报告证据
```

最终原则：不只追求"这次能跑"，要做到能运行、能验证、能回滚、能维护、下一位 AI 能继续理解。
