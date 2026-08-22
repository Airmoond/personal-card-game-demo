# Godot 卡牌战斗原型

这是一个使用 Godot 4.6 开发的单场卡牌战斗原型。项目第一阶段的目标是：用最小规则验证一个可以反复开始的“玩家出牌 → 敌人行动 → 新回合 → 胜负结算”完整闭环，同时保持数据、规则、流程和显示之间的职责边界。

> 当前状态：**第一阶段 v0.1 已完成，并已通过人工验收**。

原始阶段规划参见 [第一阶段开发计划.html](./第一阶段开发计划.html)。

## 一、当前可玩内容

当前战斗包含：

- 1 名玩家对战 1 名固定敌人。
- 5 张“打击”与 5 张“防御”组成的测试牌组。
- 抽牌堆、手牌和弃牌堆。
- 玩家生命、敌人生命、格挡和能量。
- 玩家回合、敌人回合与自动进入下一回合。
- 胜利、失败、操作锁定与重新开始。

当前固定数值：

| 项目 | 数值 |
| --- | ---: |
| 玩家最大生命 | 50 |
| 敌人最大生命 | 30 |
| 敌人每回合攻击 | 6 |
| 玩家每回合能量 | 3 |
| 每回合抽牌数 | 5 |
| 最大手牌数 | 10 |
| 打击 | 1 费，造成 6 点伤害 |
| 防御 | 1 费，获得 5 点格挡 |

## 二、运行环境

- 引擎：Godot 4.6。
- 渲染模式：Forward Plus。
- 主场景：`res://main.tscn`。
- 战斗场景：`res://battle/battle.tscn`。

打开项目：

1. 使用 Godot 导入项目根目录中的 `project.godot`。
2. 等待素材完成导入。
3. 运行项目。Godot 会先进入 `main.tscn`，再显示其实例化的 `battle.tscn`。

## 三、核心架构

项目按“数据定义、运行时状态、规则执行、流程控制、界面显示”分层。

```text
卡牌资源 CardDefinition
          ↓ 创建
运行时数据 CardInstance / CombatantState / BattleState
          ↑                     ↓
          │              BattleController
          │                     ↓
          └── ActionQueue 执行伤害、格挡、抽牌
                                ↓
                   CardView / CombatantView 刷新显示
```

### 1. 数据定义层

`CardDefinition` 是一种卡牌的静态设计数据，继承自 `Resource`。

它保存：

- 卡牌 ID。
- 名称和描述。
- 卡牌类型和目标类型。
- 基础能量费用。
- 基础伤害和基础格挡。
- 卡牌原画。

具体卡牌使用 `.tres` 资源配置。当前包含：

- `cards/data/strike.tres`
- `cards/data/defend.tres`

多张同名卡牌可以共享同一份 `CardDefinition`，战斗中不修改这些静态资源。

### 2. 运行时数据层

#### `CardInstance`

代表战斗中真实存在的一张卡牌。每个实例引用一份 `CardDefinition`，并独立保存当前能量费用。

同一种卡牌必须创建多个不同的 `CardInstance`，不能把同一个实例重复放入牌组。

#### `CombatantState`

代表一名玩家或敌人的运行时状态，保存：

- 角色名称。
- 最大生命和当前生命。
- 当前格挡。

`take_damage()` 负责格挡吸收、穿透伤害和生命下限计算。`CombatantView` 不参与伤害计算。

#### `BattleState`

是整场战斗的唯一可信数据源，保存：

- 玩家和敌人的 `CombatantState`。
- 每回合基础能量和当前可用能量。
- 抽牌堆、手牌和弃牌堆。
- 当前回合编号。
- `SETUP`、`PLAYER_TURN`、`ENEMY_TURN` 和 `FINISHED` 四种战斗阶段。

`BattleState` 负责牌堆移动、抽牌堆重洗、能量消耗以及胜负状态查询，但不负责操作 UI。

### 3. 规则执行层

`ActionQueue` 继承自 `RefCounted`，不进入场景树。

当前使用同步先进先出队列：

1. 控制器将伤害、格挡或抽牌方法及其参数绑定为 `Callable`。
2. 行为按加入顺序保存。
3. `resolve_all()` 依次调用所有行为。

它只负责执行顺序，不判断当前回合、卡牌是否在手牌中、能量是否足够或战斗是否结束。

### 4. 流程控制层

`BattleController` 挂载在 `battle.tscn` 的 `battle_controller` 节点上，是唯一的战斗流程入口。

它负责：

- 创建玩家、敌人、初始牌组和 `BattleState`。
- 连接卡牌点击、结束回合和重新开始信号。
- 验证战斗阶段、手牌归属和能量。
- 安排卡牌效果，消耗能量，并将打出的卡牌移入弃牌堆。
- 执行敌人固定意图。
- 开始新玩家回合。
- 检查胜负、锁定操作、显示结果并重开战斗。
- 根据最新 `BattleState` 刷新所有战斗 UI。

### 5. 显示与输入层

#### `CardView`

- 绑定一张 `CardInstance`。
- 显示当前费用、名称、原画和描述。
- 使用 `_gui_input()` 接收鼠标左键按下。
- 发出 `card_selected` 信号，但不判断卡牌能否打出，也不执行卡牌效果。

#### `CombatantView`

- 绑定一份 `CombatantState`。
- 显示角色名称、生命、格挡和敌人意图。
- 允许显示生命为 0 的角色。
- 不修改生命、格挡或回合状态。

## 四、项目目录

```text
res://
├── project.godot                         # Godot 项目配置，主场景为 main.tscn
├── main.tscn                            # 项目入口，实例化 battle.tscn
├── 第一阶段开发计划.html               # 第一阶段范围、架构和验收标准
├── artworks/
│   └── background.png                  # 战斗背景
├── assets/images/
│   ├── strike.png                      # 打击卡原画
│   └── defend.png                      # 防御卡原画
├── battle/
│   ├── battle.tscn                     # 单场战斗界面与节点组装
│   ├── battle_controller.gd            # 战斗流程控制器
│   ├── actions/
│   │   └── action_queue.gd            # 同步战斗行为队列
│   └── model/
│       ├── battle_state.gd            # 整场战斗的运行时状态
│       ├── card_instance.gd           # 某一张卡的运行时实例
│       └── combatant_state.gd         # 某一名战斗角色的状态
├── cards/
│   ├── card_definition.gd             # 卡牌静态定义类
│   ├── card_view.tscn                 # 卡牌显示场景
│   ├── card_view.gd                   # 卡牌数据绑定与点击信号
│   └── data/
│       ├── strike.tres                # 打击卡配置
│       └── defend.tres                # 防御卡配置
└── combatants/
    ├── combatant_view.tscn            # 玩家与敌人共用的显示场景
    └── combatant_view.gd              # 角色状态绑定与显示刷新
```

Godot 生成的 `.uid`、`.import` 和 `.godot/` 为引擎识别与导入数据，不承载战斗规则。

## 五、场景组装

### `main.tscn`

```text
Main
└── battle（battle.tscn 场景实例）
```

`main.tscn` 是项目的稳定入口。以后加入主菜单、地图、奖励或其他页面时，可以在这一层替换当前页面，而不需要把 `battle.tscn` 永久作为项目根场景。

### `battle.tscn`

```text
battle
├── background
├── main_layout
│   ├── enemy_area
│   │   └── enemy_view（combatant_view.tscn 实例）
│   ├── player_area
│   │   └── player_view（combatant_view.tscn 实例）
│   ├── battle_info_area
│   │   ├── energy_label
│   │   ├── draw_pile_label
│   │   └── discard_pile_label
│   ├── hand_area
│   └── end_turn_button
├── result_overlay
│   └── result_layout
│       ├── result_label
│       └── restart_button
└── battle_controller
```

当前界面使用第一阶段的简化布局：

- 玩家显示位于左侧，敌人显示位于右侧。
- 手牌放在屏幕底部，并刻意从左向右排列。
- 抽牌堆、弃牌堆和能量信息位于左下角。
- 结束回合按钮位于右下角。
- 背景使用图片并覆盖完整战斗区域。
- 部分 UI 使用固定坐标；这是第一阶段接受的刻意取舍。

## 六、战斗流程

### 1. 初始化战斗

```text
main.tscn 实例化 battle.tscn
        ↓
BattleController 连接按钮信号
        ↓
创建玩家、敌人和 10 个独立 CardInstance
        ↓
创建 BattleState，将全部卡牌放入抽牌堆并洗牌
        ↓
绑定玩家与敌人的 CombatantView
        ↓
恢复 3 点能量，进入第 1 回合，抽取 5 张手牌
```

### 2. 打出卡牌

```text
玩家点击 CardView
        ↓
CardView 发出 card_selected(CardInstance)
        ↓
BattleController 检查回合、实例有效性、手牌归属和能量
        ↓
根据目标类型将伤害或格挡加入 ActionQueue
        ↓
消耗能量，将卡牌从手牌移入弃牌堆
        ↓
ActionQueue 执行效果
        ↓
检查胜负并刷新界面
```

能量不足时，操作会被拒绝，卡牌、能量和目标状态保持不变。

### 3. 结束回合

```text
玩家请求结束回合
        ↓
阶段切换为 ENEMY_TURN，剩余手牌全部进入弃牌堆
        ↓
敌人清除自己的旧格挡，执行固定 6 点攻击
        ↓
玩家格挡优先吸收伤害
        ↓
玩家存活：清除剩余格挡，恢复能量，进入新回合并抽牌
玩家死亡：进入 FINISHED 并显示失败
```

抽牌堆为空而弃牌堆不为空时，`BattleState` 会自动将弃牌堆洗回抽牌堆。

### 4. 胜负与重开

- 敌人生命归零：显示“胜利”。
- 玩家生命归零：显示“失败”。
- 战斗结束后，阶段设为 `FINISHED`，清空未执行行为，禁用结束回合按钮，结果遮罩阻止继续操作底层 UI。
- 重新开始会创建新的玩家、敌人、`CardInstance` 和 `BattleState`，不沿用上一场战斗的生命、格挡、能量或牌堆。

## 七、手牌界面的重建策略

`BattleState.hand` 是真实手牌，`hand_area` 中的 `CardView` 只是它的屏幕表现。

当前每次手牌改变后，`BattleController` 会：

1. 从 `hand_area` 移除并安全释放所有旧 `CardView`。
2. 遍历 `BattleState.hand`。
3. 为每个 `CardInstance` 实例化一个新 `CardView`。
4. 先将 `CardView` 加入场景树，再绑定 `CardInstance`，确保 `@onready` 引用已经准备完成。
5. 连接新 `CardView` 的 `card_selected` 信号。

这种方式优先保证第一阶段的简单性和数据一致性。它会丢失旧节点上的悬停或动画状态，因此在开发卡牌动画时，可以改为根据 `CardInstance` 单独新增、移除和移动对应 `CardView`。

## 八、已完成的第一阶段功能

- [x] `main.tscn` 作为项目入口并实例化战斗场景。
- [x] 战斗开始时创建玩家、敌人和初始牌组。
- [x] 玩家回合开始时恢复能量并抽取手牌。
- [x] 手牌中的每个 `CardInstance` 都拥有一个 `CardView`。
- [x] 抽牌堆和弃牌堆中的卡牌没有常驻显示节点。
- [x] 能量不足时拒绝出牌。
- [x] 打击造成伤害，防御获得格挡。
- [x] 格挡优先抵消敌人攻击伤害。
- [x] 结束回合后敌人执行固定意图。
- [x] 角色生命和格挡始终从 `CombatantState` 刷新。
- [x] 任意一方死亡后停止普通战斗操作。
- [x] 显示胜利或失败结果。
- [x] 重新开始创建一份干净的新战斗状态。
- [x] `CardView` 和 `CombatantView` 不直接修改战斗状态。
- [x] 新增一张基础伤害或格挡卡时，不需要创建新场景。

## 九、当前范围与刻意取舍

第一阶段刻意不包含：

- 状态效果、遗物、药水和角色成长。
- 地图、奖励、商店、事件与存档。
- 多敌人、多目标选择和复杂意图。
- 拖拽出牌、曲线手牌和正式战斗动画。
- 声音、特效与完整美术表现。
- 自动化测试和调试界面。
- 全局事件总线或其他为未来提前搭建的大型框架。

当前还有以下已知限制：

- 参战角色、牌组数量、每回合能量和敌人攻击值仍固定在 `BattleController` 常量中。
- `CombatantState` 尚未包含或引用角色静态定义，因此玩家和敌人原画未实现数据驱动。
- 敌人意图文字和行动均由 `BattleController` 使用固定值提供。
- `CardDefinition` 只能直接表达基础伤害与格挡，尚不能组合抽牌、多段攻击、状态等复杂效果。
- `ActionQueue` 当前立即同步结算，没有等待动画或玩家选择的机制。
- 手牌每次更新时整体重建 `CardView`，尚未保留节点级动画状态。

## 十、开发约定

继续开发时应保持以下规则：

1. **数据是真实状态。** 不能从 `Label`、`ProgressBar` 或 `CardView` 反向读取战斗数据。
2. **View 只显示和报告输入。** `CardView` 不扣能量，`CombatantView` 不扣生命。
3. **Controller 组织流程。** 回合、目标、费用、牌堆移动和胜负由 `BattleController` 统一协调。
4. **Model 保存数据与基础规则。** 生命、格挡、能量和牌堆不依赖场景树。
5. **静态定义与运行时实例分离。** `.tres` 保存设计数据，`CardInstance` 保存单场战斗中的临时状态。
6. **先入树，后绑定。** 运行时创建 `CardView` 时，先调用 `add_child()`，再调用 `bind_card_instance()`，以保证 `@onready` 引用可用。
7. **新功能先定义阶段边界。** 不要为未确定的远期功能提前引入大型框架。
8. **命名保持 `snake_case`。** Godot 内置类型名保留引擎原名。

## 十一、第二阶段开工前的建议

进入第二阶段前，先明确该阶段的唯一主目标。不建议同时开发多敌人、状态、动画、地图和存档。

推荐的演进顺序：

1. **数据驱动角色与遭遇。** 为玩家和敌人建立静态定义资源，将姓名、最大生命、原画和敌人意图从 `BattleController` 常量中移出。
2. **抽离敌人意图和行动选择。** 让敌人运行时状态保存已决定的下一步行动，View 只显示其结果。
3. **扩展卡牌效果表达。** 在伤害和格挡之外，再根据确定需求加入抽牌、多段攻击或状态。
4. **扩展目标系统。** 只有在确定需要多敌人时，再将单个 `enemy_state` 演进为敌人数组并引入目标选择。
5. **改造显示更新。** 需要抽牌、出牌和弃牌动画时，再将整手重建改为按实例增量更新。
6. **最后扩展局外页面。** 利用 `main.tscn` 作为页面入口，再加入地图、奖励或主菜单。

在确定第二阶段主目标后，建议新建一份独立阶段计划，列出“要做、不做、数据边界、开发顺序和验收标准”，再开始修改第一阶段稳定代码。

## 十二、阶段交接摘要

第一阶段已经建立了可复用的战斗骨架：静态卡牌资源生成运行时卡牌，`BattleState` 保存唯一真实状态，`BattleController` 组织回合与胜负，`ActionQueue` 结算行为，View 只负责显示和输入。

下一阶段应将这套边界作为已稳定基线。新功能应优先通过扩展数据定义、运行时状态和控制器流程接入，而不是让 View 开始保存规则或把 UI 数值当作真实数据。
