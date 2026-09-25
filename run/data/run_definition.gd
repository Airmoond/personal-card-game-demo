## 一局冒险的静态规则入口。
## 角色内容由CharacterDefinition保存；这里组合角色、地图与奖励规则。
## 当前生命、实际牌组和地图进度仍属于RunState。
class_name RunDefinition
extends Resource

## 开局逐轮选牌的固定顺序；每轮展示该稀有度的全部角色卡牌。
const DRAFT_RARITIES:Array[int] = [
	CardDefinition.CardRarity.LEGENDARY,
	CardDefinition.CardRarity.EPIC,
	CardDefinition.CardRarity.RARE
];


## 稳定的冒险ID，例如default_run。
@export var run_id:String

## 本局使用的角色，统一提供玩家定义、基础牌组和奖励卡池。
@export var character_definition:CharacterDefinition

## 地图结构与节点内容，运行时只读。
@export var map_definition:MapDefinition

## 每轮展示的不同奖励卡数量，不能超过角色非传说卡池容量。
@export var reward_option_count:int = 3

## 可配置连续奖励轮数；默认冒险资源设为一次。
@export var reward_selection_count:int = 3


## 检查必需引用与整局规则，角色内部配置交给CharacterDefinition验证。
func is_invalid()->bool:
	if run_id.is_empty():
		push_error("冒险ID不能为空");
		return true;
	if character_definition == null:
		push_error("冒险缺少角色定义");
		return true;
	if character_definition.is_invalid():
		return true;
	if map_definition == null:
		push_error("冒险缺少地图定义");
		return true;
	if map_definition.is_invalid():
		return true;
	var reward_candidates:Array[CardDefinition] = CardPoolSampler.filter_pool(
		character_definition.reward_card_pool, CardPoolSampler.REWARD_RARITIES
	);
	if reward_option_count <= 0 or reward_option_count > reward_candidates.size():
		push_error("奖励选项数必须大于0，且不能超过角色非传说卡池大小");
		return true;
	if reward_selection_count <= 0:
		push_error("奖励选择次数必须大于0");
		return true;
	for rarity in DRAFT_RARITIES:
		if CardPoolSampler.filter_pool(character_definition.reward_card_pool, [rarity]).is_empty():
			push_error("开局选牌每个稀有度至少需要一张候选，缺少：%d" % rarity);
			return true;
	return false;
