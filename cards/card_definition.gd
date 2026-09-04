## 卡牌的静态定义资源。
##
## 保存一种卡牌的ID、名称、描述、类型、基础费用、原画和有序效果列表。
## 多个运行时CardInstance可以共同引用同一份CardDefinition资源。
## 战斗过程中应当将该资源视为只读数据，临时变化应保存在CardInstance中。
## 卡牌的目标、伤害、格挡和抽牌等规则由effects中的每个CombatEffectDefinition描述；
## CardDefinition本身不选择实际目标，也不直接执行任何战斗效果。
class_name CardDefinition;
extends Resource;


## 卡牌的基础类型。
enum CardType {
	## 攻击牌，主要用于对敌人造成伤害。
	ATTACK,
	
	## 技能牌，主要用于获得格挡或产生其他非攻击效果。
	SKILL
}


## 程序内部使用的唯一卡牌ID，例如strike。
##
## 该ID用于识别和查找卡牌，不应随着显示名称或语言变化而改变。
@export var card_id:String;


## 显示给玩家的卡牌名称，例如“打击”。
@export var card_name:String;


## 显示在卡牌上的效果说明。
##
## 支持在Godot检查器中输入多行文本。
@export_multiline var description:String;


## 卡牌的基础类型，例如攻击牌或技能牌。
@export var card_type:CardType;


## 卡牌原本需要消耗的能量。
##
## 该数值必须大于或等于0，战斗中的临时费用变化不应修改该字段。
@export var base_energy_cost:int = 0;


## 按照设计顺序保存这张卡牌包含的全部战斗效果。
##
## 数组顺序就是控制器安排效果的顺序；其中每个元素都必须存在且合法。
## 该数组是卡牌效果的唯一静态数据来源，因此至少需要包含一项效果。
@export var effects:Array[CombatEffectDefinition] = [];


## 卡牌使用的原画资源。
##
## 第一阶段允许为空；该字段只负责表现，不参与卡牌规则计算。
@export var artwork:Texture2D;


## 检查当前卡牌定义是否无效。
##
## card_id为空时推送错误并返回true。
## card_name为空时推送错误并返回true。
## description为空时推送错误并返回true。
## 基础费用小于0时推送错误并返回true。
## effects为空，或者其中存在null或非法CombatEffectDefinition时，推送错误并返回true。
## 所有字段均满足当前阶段的规则时返回false。
## 该方法在发现第一个错误后立即结束，不会继续检查后续字段。
func is_invalid()->bool:
	if card_id.is_empty():
		push_error("Invalid card_id! 空卡牌ID");
		return true;
	if card_name.is_empty():
		push_error("Invalid card_name! 空卡牌名称");
		return true;
	if description.is_empty():
		push_error("Invalid description! 空卡牌描述");
		return true;
	if base_energy_cost < 0:
		push_error("Invalid base_energy_cost! 非法的卡牌费用");
		return true;
	if effects.is_empty():#卡牌必须至少配置一项统一战斗效果
		push_error("Invalid effects! 卡牌效果数组为空");#报告缺少唯一效果来源
		return true;#没有效果的卡牌定义不能进入战斗
	for effect_index in range(effects.size()):#按照数组顺序逐一验证所有卡牌效果
		var effect:CombatEffectDefinition = effects[effect_index];#取得当前位置的效果定义，便于报告准确下标
		if effect == null:#效果数组中不能出现没有实际资源的空元素
			push_error("Invalid effect! 卡牌效果[%d]为空" % effect_index);#报告空效果所在的位置
			return true;#空元素无法被控制器解释，立即判定整张卡牌无效
		if effect.is_invalid():#复用效果定义自身的类型、目标、数值和重复次数检查
			push_error("Invalid effect! 卡牌效果[%d]无效" % effect_index);#补充卡牌数组中的上下文位置
			return true;#任意一项效果非法时，整张卡牌定义都不能使用
	return false;
