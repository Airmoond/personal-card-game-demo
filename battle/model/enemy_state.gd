## 保存一名敌人在当前战斗中的运行时状态。
##
## 在CombatantState提供的生命、格挡和受伤能力基础上，额外保存具体敌人定义、
## 当前行动下标以及已经准备好的当前行动。意图显示和敌人回合必须读取同一个
## current_action，避免界面显示与实际执行不一致。
##
## EnemyState只保存和推进状态，不执行效果、不修改静态资源，也不刷新界面。
class_name EnemyState
extends CombatantState


## 当前敌人引用的具体静态定义资源。
##
## 与继承的definition引用同一个EnemyDefinition，但保留具体类型后可以直接访问
## action_pattern。该资源在战斗过程中必须视为只读。
var enemy_definition:EnemyDefinition


## 当前行动在enemy_definition.action_pattern中的下标。
##
## 每场战斗初始化为0；行动结束后循环递增，到达数组末尾后回到0。
var current_action_index:int = 0


## 当前已经准备好、即将在敌人回合中执行的行动。
##
## CombatantView以后读取它显示意图，BattleController读取同一个对象安排真实效果。
## 该引用只表示当前选择，不复制或修改EnemyActionDefinition资源。
var current_action:EnemyActionDefinition


## 使用敌人静态定义初始化当前敌人运行时状态。
##
## 定义为空、定义非法或公共角色状态初始化失败时返回false。
## 成功时恢复生命和格挡，将行动模式重置到第0项，并准备第一项当前行动。
## 该方法不会修改EnemyDefinition或执行已经准备好的行动。
func enemy_state_init(new_enemy_definition:EnemyDefinition)->bool:
	if new_enemy_definition == null:#空定义无法提供角色数据和行动模式
		push_error("敌人定义为空，敌人状态初始化失败");#报告调用方缺少静态敌人配置
		return false;#验证失败前不修改当前运行时状态
	if not super.combatant_init_from_definition(new_enemy_definition):#复用父类初始化名称、生命、格挡和通用定义引用
		push_error("敌人公共状态初始化失败");#补充敌人初始化阶段的错误上下文
		return false;#公共状态不完整时不能继续准备敌人行动

	enemy_definition = new_enemy_definition;#保存具体敌人类型引用，方便读取固定行动模式
	current_action_index = 0;#每场新战斗从模式第一项开始
	current_action = enemy_definition.action_pattern[0];#定义已完整验证，可以安全准备首个敌人意图
	return true;#敌人公共状态和当前行动均已建立





## 初始化已验证整个行动模式；每回合只循环推进下标并更新当前意图。
func advance_to_next_action()->void:
	current_action_index = (current_action_index + 1) % enemy_definition.action_pattern.size();
	current_action = enemy_definition.action_pattern[current_action_index];
