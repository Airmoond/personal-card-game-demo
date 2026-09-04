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


## 根据当前行动下标准备current_action。
##
## 该方法不改变current_action_index，也不执行行动；只有定义、下标和对应行动
## 全部合法时才替换current_action并返回true，失败时保持原当前行动不变。
func prepare_current_action()->bool:
	if enemy_definition == null:#没有具体敌人定义就无法读取行动模式
		push_error("敌人定义为空，无法准备当前行动");#报告缺少静态行动来源
		return false;#保持原当前行动不变
	if enemy_definition.is_invalid():#防止读取空模式或非法行动资源
		push_error("敌人定义无效，无法准备当前行动");#报告静态敌人配置错误
		return false;#非法定义不能产生运行时意图
	if current_action_index < 0 or current_action_index >= enemy_definition.action_pattern.size():#当前下标必须位于模式数组范围内
		push_error("当前敌人行动下标越界，无法准备当前行动");#报告损坏的运行时模式位置
		return false;#越界时不能访问行动数组

	var prepared_action:EnemyActionDefinition = enemy_definition.action_pattern[current_action_index];#读取当前下标对应的静态行动
	if prepared_action == null or prepared_action.is_invalid():#更新引用前再次防御性检查目标行动
		push_error("需要准备的敌人行动无效");#报告当前模式项不可用
		return false;#失败时不覆盖原current_action

	current_action = prepared_action;#让意图显示和后续执行共同引用这项行动
	return true;#当前行动已成功准备


## 将敌人行动模式循环推进到下一项，并准备新的current_action。
##
## 当前下标位于末尾时回到第0项。只有下一项行动完整合法时才同时更新
## current_action_index和current_action；该方法不会执行新行动。
func advance_to_next_action()->bool:
	if enemy_definition == null:#缺少敌人定义时无法计算下一项模式位置
		push_error("敌人定义为空，无法推进行动模式");#报告缺少静态行动来源
		return false;#保持当前下标和行动不变
	if enemy_definition.is_invalid():#行动模式必须非空且全部行动合法
		push_error("敌人定义无效，无法推进行动模式");#报告静态模式配置错误
		return false;#非法模式不能继续循环
	if current_action_index < 0 or current_action_index >= enemy_definition.action_pattern.size():#拒绝从损坏的当前下标继续计算
		push_error("当前敌人行动下标越界，无法推进行动模式");#报告运行时下标错误
		return false;#不擅自修复或重置损坏状态

	var next_action_index:int = (current_action_index + 1) % enemy_definition.action_pattern.size();#到达数组末尾后循环回第0项
	var next_action:EnemyActionDefinition = enemy_definition.action_pattern[next_action_index];#取得下一下标对应的静态行动
	if next_action == null or next_action.is_invalid():#提交新状态前完整验证下一项行动
		push_error("下一项敌人行动无效，无法推进行动模式");#报告无法准备的新意图
		return false;#失败时保留原下标和current_action

	current_action_index = next_action_index;#保存新的运行时模式位置
	current_action = next_action;#让界面和控制器开始共同读取下一项行动
	return true;#行动模式已成功推进并准备新意图
