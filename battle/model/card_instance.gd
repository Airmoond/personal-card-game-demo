## 表示战斗中一张具体卡牌的运行时实例。
##
## 每个实例引用一份CardDefinition，并独立保存本场战斗中的临时数据。
## 多个CardInstance可以引用同一份CardDefinition，但彼此的当前费用互不影响。
class_name CardInstance;
extends RefCounted

## 该实例引用的卡牌定义资源。
##
## 用于读取卡牌名称、描述、类型、目标类型和基础数值等固定数据。
## 成功初始化后该变量不能为null，并且不应在战斗过程中修改定义资源本身。
var definition:CardDefinition;

## 这张具体卡牌当前需要消耗的能量。
##
## 初始化时复制自definition.base_energy_cost，之后可以被临时费用效果独立修改。
## 该数值必须大于或等于0。
var current_energy_cost:int;


## 使用传入的卡牌定义初始化当前卡牌实例。
##
## 如果card_def为null，返回false，且不修改当前实例。
## 如果card_def的定义无效，返回false，且不修改当前实例。
## 初始化成功时，保存definition引用，将current_energy_cost设置为基础费用，并返回true。
func card_instance_init(card_def:CardDefinition)->bool:
	if card_def == null:
		return false;
	if card_def.is_invalid():
		return false;
	
	definition = card_def;#检查合格后，把外部传进来的定义赋给definition
	current_energy_cost = card_def.base_energy_cost;
	return true;


## 检查当前运行时卡牌实例是否无效。
##
## definition为null时返回true。
## definition本身无效时返回true。
## current_energy_cost小于0时返回true。
## 所有数据均合法时返回false。
func is_invalid_instance()->bool:
	if definition == null:
		return true;
	if definition.is_invalid():
		return true;
	if current_energy_cost < 0:
		return true;
	return false;


## 判断玩家当前可用能量是否足以支付这张卡牌的当前费用。
##
## 该方法应当只对已经成功初始化的有效卡牌实例调用。
## energy_can_use小于0时返回false。
## energy_can_use大于或等于current_energy_cost时返回true。
## energy_can_use小于current_energy_cost时返回false。
## 该方法只进行判断，不会扣除玩家能量。
func can_afford(energy_can_use:int)->bool:
	if energy_can_use<0:
		return false;
	if energy_can_use>=current_energy_cost:
		return true;
	return false;


## 安全地修改这张具体卡牌的当前能量费用。
##
## new_energy_cost小于0时推送错误、立即结束，并保持原费用不变。
## new_energy_cost大于或等于0时，将其保存为新的current_energy_cost。
## 该方法没有返回值，也不会修改CardDefinition中的基础费用。
func set_current_energy_cost(new_energy_cost:int)->void:
	if new_energy_cost<0:
		push_error("Invalid new cost! 非法的新费用")
		return;
	current_energy_cost=new_energy_cost;


## 将当前费用恢复为卡牌定义中的基础费用。
##
## definition为null或定义无效时推送错误、立即结束，并保持当前费用不变。
## definition存在且合法时，将current_energy_cost恢复为definition.base_energy_cost。
## 该方法没有返回值，也不会修改CardDefinition本身。
func reset_energy_cost()->void:
	if definition == null or definition.is_invalid():
		push_error("非法的定义，更新费用失败")
		return;
	current_energy_cost=definition.base_energy_cost;
