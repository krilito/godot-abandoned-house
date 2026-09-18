---
name: game-dev-protocol
description: 游戏项目长期维护的工程协议。在进行任何游戏项目功能开发、Bug 修复、调试、验证或汇报时应用本协议：任务三分类（A微小修改/B普通功能/C复杂功能）、修改范围锁定、分层测试（unit/scene/runtime/regression）、通过 Godot AI MCP 做真实运行验证、以及证据式最终汇报。当用户要求实现功能、修复问题、检查项目状态、"能不能用"类验证任务时使用。
when_to_use: 游戏项目中的任何代码修改、功能实现、Bug 调试、运行时验证任务
---

# Game Dev Protocol

## Overview

参与长期维护的游戏项目时，目标不只是"本次功能能用"，而是能运行、能验证、能回滚、能维护。本协议规定每个任务的标准流程。

## 核心流程（每个任务必须走完）

```
理解现状 → 分类任务(A/B/C) → 锁定修改范围 → 设计/测试计划 → 最小实现
→ 实际运行 → 读日志和错误 → 修复 → 回归验证 → 检查 diff → 证据式汇报
```

## 第 1 步：任务分类（改代码前必须先做）

| 类 | 例子 | 要求 |
|---|---|---|
| **A 微小修改** | 改文字/数值/动画时长/材质参数 | 检查上下文→最小修改→必要验证。不造复杂文档 |
| **B 普通功能** | 加一扇门/拾取物/UI 按钮/玩家动作/局部 Bug | 先理解现有实现→声明修改范围→复用已有架构→加测试→运行验证→回归→保留可回滚节点 |
| **C 复杂功能/架构** | Inventory/存档/任务/战斗系统、改核心数据结构 | **先写设计文档再写代码**（模板见 references/protocol.md §1），用户确认后才实现；实现中设计变化必须同步改文档 |

分类结果和理由要用一两句话告诉用户。

## 第 2 步：理解现状 + 锁定范围

- 先搜索现有代码/场景/脚本，**扩展现有机制，绝不另造一套类似机制**（例：项目已有 `Player→射线→Interactable→interact()` 交互链，新 Door 必须进入这个体系）。
- 开始前列出 `EXPECTED_FILES_TO_CHANGE / EXPECTED_FILES_TO_ADD / FILES_THAT_SHOULD_NOT_CHANGE`。
- 禁止顺手重构、批量重命名、格式化整个项目。
- 有 Git 的项目：改前先 `git status`，避免覆盖用户未提交内容。禁止未经允许使用 `git reset --hard` / `git clean -fd` 等破坏性命令。

## 第 3 步：实现纪律

- 单一职责：Player 管移动和自身状态，Door 管门自身，UI 管显示；系统间用明确接口通信。
- 禁止过度设计（YAGNI）：一扇门不需要 DoorManager/Factory/EventBus。
- GDScript 规范：变量/函数 `snake_case`，类 `PascalCase`，常量 `UPPER_SNAKE_CASE`，尽量写类型标注，禁止魔法数字与无解释硬编码 NodePath。
- 目录职责固定（scenes/ scripts/ assets/ tests/ docs/），禁止 scripts2/、temp/ 等垃圾目录。

## 第 4 步：分层验证（不许"读代码后说应该可以"）

按需组合，测试数量服从风险而非凑数。必须覆盖：正常路径、边界、快速重复输入、非法状态、原有功能回归。

| 层 | 适用 | 手段 |
|---|---|---|
| Unit | 纯函数、数据操作、状态转换 | tests/ 下脚本 |
| Scene/Integration | 节点交互、碰撞、动画联动 | 加载场景断言 |
| **Runtime/Play** | 真实游戏行为（移动、按 E 交互） | **必须实际运行**，见下 |
| Regression | 改过的系统原来的功能还能用 | 跑旧用例 |

### Godot 项目：用 Godot AI MCP 做真实验证

Godot 编辑器内需开着 Godot AI 插件（服务器 `http://127.0.0.1:8000/mcp`）。**在项目根目录**用捆绑脚本调用：

```bash
MCP=.qoder/skills/game-dev-protocol/scripts/godot_mcp.sh
bash $MCP <tool_name> ['<json-args>']
```

**禁止猜工具名。** 本插件的工具名与参数曾多次被凭空编造（如 `scan_filesystem`、独立的 `game_eval` 工具，均不存在）。脚本自带查询命令，动手前先查真值：

```bash
bash $MCP --list                     # 列出全部工具名 + 每个工具的 op 枚举（本项目实测 46 个）
bash $MCP --schema game_manage       # 打印某工具的描述 + 完整 inputSchema
bash $MCP --schema scan_filesystem   # 名字写错会直接报错并提示真实工具数量
```

离线备查：`addons/godot_ai/tool_catalog.gd`（DOMAINS 常量即权威清单）。

多数工具是"卷起式"的：`<domain>_manage` + `{"op":"<verb>","params":{...}}`。四个核心工具例外，直接调用：`editor_state`、`node_get_properties`、`scene_get_hierarchy`、`session_activate`。

#### 按验证层对应的实测命令

```bash
# 0. 通道健康
bash $MCP editor_state                          # 编辑器/游戏存活、当前场景、readiness、game_status.break

# 1. Unit + Scene 层：跑 tests/ 下的 McpTestSuite（@tool extends McpTestSuite）
bash $MCP test_run '{}'                         # 自动发现 res://tests/test_*.gd，执行全部 test_* 方法
                                                # 返回 passed/failed/total/suites_run/duration_ms
bash $MCP test_run '{"suite":"door"}'           # 只跑一个套件；加 "verbose":true 出每条用例
bash $MCP test_manage '{"op":"results_get"}'    # 复取上次结果，不重跑

# 2. Runtime 层：必须真的把游戏跑起来
bash $MCP filesystem_manage '{"op":"scan"}'     # 改了文件先让编辑器重新扫描
bash $MCP project_run '{}'                                            # 跑主场景 scene/main.tscn
bash $MCP project_run '{"mode":"custom","scene":"res://abandoned_house.tscn"}'  # 跑指定关卡
bash $MCP project_run '{"mode":"current"}'                            # 跑编辑器当前打开的场景
bash $MCP logs_read '{"source":"game","count":100}'   # 游戏 stdout/push_error（默认 source=plugin，必须显式传）
bash $MCP editor_manage '{"op":"game_eval","params":{"code":"return get_tree().current_scene.name"}}'
                                                # 在运行中的游戏里执行 GDScript 断言，返回 {"result":...,"source":"game"}
bash $MCP game_manage '{"op":"get_scene_tree","params":{"depth":5}}'  # 运行时场景树
bash $MCP game_manage '{"op":"input_key","params":{...}}'             # 模拟按键（E / Esc / WASD）
                                                # 其它 op: input_action, input_mouse, input_sequence,
                                                #         input_state, get_node_info, get_ui_elements
bash $MCP project_manage '{"op":"stop"}'        # 收尾必须停止（op 仅 settings_get/settings_set/stop）

# 3. 结构核查（不必运行游戏）
bash $MCP scene_get_hierarchy '{"depth":4}'
bash $MCP node_find '{"type":"AnimationPlayer"}'
bash $MCP script_manage '{"op":"read","params":{"path":"res://scripts/door.gd"}}'
bash $MCP batch_execute '{"commands":[{"command":"create_node","params":{...}}]}'
                                                # 注意：command 用插件内部命令名
                                                # (create_node/set_property/delete_node/attach_script)，不是 MCP 工具名
```

关键坑（本项目实测）：
- `godot --headless --check-only --script` **解析不到 autoload 单例**，会误报 "Identifier not found"。判断脚本真错要靠编辑器日志 + 实际运行，不能只信 check-only。
- `game_eval` 要求游戏正在运行且主循环在推进；否则返回 `SUB_EDITOR_GAME_NOT_RUNNING` 或 `EVAL_GAME_NOT_READY`（窗口被切到后台就会 not ready）。先 `project_run`，轮询 `editor_state` 到 `game_capture_ready=true`。
- `project_run` 是幂等的：已在运行则返回 `data.was_already_running=true`，不会重启。想重跑得先 `project_manage op=stop`。
- `editor_state` 里 `game_status.status` 为 `"break"` 时，`game_status.break.reason` 就是游戏当前的报错原文 —— 这是最省事的运行时错误入口。
- 启动游戏后 helper 可能未 live，`project_run` 返回 not_live 时直接读 logs_read 即可，日志里有真实启动结果。
- 游戏窗口是用户桌面上的，跑完必须 stop。若 `editor_state` 显示 `is_playing=true` 而**不是自己启动的**（`run_token` 在你没调 project_run 时自己涨了），说明是用户在玩 —— 别擅自 stop，先问。
- `test_run` 只覆盖 `@tool` 脚本；非 `@tool` 的运行时脚本（如 `door.gd`）在编辑器里是 placeholder，其行为必须走 Runtime 层验证。

工具不存在/编辑器没开：**明确告诉用户只完成了 STATIC_VERIFIED，不得假装做过 RUNTIME_VERIFIED**。

## 第 5 步：Debug 纪律

复现→拿错误信息/堆栈→定位→最小修复→重新运行→回归。禁止不看错误同时改十处。

## 第 6 步：最终汇报模板（每次任务结束必须给）

```
## CHANGED      修改/新增/删除的文件
## IMPLEMENTATION 实际实现方式
## TESTS        unit x/x PASS · scene x/x · regression x/x（列实际执行项）
## RUNTIME      是否真实运行、看到了什么证据（日志行、交互结果）
## GIT          分支/commit/工作区状态
## UNVERIFIED   未验证的内容（推测≠PASS）
```

## 遇到任务描述与实际不符

收集证据、说明冲突、能小修则小修；需要大改时停下，把任务升级为 C 类先出设计。

## Resources

- `scripts/godot_mcp.sh` — Godot AI MCP HTTP 调用助手（自动握手/复用会话/过期重连/输出已精简为 structuredContent）。自带 `--list`、`--schema <tool>` 查询真实工具名与参数，猜名字前先用它。
- `references/protocol.md` — 完整 18 条协议原文细则。B/C 类任务、需要设计文档模板或完整汇报示例时加载它。
