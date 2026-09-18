# 项目工程纪律（每次会话强制生效）

本项目为长期维护的 Godot 游戏项目。任何代码/场景修改、Bug 调试、功能验证任务，**动手前先加载 `/game-dev-protocol` 技能并遵守其流程**：任务分类 A/B/C → 锁定修改范围 → 最小实现 → 分层验证 → 证据式汇报（CHANGED/IMPLEMENTATION/TESTS/RUNTIME/GIT/UNVERIFIED）。

该技能是**项目级**技能，随仓库版本管理，位于 `.qoder/skills/game-dev-protocol/`（不在用户全局目录）。改协议就改这里，并同步本文件。

硬性规则摘要：
- C 类（新系统/改核心数据结构）必须先出设计文档，经用户确认后实现。
- 扩展现有机制，不另造平行系统；禁止过度设计；禁止顺手重构无关文件。
- 真实运行验证优先于静态推断；无法运行时必须声明 STATIC_VERIFIED。
- 禁止未经允许的破坏性 Git 操作（reset --hard / clean -fd 等）。

# 项目事实

- 引擎：Godot 4.7.2-stable（可执行文件 `D:\BaiduNetdiskDownload\Godot_v4.7.2-stable_win64.exe\`）。
- 交互体系：`player.gd → 射线检测 → Interactable(scripts/interactable.gd) → interact()`；新交互物必须继承 Interactable。
- 物品系统：autoload 单例 `PlayerInventory`（scripts/PlayerInventory.gd），通过 `PlayerInventory.add_item/has_item` 访问。
- MCP 验证通道：Godot 编辑器内需开着 Godot AI 插件，服务器 `http://127.0.0.1:8000/mcp`。在**项目根目录**调用：`bash .qoder/skills/game-dev-protocol/scripts/godot_mcp.sh <tool> ['<json-args>']`。
- 工具名不许猜（插件共 46 个工具，多为 `<domain>_manage` + `{"op":...,"params":{...}}`）。查真值：`godot_mcp.sh --list` / `--schema <tool>`；离线看 `addons/godot_ai/tool_catalog.gd`。
- 单元测试：`godot_mcp.sh test_run '{}'` 自动发现并执行 `tests/test_*.gd`（`@tool extends McpTestSuite`）。2026-09-19 实测 17/17 PASS（套件 door 14、player_step 3）。
- **autoload 在编辑器 `@tool` 测试层只是 placeholder**（调用其方法会报 "Attempt to call a method on a placeholder instance"）。因此凡涉及 `PlayerInventory` 的行为，单元测试层测不到，必须在真实运行的游戏里验证；`test_run` 只认 `test_*.gd` 里的 McpTestSuite 子类，游戏内跑的运行时套件不要加 `test_` 前缀（现有：`tests/lock_runtime_suite.gd` 锁状态机 L1-L6、`tests/key_door_play.gd` 真实按键流程）。
- 门锁：`scripts/door.gd` 的 `Lock` 分组（`is_locked` / `required_key` / `consume_key_on_unlock`）由 Door 自己判定并查 `PlayerInventory`；Player/Key/Inventory 都不感知锁。`Casa/Puerta` 配为锁门 + Basement Key 不消耗。
- 已知坑：`--check-only` 解析不到 autoload 会误报，脚本真实错误以编辑器日志 + 实际运行为准；游戏跑完必须 `project_manage op=stop`；`logs_read` 默认 source 是 `plugin`，读游戏日志要显式传 `{"source":"game"}`。
- 主场景：scene/main.tscn（`project_run '{}'`）；测试关卡 abandoned_house.tscn（`project_run '{"mode":"custom","scene":"res://abandoned_house.tscn"}'`）；测试放 tests/。
