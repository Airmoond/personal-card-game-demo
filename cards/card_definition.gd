## 卡牌的静态定义资源。
##
## 保存一种卡牌的ID、名称、描述、类型、目标类型、原画和基础数值。
## 多个运行时CardInstance可以共同引用同一份CardDefinition资源。
## 战斗过程中应当将该资源视为只读数据，临时变化应保存在CardInstance中。
class_name CardDefinition;
extends Resource;


## 卡牌的基础类型。
enum CardType {
	## 攻击牌，主要用于对敌人造成伤害。
	ATTACK,
	
	## 技能牌，主要用于获得格挡或产生其他非攻击效果。
	SKILL
}


## 卡牌效果的目标类型。
enum TargetType {
	## 卡牌效果作用于玩家自己，不需要选择敌人。
	SELF,
	
	## 卡牌效果作用于一个敌人，需要指定或自动选择敌人目标。
	ENEMY,
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


## 卡牌效果的目标类型，例如玩家自己或一个敌人。
@export var target_type:TargetType;


## 卡牌原本需要消耗的能量。
##
## 该数值必须大于或等于0，战斗中的临时费用变化不应修改该字段。
@export var base_energy_cost:int = 0;


## 卡牌原本能够造成的伤害。
##
## 没有伤害效果时为0，该数值不能小于0。
@export var base_damage_amount:int = 0;


## 卡牌原本能够提供的格挡。
##
## 没有格挡效果时为0，该数值不能小于0。
@export var base_block_amount:int = 0;


## 卡牌使用的原画资源。
##
## 第一阶段允许为空；该字段只负责表现，不参与卡牌规则计算。
@export var artwork:Texture2D;


## 检查当前卡牌定义是否无效。
##
## card_id为空时推送错误并返回true。
## card_name为空时推送错误并返回true。
## description为空时推送错误并返回true。
## 基础费用、基础伤害或基础格挡小于0时推送错误并返回true。
## 基础伤害和基础格挡同时为0时推送错误并返回true。
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
	if base_damage_amount < 0:
		push_error("Invalid base_damage_amount! 非法的伤害数值");
		return true;
	if base_block_amount < 0:
		push_error("Invalid base_block_amount! 非法的格挡数值");
		return true;
	if base_damage_amount == 0 and base_block_amount == 0:
		push_error("Invalid damage and block amount! 伤害和格挡不可同时为零");
		return true;
	return false;


## 判断这张卡牌是否需要指定一个敌人目标。
##
## target_type为TargetType.ENEMY时返回true。
## target_type为TargetType.SELF时返回false。
## 该方法只进行判断，不会选择目标，也不会修改卡牌定义。
func requires_target()->bool:
	if target_type == TargetType.ENEMY:
		return true;
	else:
		return false;
