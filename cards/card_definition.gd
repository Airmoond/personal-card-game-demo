## 卡牌的静态定义资源。
##
## 保存一种卡牌的ID、名称、描述、类型、稀有度、词条、基础费用、原画和有序效果列表。
## 多个运行时CardInstance可以共同引用同一份CardDefinition资源。
## 战斗过程中应当将该资源视为只读数据，临时变化应保存在CardInstance中。
## 卡牌的目标、伤害、格挡和抽牌等规则由effects中的每个CombatEffectDefinition描述；
## CardDefinition本身不选择实际目标，也不直接执行任何战斗效果。
## 武器的装备数据由weapon_definition描述，effects可另外配置打出时的附加效果。
class_name CardDefinition;
extends Resource;


## 卡牌的基础类型。资源文件保存枚举数值，因此已有类型的编号不能改变。
enum CardType {
	## 攻击牌，主要用于对敌人造成伤害。
	ATTACK = 0,
	
	## 技能牌，主要用于获得格挡或产生其他非攻击效果。
	SKILL = 1,

	## 能力牌，结算后退出抽牌循环，产生的能力或状态按各自规则持续。
	POWER = 2,

	## 武器牌，打出后进入装备栏。
	WEAPON = 3
}


## 卡牌稀有度，用于开局选牌分组与奖励筛选；显示颜色由界面决定。
enum CardRarity {
	COMMON = 0,
	RARE = 1,
	EPIC = 2,
	LEGENDARY = 3
}


## 程序内部使用的唯一卡牌ID，例如strike。
##
## 该ID用于识别和查找卡牌，不应随着显示名称或语言变化而改变。
@export var card_id:String;


## 显示给玩家的卡牌名称，例如“打击”。
@export var card_name:String;


## 显示在卡牌上的效果说明。
##
## 支持多行文本；{damage_0}表示effects[0]的单段伤害，编号按效果数组从0开始。
## 战斗中显示当前修正值，非战斗界面显示固定基础值或动态值X；普通文字原样保留。
@export_multiline var description:String;


## 卡牌的基础类型，与稀有度和词条相互独立。
@export var card_type:CardType;


## 默认值让尚未配置稀有度的旧资源可以继续加载，具体分级在内容接入时确认。
@export var rarity:CardRarity = CardRarity.COMMON;


## 消耗：成功打出并结算后进入消耗牌堆。
## 这是静态标记，实际移动由战斗逻辑处理；武器损坏消耗不使用这个词条。
@export var exhausts_on_play:bool = false;


## 固有：在战斗开始时参与起手牌安排，不代表每个回合都能抽到。
@export var is_innate:bool = false;


## 保留：回合结束时留在手牌，不随其他未打出的手牌一起弃置。
@export var retains_on_turn_end:bool = false;


## 仅武器牌配置，描述基础攻击力、最大耐久和损坏去向。
@export var weapon_definition:WeaponDefinition;


## 卡牌原本需要消耗的能量。
##
## 该数值必须大于或等于0，战斗中的临时费用变化不应修改该字段。
@export var base_energy_cost:int = 0;


## 按照设计顺序保存这张卡牌包含的全部战斗效果。
##
## 数组顺序就是控制器安排效果的顺序；其中每个元素都必须存在且合法。
## 普通卡牌至少有一项效果；武器牌本身提供装备行为，允许没有附加效果。
@export var effects:Array[CombatEffectDefinition] = [];


## 卡牌使用的原画资源。
##
## 第一阶段允许为空；该字段只负责表现，不参与卡牌规则计算。
@export var artwork:Texture2D;


## 把伤害占位符填入文案；非战斗界面无格挡上下文，动态伤害显示X。
## 只生成新字符串，不修改description或效果资源。调用方提供已验证的卡牌定义。
func format_description(damage_values:Array[int] = [])->String:
	var text:String = description;
	for effect_index in range(effects.size()):
		var effect:CombatEffectDefinition = effects[effect_index];
		if effect.effect_type == CombatEffectDefinition.EffectType.DAMAGE:
			var damage_text:String = str(effect.amount);
			if not damage_values.is_empty():
				damage_text = str(damage_values[effect_index]);
			elif effect.damage_source == CombatEffectDefinition.DamageSource.CURRENT_BLOCK:
				damage_text = "X";
			text = text.replace("{damage_%d}" % effect_index, damage_text);
	return text;


## 检查当前卡牌定义是否无效。
##
## card_id为空时推送错误并返回true。
## card_name为空时推送错误并返回true。
## description为空时推送错误并返回true。
## 类型或稀有度不属于对应枚举时推送错误并返回true。
## 基础费用小于0时推送错误并返回true。
## 武器牌缺少武器定义或带有打出即消耗词条、非武器牌配置了武器定义时返回true。
## 非武器牌effects为空，或任意效果为null或非法时，推送错误并返回true。
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
	if not CardType.values().has(card_type):
		push_error("Invalid card_type! 非法的卡牌类型");
		return true;
	if not CardRarity.values().has(rarity):
		push_error("Invalid rarity! 非法的卡牌稀有度");
		return true;
	if base_energy_cost < 0:
		push_error("Invalid base_energy_cost! 非法的卡牌费用");
		return true;
	if card_type == CardType.WEAPON:
		if weapon_definition == null:
			push_error("武器牌缺少武器定义");
			return true;
		if weapon_definition.is_invalid():
			return true;
		if exhausts_on_play:
			push_error("武器在损坏时处理去向，不支持打出即消耗词条");
			return true;
	else:
		if weapon_definition != null:
			push_error("只有武器牌可以配置武器定义");
			return true;
		if effects.is_empty():
			push_error("Invalid effects! 卡牌效果数组为空");
			return true;
	for effect_index in range(effects.size()):#按照数组顺序逐一验证所有卡牌效果
		var effect:CombatEffectDefinition = effects[effect_index];#取得当前位置的效果定义，便于报告准确下标
		if effect == null:#效果数组中不能出现没有实际资源的空元素
			push_error("Invalid effect! 卡牌效果[%d]为空" % effect_index);#报告空效果所在的位置
			return true;#空元素无法被控制器解释，立即判定整张卡牌无效
		if effect.is_invalid():#复用效果定义自身的类型、目标、数值和重复次数检查
			push_error("Invalid effect! 卡牌效果[%d]无效" % effect_index);#补充卡牌数组中的上下文位置
			return true;#任意一项效果非法时，整张卡牌定义都不能使用
	return false;
