## 角色的静态内容：玩家属性、基础牌组和奖励卡池。
## 本局实际获得的卡牌和当前生命仍由RunState保存，不写回这份资源。
class_name CharacterDefinition
extends Resource


## 稳定的角色ID，例如warrior。
@export var character_id:String

## 角色的名称、最大生命和原画。
@export var combatant_definition:CombatantDefinition

## 按“卡牌定义＋数量”配置基础牌组，由RunState展开为实际拥有的卡牌。
@export var starting_deck_entries:Array[DeckEntryDefinition] = []

## 每种奖励卡只配置一次；玩家实际拥有的同名卡可以有多张。
@export var reward_card_pool:Array[CardDefinition] = []


## 检查编辑器中可能漏填或填错的角色配置。
## 卡牌及牌组条目的内部规则交给各自定义验证，这里只检查引用与集合约束。
func is_invalid()->bool:
	if character_id.is_empty():
		push_error("角色ID不能为空");
		return true;
	if combatant_definition == null:
		push_error("角色缺少玩家定义");
		return true;
	if combatant_definition.is_invalid():
		return true;
	if starting_deck_entries.is_empty():
		push_error("角色基础牌组不能为空");
		return true;

	var starting_card_ids:Dictionary = {};
	for entry in starting_deck_entries:
		if entry == null:
			push_error("角色基础牌组包含空条目");
			return true;
		if entry.is_invalid():
			return true;
		var card_id:String = entry.card_definition.card_id;
		if starting_card_ids.has(card_id):
			push_error("基础牌组重复配置卡牌：%s，请使用同一条目的count设置数量" % card_id);
			return true;
		starting_card_ids[card_id] = true;

	if reward_card_pool.is_empty():
		push_error("角色奖励卡池不能为空");
		return true;

	var reward_card_ids:Dictionary = {};
	for card in reward_card_pool:
		if card == null:
			push_error("角色奖励卡池包含空卡牌");
			return true;
		if card.is_invalid():
			return true;
		if reward_card_ids.has(card.card_id):
			push_error("角色奖励卡池重复配置卡牌：%s" % card.card_id);
			return true;
		reward_card_ids[card.card_id] = true;

	return false;
