## 一种敌人的可复用静态定义资源。
##
## 在CombatantDefinition提供的角色ID、显示名称、最大生命和原画基础上，
## 增加敌人按照顺序循环使用的行动模式。
## EnemyDefinition只描述敌人原本的数据，不保存当前生命、格挡、行动下标或当前意图。
## 该资源在战斗过程中必须视为只读。
class_name EnemyDefinition
extends CombatantDefinition


## 敌人按照顺序循环使用的静态行动模式。
##
## 数组中的每个元素都是一项EnemyActionDefinition，数组顺序就是敌人行动顺序。
## 该资源只保存模式本身，不保存当前行动下标，也不在这里推进或执行行动。
@export var action_pattern:Array[EnemyActionDefinition] = []


## 检查当前敌人静态定义是否包含非法数据。
##
## 先复用CombatantDefinition的公共角色字段检查，再验证行动模式非空，
## 且其中每项EnemyActionDefinition都存在并且合法。
## 该方法只验证静态配置，不修改资源、不推进模式，也不执行敌人行动。
func is_invalid()->bool:
	if super.is_invalid():#先检查角色ID、名称、最大生命和原画
		return true;#公共角色字段非法时立即结束验证
	if action_pattern.is_empty():#敌人必须至少拥有一项可以循环执行的行动
		push_error("Invalid action_pattern! 敌人行动模式为空");#报告缺少敌人规则
		return true;#没有行动的敌人定义不能用于战斗

	for action_index in range(action_pattern.size()):#按照模式顺序逐一检查全部行动
		var action:EnemyActionDefinition = action_pattern[action_index];#取得当前下标对应的行动
		if action == null:#行动模式中不能存在空资源位置
			push_error("Invalid enemy action! 行动模式[%d]为空" % action_index);#报告具体下标
			return true;#空行动无法被EnemyState准备
		if action.is_invalid():#复用行动定义自身的完整合法性检查
			push_error("Invalid enemy action! 行动模式[%d]无效" % action_index);#补充模式位置
			return true;#任意一项非法都会使整个敌人定义非法

	return false;#公共角色数据和全部行动均合法
