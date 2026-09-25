## 敌人的一次可复用、可配置的静态行动定义。
##
## 保存行动ID、意图名称和按顺序执行的战斗效果。EnemyDefinition以后会将多个
## EnemyActionDefinition组成固定循环模式，EnemyState保存本场战斗当前准备的行动。
## SELF表示执行行动的敌人自己，OPPONENT表示当前玩家；实际角色对象由
## BattleController在敌人回合中选择。
##
## 该资源在战斗过程中必须视为只读数据。它不保存行动下标，不直接修改生命、
## 格挡或牌堆，也不调用ActionQueue执行效果。
class_name EnemyActionDefinition
extends Resource


## 程序内部使用的稳定唯一行动ID，例如basic_attack或double_strike。
##
## 该ID用于识别和查找敌人行动，不应随着显示文字或语言变化而改变。
@export var action_id:String


## 显示给玩家的敌人意图名称，例如“攻击”“防御”或“连续斩击”。
##
## 建议只保存行动名称，实际伤害、格挡和重复次数应当从effects生成显示内容，
## 防止意图文字中的数值与随后执行的真实效果不一致。
@export var intent_text:String


## 按照设计顺序保存本次敌人行动包含的全部战斗效果。
##
## 数组顺序就是控制器安排效果的顺序；其中每个元素都必须存在且合法。
## 当前敌人支持伤害、格挡、力量、易伤、虚弱与持续能力，玩家专用效果不用于敌人行动。
@export var effects:Array[CombatEffectDefinition] = []


## 检查当前敌人行动定义是否包含非法数据。
##
## action_id或intent_text为空、effects为空，或者数组中存在空、非法或仅玩家支持的效果时，
## 推送对应错误并返回true。所有字段均满足当前规则时返回false。
## 该方法只验证静态配置，不会修复资源、推进敌人模式或执行任何效果。
func is_invalid()->bool:
	if action_id.is_empty():#每项敌人行动必须拥有稳定且非空的内部ID
		push_error("Invalid action_id! 空敌人行动ID");#报告无法识别行动的配置错误
		return true;#发现第一个错误后立即结束验证
	if intent_text.is_empty():#敌人意图界面必须拥有可显示的行动名称
		push_error("Invalid intent_text! 空敌人意图文字");#报告缺少意图显示内容
		return true;#没有意图文字的行动不能用于本阶段敌人
	if effects.is_empty():#一次敌人行动至少需要包含一项真实战斗效果
		push_error("Invalid effects! 敌人行动效果数组为空");#报告缺少行动规则来源
		return true;#没有效果的行动不能进入固定行动模式

	for effect_index in range(effects.size()):#按照数组顺序逐一验证行动中的全部效果
		var effect:CombatEffectDefinition = effects[effect_index];#取得当前位置的静态效果定义
		if effect == null:#效果数组中不能出现没有实际资源的空元素
			push_error("Invalid effect! 敌人行动效果[%d]为空" % effect_index);#报告空效果所在下标
			return true;#空元素无法被控制器解释，立即判定行动无效
		if effect.is_invalid():#复用效果定义自身的类型、目标、数值和次数检查
			push_error("Invalid effect! 敌人行动效果[%d]无效" % effect_index);#补充敌人行动中的位置上下文
			return true;#任意一项效果非法时，整次敌人行动都不能使用
		if effect.effect_type in [CombatEffectDefinition.EffectType.DRAW, CombatEffectDefinition.EffectType.GAIN_ENERGY, CombatEffectDefinition.EffectType.ENHANCE_WEAPON, CombatEffectDefinition.EffectType.LOSE_HEALTH, CombatEffectDefinition.EffectType.PREVENT_DRAW, CombatEffectDefinition.EffectType.LOSE_MAX_HEALTH, CombatEffectDefinition.EffectType.GAIN_ATTACK_CARD_ENERGY]:
			push_error("敌人行动不能包含玩家专用效果");
			return true;

	return false;#全部静态字段和效果均合法，当前敌人行动定义可以使用
