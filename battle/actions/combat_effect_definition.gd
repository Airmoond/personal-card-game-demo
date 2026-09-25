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


## 基础战斗效果类型；新增值追加在末尾，保留已有资源的枚举编号。
enum EffectType {
	## 对目标造成伤害；基础值由damage_source决定。
	DAMAGE,

	## 为目标增加amount点格挡。
	BLOCK,

	## 让行动者抽取amount张牌；第二阶段只允许以SELF为目标。
	DRAW,

	## 为玩家增加amount点当前能量，不改变每回合基础能量。
	GAIN_ENERGY,

	## 强化当前武器：amount为攻击增量，durability_bonus为耐久增量。
	ENHANCE_WEAPON,

	## 玩家直接失去amount点生命，不经过攻击或格挡计算。
	LOSE_HEALTH,

	## 为目标增加amount点本场力量，玩家与敌人均可使用。
	GAIN_STRENGTH,

	## 为目标施加amount回合虚弱或易伤。
	APPLY_WEAK,
	APPLY_VULNERABLE,

	## 为目标施加power_definition中的持续能力，不使用amount。
	APPLY_POWER,

	## 禁止玩家在本回合继续抽牌，不使用amount。
	PREVENT_DRAW,

	## 玩家减少amount点最大生命；当前生命只压到新上限，损失持续整局。
	LOSE_MAX_HEALTH,

	## 本回合后续每打出一张攻击牌回复amount能量；重复施加相加。
	GAIN_ATTACK_CARD_ENERGY
}


## 一项效果相对于行动者的目标类型。
enum TargetType {
	## 效果作用于行动者自己。
	SELF,

	## 效果作用于行动者的对手。
	OPPONENT
}


## 伤害基础值的来源，与攻击／非攻击类别相互独立。
enum DamageSource { FIXED, CURRENT_BLOCK }


## 当前效果的基础类型，决定控制器安排哪一种行为。
@export var effect_type:EffectType


## 当前效果相对于行动者的目标；这里只描述方向，不保存实际角色对象。
@export var target_type:TargetType


## 当前效果每次执行时使用的数值。
##
## 固定DAMAGE表示单段基础伤害，BLOCK表示单次格挡，DRAW表示单次抽牌数量。
## GAIN_ENERGY表示单次获得的当前能量。
## GAIN_ATTACK_CARD_ENERGY表示本回合每张后续攻击牌的回能增量。
## ENHANCE_WEAPON表示武器攻击力增量。
## LOSE_HEALTH表示直接失去的生命值。
## LOSE_MAX_HEALTH表示减少的最大生命值。
## GAIN_STRENGTH表示力量增量。
## APPLY_WEAK、APPLY_VULNERABLE表示持续回合数。
## 数值效果必须填写正数；APPLY_POWER、PREVENT_DRAW和按格挡伤害不使用此字段。
@export var amount:int = 0

## 仅DAMAGE使用。攻击伤害受力量、虚弱和易伤修正；非攻击伤害只抵消格挡。
## 卡牌类型与伤害类别相互独立。旧资源的伤害均为攻击，默认保持这一语义。
@export var is_attack_damage:bool = true

## 仅DAMAGE使用。CURRENT_BLOCK在每段执行时读取行动者格挡，不消耗其格挡。
@export var damage_source:DamageSource = DamageSource.FIXED

## 仅DAMAGE使用：每段伤害后，行动者恢复等同于目标实际失血的生命。
## 格挡抵消与过量伤害不计入治疗；治疗仍受行动者最大生命限制。
@export var heals_from_damage:bool = false

## 仅ENHANCE_WEAPON使用：同时增加最大耐久和当前耐久。
@export var durability_bonus:int = 0

## 仅APPLY_POWER使用；支持保留格挡与自身回合开始失血换格挡。
@export var power_definition:PowerDefinition


## 当前效果需要独立执行的次数。
##
## 例如amount为3且repeat_count为2的DAMAGE，会被控制器解释为两次
## 独立的3点伤害，而不是一次6点伤害。该数值必须大于0。
@export var repeat_count:int = 1


## 预览与结算共用基础值选择；current_block由调用方提供当时的格挡。
func get_base_damage(current_block:int)->int:
	return current_block if damage_source == DamageSource.CURRENT_BLOCK else amount;


## 检查当前战斗效果定义是否包含非法数据。
##
## 效果类型或目标类型不属于对应枚举、数值效果非正数、重复次数小于或等于0时，
## 推送对应错误并返回true。玩家专用效果只能以SELF为目标，武器强化的耐久增量也须为正数。
## 所有数据均满足当前阶段规则时返回false。
## 该方法只检查静态配置，不会修复数据或执行任何效果。
func is_invalid()->bool:
	if not EffectType.values().has(effect_type):
		push_error("非法的效果类型，战斗效果定义无效");#报告具体的配置错误，方便定位资源问题
		return true;#发现第一个错误后立即结束验证
	if not TargetType.values().has(target_type):#确认目标类型确实属于SELF或OPPONENT
		push_error("非法的目标类型，战斗效果定义无效");#报告目标类型配置错误
		return true;#非法目标不能继续参与效果解释
	if effect_type == EffectType.DAMAGE and not DamageSource.values().has(damage_source):
		push_error("伤害基础值来源无效");
		return true;
	if effect_type == EffectType.APPLY_POWER:
		if power_definition == null:
			push_error("施加能力效果缺少能力定义");
			return true;
		if power_definition.is_invalid():
			return true;
	elif effect_type != EffectType.PREVENT_DRAW and not (effect_type == EffectType.DAMAGE and damage_source == DamageSource.CURRENT_BLOCK) and amount <= 0:
		# 按格挡伤害允许基础值为0，其余数值效果仍要求配置正数。
		push_error("效果数值必须大于0，战斗效果定义无效");#报告数值配置错误
		return true;#非正数效果没有合法的执行意义
	if repeat_count <= 0:#效果至少需要执行一次
		push_error("效果重复次数必须大于0，战斗效果定义无效");#报告重复次数配置错误
		return true;#零次或负数次执行均视为非法
	if effect_type in [EffectType.DRAW, EffectType.GAIN_ENERGY, EffectType.ENHANCE_WEAPON, EffectType.LOSE_HEALTH, EffectType.PREVENT_DRAW, EffectType.LOSE_MAX_HEALTH, EffectType.GAIN_ATTACK_CARD_ENERGY] and target_type != TargetType.SELF:
		push_error("玩家专用效果只能以SELF为目标");
		return true;#目标语义不合法时拒绝该效果定义
	if effect_type == EffectType.ENHANCE_WEAPON and durability_bonus <= 0:
		push_error("武器强化的耐久增量必须大于0");
		return true;
	return false;#全部检查通过，当前战斗效果定义合法
