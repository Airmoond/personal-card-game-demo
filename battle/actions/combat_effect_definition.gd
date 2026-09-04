## 一项可复用、可配置的静态战斗效果定义。
##
## CardDefinition和EnemyActionDefinition可以按照设计顺序保存多个
## CombatEffectDefinition，从而组合出伤害、格挡、抽牌和多段效果。
## target_type描述的是相对于行动者的目标：SELF是行动者自己，
## OPPONENT是行动者的对手；实际的玩家或敌人对象由BattleController选择。
##
## 该资源在战斗过程中应当视为只读数据。它只描述效果，不选择实际目标，
## 不检查回合或费用，也不直接修改CombatantState、BattleState或界面。
class_name CombatEffectDefinition
extends Resource


## 第二阶段支持的基础战斗效果类型。
enum EffectType {
	## 对目标造成amount点伤害。
	DAMAGE,

	## 为目标增加amount点格挡。
	BLOCK,

	## 让行动者抽取amount张牌；第二阶段只允许以SELF为目标。
	DRAW
}


## 一项效果相对于行动者的目标类型。
enum TargetType {
	## 效果作用于行动者自己。
	SELF,

	## 效果作用于行动者的对手。
	OPPONENT
}


## 当前效果的基础类型，决定控制器应当安排伤害、格挡还是抽牌行为。
@export var effect_type:EffectType


## 当前效果相对于行动者的目标；这里只描述方向，不保存实际角色对象。
@export var target_type:TargetType


## 当前效果每次执行时使用的数值。
##
## DAMAGE表示单段伤害，BLOCK表示单次格挡，DRAW表示单次抽牌数量。
## 默认值0刻意保持为非法值，提醒配置者必须为新效果填写一个正数。
@export var amount:int = 0


## 当前效果需要独立执行的次数。
##
## 例如amount为3且repeat_count为2的DAMAGE，会被控制器解释为两次
## 独立的3点伤害，而不是一次6点伤害。该数值必须大于0。
@export var repeat_count:int = 1


## 检查当前战斗效果定义是否包含非法数据。
##
## 效果类型或目标类型不属于对应枚举、数值小于或等于0、重复次数小于或等于0时，
## 推送对应错误并返回true。抽牌效果只能以使用者自己为目标。
## 所有数据均满足当前阶段规则时返回false。
## 该方法只检查静态配置，不会修复数据或执行任何效果。
func is_invalid()->bool:
	if not EffectType.values().has(effect_type):#确认效果类型确实属于DAMAGE、BLOCK或DRAW
		push_error("非法的效果类型，战斗效果定义无效");#报告具体的配置错误，方便定位资源问题
		return true;#发现第一个错误后立即结束验证
	if not TargetType.values().has(target_type):#确认目标类型确实属于SELF或OPPONENT
		push_error("非法的目标类型，战斗效果定义无效");#报告目标类型配置错误
		return true;#非法目标不能继续参与效果解释
	if amount <= 0:#伤害、格挡和抽牌的单次执行数值都必须大于0
		push_error("效果数值必须大于0，战斗效果定义无效");#报告数值配置错误
		return true;#非正数效果没有合法的执行意义
	if repeat_count <= 0:#效果至少需要执行一次
		push_error("效果重复次数必须大于0，战斗效果定义无效");#报告重复次数配置错误
		return true;#零次或负数次执行均视为非法
	if effect_type == EffectType.DRAW and target_type != TargetType.SELF:#第二阶段只允许行动者为自己抽牌
		push_error("抽牌效果只能以SELF为目标，战斗效果定义无效");#阻止把抽牌错误配置到对手身上
		return true;#目标语义不合法时拒绝该效果定义
	return false;#全部检查通过，当前战斗效果定义合法
