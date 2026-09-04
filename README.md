# Godot 卡牌冒险原型

这是一个使用 Godot 4.6 开发的单敌人卡牌战斗项目。项目目前已完成第三阶段：在数据驱动的单场战斗系统之上，建立了由主菜单、地图、战斗、卡牌奖励、休整、Boss 战和结算组成的最小完整冒险流程。

> 当前状态：**第三阶段 v0.3 已完成，并已完成一次完整人工试玩验证。**

阶段文档：

- [第一阶段开发计划](./第一阶段开发计划.html)：建立可以反复开始的基础战斗闭环。
- [第二阶段开发计划](./第二阶段开发计划.html)：建立资源驱动的单敌人战斗系统。
- [第三阶段开发计划](./第三阶段开发计划.html)：建立最小但完整的整局冒险流程，并记录最终实现。

## 一、当前游戏流程

```text
主菜单
  ↓ 开始游戏，创建新的 RunState
三节点地图
  ↓
哥布林营地：普通战斗
  ↓ 胜利
连续三轮卡牌奖励：每轮随机展示三张不同卡牌，选择一张
  ↓ 共获得三张卡牌
篝火休整：恢复 15 点生命
  ↓
遗迹守卫：Boss 战
  ↓
胜利或失败结算
  ↓ 再次启程
返回主菜单
```

普通战斗失败会立即进入失败结算，不会发放奖励，也不会完成失败的地图节点。Boss 胜利会完成 Boss 节点、把整局标记为胜利，然后进入胜利结算。

结算页中的“再次启程”只负责返回主菜单并清理上一局状态。玩家再次点击主菜单中的“开始游戏”时，才会创建一份全新的 `RunState`。

## 二、当前可玩内容

### 整局冒险

- 一张由三个线性节点组成的静态地图。
- 当前生命、实际牌组和地图进度可以跨战斗保存。
- 初始牌组为 5 张打击和 5 张防御。
- 普通战斗胜利后连续进行 3 轮奖励，每轮从 4 张奖励卡中随机展示 3 张不同卡牌。
- 每轮必须选择 1 张卡加入本局牌组，因此一次普通战斗共获得 3 张卡。
- 同一轮不会出现重复选项；不同轮次可以再次出现同一种卡牌。
- 休整节点恢复 15 点生命，但不会超过玩家的 50 点最大生命。
- 胜利、失败、返回主菜单和重新开始已经组成完整闭环。

### 卡牌

| 资源 | 显示名称 | 费用 | 效果 |
| --- | --- | ---: | --- |
| `strike.tres` | 打击 | 1 | 对敌人造成 6 点伤害 |
| `defend.tres` | 防御 | 1 | 玩家获得 5 点格挡 |
| `double_strike.tres` | 双重打击 | 1 | 对敌人造成 3 点伤害，共 2 次 |
| `attack_and_block.tres` | 防守反击 | 1 | 玩家获得 3 点格挡，然后对敌人造成 4 点伤害 |
| `tactical_defense.tres` | 战术防御 | 1 | 玩家获得 3 点格挡，然后抽 1 张牌 |
| `heavy_strike.tres` | 重击 | 2 | 对敌人造成 12 点伤害 |

### 敌人与遭遇

| 遭遇资源 | 敌人显示名称 | 最大生命 | 固定行动循环 |
| --- | --- | ---: | --- |
| `cave_crawler_encounter.tres` | 哥布林战士 | 30 | 攻击 6 → 格挡 5 → 攻击 9 |
| `ruin_guard_encounter.tres` | 遗迹守卫 | 40 | 格挡 8 → 攻击 3 × 2 → 攻击 12 |

两份遭遇当前都使用 `EncounterDefinition` 的默认规则：每回合 3 点能量、抽 5 张牌、手牌上限 10 张。

### 默认地图

| 节点 ID | 显示名称 | 类型 | 内容 | 后继节点 |
| --- | --- | --- | --- | --- |
| `goblin_battle` | 哥布林营地 | 普通战斗 | `cave_crawler_encounter.tres` | `rest_site` |
| `rest_site` | 篝火休整 | 休整 | 恢复 15 点生命 | `ruin_guard_boss` |
| `ruin_guard_boss` | 遗迹守卫 | Boss 战 | `ruin_guard_encounter.tres` | 无 |

## 三、运行项目

1. 使用 Godot 4.6 打开项目目录。
2. 运行项目主场景 `main.tscn`。
3. 在主菜单点击“开始游戏”。
4. 按照地图解锁顺序完成普通战斗、三轮奖励、休整和 Boss 战。

`main.tscn` 不再直接放置一场固定战斗。它只保留持久存在的 `GameFlowController` 和 `page_container`，由流程控制器实例化当前需要显示的页面。

## 四、核心架构

项目把稳定配置、整局状态、单场战斗状态、流程编排和界面输入分开管理。

### 1. 静态定义层：描述“这局游戏是什么”

这一层主要由 `.tres` 资源组成，运行时必须视为只读。

- `RunDefinition`
  - 保存玩家定义、初始牌组条目、地图、奖励池、每轮奖励选项数和连续选择次数。
  - `default_run.tres` 是当前游戏使用的默认整局配置。
- `MapDefinition`
  - 保存地图 ID、全部节点和初始可进入节点。
  - 负责验证重复节点、无效连接、自连接、Boss 缺失和不可达节点。
- `MapNodeDefinition`
  - 保存节点 ID、显示名称、节点类型、地图坐标、后继节点、遭遇或治疗量。
- `EncounterDefinition`
  - 只保存敌人和单场战斗规则。
  - 不再保存玩家定义或初始牌组；这些数据属于 `RunDefinition`。
- `CardDefinition`、`CombatEffectDefinition`
  - 分别描述卡牌和按顺序执行的战斗效果。
- `CombatantDefinition`、`EnemyDefinition`、`EnemyActionDefinition`
  - 描述玩家、敌人及敌人的固定行动循环。

关键原则：静态资源回答“默认配置是什么”，不能保存“这一局已经发生了什么”。

### 2. 局内运行时层：`RunState`

`RunState` 是一局冒险在战斗之外的唯一状态来源，保存：

- 玩家当前生命。
- 本局实际拥有的 `CardDefinition` 引用列表。
- 当前正在处理的节点 ID。
- 可进入节点 ID 列表。
- 已完成节点 ID 列表。
- 整局状态：`SETUP`、`IN_PROGRESS`、`VICTORY` 或 `DEFEAT`。

`RunState.owned_cards` 中的每个数组元素代表玩家实际拥有的一张卡。因此，同一份 `CardDefinition` 可以出现多次，但运行时不会修改卡牌资源本身。

### 3. 流程编排层：`GameFlowController`

`GameFlowController` 在整局期间持续存在，负责：

- 显示主菜单并创建新局。
- 在 `page_container` 中替换地图、战斗、奖励和结算页面。
- 接收地图节点选择并调用 `RunState` 推进节点。
- 把当前生命和牌组注入新战斗。
- 把战斗剩余生命回写到 `RunState`。
- 普通战斗胜利后组织连续三轮奖励。
- 处理休整、Boss 胜利、战斗失败和返回主菜单。

它不执行具体卡牌效果，也不把地图或奖励规则塞进战斗控制器。

### 4. 单场战斗层：`BattleController` 与 `BattleState`

`BattleState` 仍然只管理一场战斗中的玩家、敌人、能量、回合阶段、抽牌堆、手牌和弃牌堆。

`BattleController` 通过公共方法接收外部流程提供的数据：

```gdscript
func start_battle(
    encounter:EncounterDefinition,
    player_definition:CombatantDefinition,
    deck_definitions:Array[CardDefinition],
    starting_player_health:int
) -> bool
```

每次启动战斗时，控制器都会创建新的 `BattleState`、角色状态和 `CardInstance`。战斗结束后只发送：

```gdscript
signal battle_finished(victory:bool, remaining_player_health:int)
```

因此，`BattleController` 不需要知道当前地图节点、奖励次数或整局胜负规则。

### 5. 行为执行层

- `CombatEffectDefinition` 描述伤害、格挡、抽牌、目标、数值和重复次数。
- `ActionQueue` 按顺序执行已经排入队列的效果。
- 卡牌和敌人的复合效果、多段效果共用同一条执行路径。

### 6. 视图与输入层

- `MainMenu` 发送 `start_requested`。
- `MapView` 和 `MapNodeView` 显示地图状态并发送节点选择。
- `RewardCardView` 是以 `Button` 为根节点的独立奖励卡组件，直接展示 `CardDefinition`。
- `RewardView` 根据流程层传入的候选数据创建奖励卡视图、锁定首次选择并发送 `reward_selected`。
- `RunResult` 显示胜负文字并发送 `restart_requested`。
- 战斗中的 `CardView` 与 `CombatantView` 继续负责战斗画面和输入。

奖励卡视图没有继承战斗卡牌脚本。两者虽然可以共享视觉思路，但依赖的数据和交互语义不同：奖励卡读取静态 `CardDefinition`，战斗卡读取单场 `CardInstance`。

## 五、关键状态流转

### 开始新局

1. `GameFlowController` 创建新的 `RunState`。
2. `RunState` 从 `RunDefinition` 复制玩家满生命和地图起点。
3. 初始牌组条目的数量被展开为 10 个 `CardDefinition` 引用。
4. 流程进入地图页面。

### 进入战斗

1. 地图视图只发送玩家选择的节点 ID。
2. `RunState.enter_node()` 验证并提交“正在处理的节点”。
3. `GameFlowController` 读取该节点的遭遇定义。
4. `BattleController.start_battle()` 用局内生命和牌组创建全新的单场战斗状态。

### 普通战斗胜利

1. 战斗控制器发送胜利状态和剩余生命。
2. 流程控制器把生命回写到 `RunState`。
3. 流程控制器从 4 张奖励卡中打乱并截取 3 张，显示本轮奖励页面。
4. 玩家选择后，`RunState.add_card()` 追加一份卡牌定义引用。
5. 重复步骤 3～4，直到完成 3 次选择。
6. 完成普通战斗节点并解锁休整节点。

每一轮抽取都只打乱局部数组，不会改变 `RunDefinition.reward_pool` 的顺序或内容。

### 休整

1. `RunState.enter_node()` 提交休整节点。
2. `RunState.heal(15)` 根据最大生命计算实际恢复量。
3. 完成休整节点并解锁 Boss 节点。
4. 返回地图页面。

### Boss 胜利或战斗失败

- Boss 胜利：回写生命 → 完成 Boss 节点 → `mark_victory()` → 胜利结算。
- 任意战斗失败：回写生命 → `mark_defeat()` → 失败结算。
- 结算页点击“再次启程”：清空当前 `RunState` 和奖励计数 → 返回主菜单。

## 六、调整游戏内容

### 调整初始牌组与奖励

编辑 `run/data/default_run.tres`：

- `starting_deck_entries` 决定初始牌组的卡牌及数量。
- `reward_pool` 决定普通战斗可以出现哪些奖励卡。
- `reward_option_count` 决定每轮展示几张不同卡牌，不能超过奖励池大小。
- `reward_selection_count` 决定普通战斗胜利后连续选择几次。

后两个字段当前使用脚本中的默认值 `3`，因此 `.tres` 没有显式覆盖它们。

### 调整地图

编辑 `run/map/data/first_map.tres`：

- `nodes` 保存全部节点定义。
- `starting_node_ids` 决定新局最先解锁的节点。
- `map_position` 决定节点在地图页面中的显示坐标。
- `next_node_ids` 决定完成节点后解锁哪些后继节点。
- 战斗节点通过 `encounter_definition` 选择遭遇。
- 休整节点通过 `heal_amount` 决定恢复量。

### 调整单场规则

编辑 `battle/data/encounters/` 中的遭遇资源：

- `enemy_definition` 选择敌人。
- `energy_per_turn`、`cards_per_turn`、`max_hand_size` 调整单场规则。
- 未在 `.tres` 中显式写出的字段使用 `EncounterDefinition` 脚本默认值。

## 七、目录结构

```text
游戏开发/
├── main.tscn                         # 应用入口与持久流程控制器
├── run/
│   ├── game_flow_controller.gd       # 整局页面与流程编排
│   ├── data/                         # RunDefinition 与默认整局资源
│   ├── model/                        # RunState
│   ├── map/                          # 地图定义、资源、视图和节点组件
│   ├── reward/                       # 奖励页面与奖励卡组件
│   └── screens/                      # 主菜单与整局结算页面
├── battle/
│   ├── battle_controller.gd          # 单场战斗编排和外部接口
│   ├── battle.tscn                   # 可复用战斗页面
│   ├── actions/                      # 效果定义与行动队列
│   ├── data/                         # 遭遇与初始牌组条目定义
│   └── model/                        # 单场战斗运行时状态
├── cards/                            # 卡牌定义、数据与战斗卡牌视图
├── combatants/                       # 玩家、敌人、行动定义与角色视图
├── artworks/                         # 玩家、敌人和页面背景原画
└── assets/images/                    # 卡牌插画
```

Godot 生成的 `.uid` 和 `.import` 文件需要与对应脚本、图片一起保留，以维持资源身份和导入设置。

## 八、第三阶段验收结果

- [x] 游戏从主菜单开始，而不是直接进入战斗。
- [x] 三节点地图会显示锁定、可进入和已完成状态。
- [x] 普通战斗与 Boss 节点可以启动不同遭遇。
- [x] 战斗后的剩余生命可以跨战斗保存。
- [x] 普通战斗胜利后连续进行三轮三选一奖励。
- [x] 三张奖励卡会加入本局牌组，并可能在 Boss 战中抽到。
- [x] 休整恢复 15 点生命且不超过最大生命。
- [x] Boss 胜利与任意战斗失败均会进入对应结算。
- [x] “再次启程”返回主菜单；再次开始会创建干净的新局。
- [x] `RunState`、`BattleState` 和静态资源的职责边界保持清晰。
- [x] 已由玩家完成一次从开始到结算的完整人工试玩验证。

本次收尾只进行文档与代码静态一致性检查，没有运行额外的 Godot 命令或自动化测试。

## 九、当前开发约定

- 静态 `.tres` 资源在运行时只读。
- 跨战斗数据写入 `RunState`，单场数据写入 `BattleState`。
- `RunState` 保存 `CardDefinition`，每场战斗重新创建 `CardInstance`。
- 页面和组件通过信号报告玩家意图，不直接决定流程去向。
- 页面切换、奖励次数、胜负去向由 `GameFlowController` 统一编排。
- 新增脚本继续补充文档注释，并在关键状态变更处说明原因。
- 调整场景节点名称或层级时，同步检查脚本中的节点路径。

## 十、当前范围与后续方向

当前版本仍是学习架构用的原型，暂未包含随机地图、分支路线、商店、事件、遗物、药水、货币、存档、局外成长、多敌人、状态效果体系、正式异步演出、完整音效和最终 UI 美术。

第三阶段完成后，项目已经拥有可以持续扩展的游戏骨架。后续阶段可以围绕内容扩充、战斗体验、地图选择、成长系统和表现层逐项演进，而不需要再次把整套入口流程推倒重写。
