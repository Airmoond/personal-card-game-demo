## 保存一场战斗当前时刻的全部运行时状态。
##
## 包含参战角色、能量、回合阶段以及抽牌堆、手牌和弃牌堆。
## BattleState是战斗数据的唯一可信来源；控制器负责调用这里的方法推进战斗，
## 显示层只读取这些状态并更新画面，不应把UI中的数值反向当作真实战斗数据。
class_name BattleState
extends RefCounted

## 当前战斗所处的阶段。
enum BattlePhase{
	## 战斗正在初始化，玩家和敌人的回合尚未开始。
	SETUP,

	## 当前允许玩家抽牌、出牌和结束回合。
	PLAYER_TURN,

	## 当前由敌人执行行动。
	ENEMY_TURN,

	## 当前战斗已经结束，不应继续执行普通回合操作。
	FINISHED
}

## 当前战斗中的玩家状态实例，用于读取和修改玩家的生命与格挡等真实数据。
var player_state:CombatantState;

## 当前战斗中的敌人状态实例，用于读取和修改敌人的生命与格挡等真实数据。
var enemy_state:CombatantState;

## 玩家每个回合开始时应当恢复到的基础能量，不能小于0。
var energy_per_turn:int;#每回合开始恢复的能量

## 玩家当前能够用于支付卡牌费用的能量，不能小于0。
var current_available_energy:int;#当前可用的能量

## 当前抽牌堆中的卡牌实例；数组末尾视为牌堆顶端。
var draw_pile:Array[CardInstance];

## 玩家当前持有的卡牌实例；其中每张卡牌都可以在显示层拥有对应的card_view。
var hand:Array[CardInstance];

## 当前弃牌堆中的卡牌实例；抽牌堆耗尽时，这些卡牌会被重新洗入抽牌堆。
var discard_pile:Array[CardInstance];

## 当前战斗阶段，用于让控制器判断此刻允许执行哪些战斗操作。
var current_phase:BattlePhase;

## 当前回合编号；初始化时为0，正式开始新的玩家回合时再由控制器递增。
var current_turn_number:int=0;#当前回合编号

## 玩家能够持有的最大手牌数量；达到或超过该数值时不能继续抽牌。
var max_hand_size:int=10;

## 使用参战角色、初始牌组和每回合能量初始化一场新战斗。
##
## player或enemy为null、任意一方未存活、energy_start小于0，或者start_pile为空时，
## 推送对应错误、保持当前BattleState原有数据不变，并返回false。
## start_pile中存在null、非法CardInstance，或者重复放入同一个CardInstance时，
## 推送对应错误、保持当前BattleState原有数据不变，并返回false。
## 所有参数合法时保存角色引用，将start_pile中的卡牌实例放入draw_pile，清空hand和
## discard_pile，把能量、回合编号和阶段恢复为战斗初始状态，然后返回true。
## 该方法会复制start_pile数组本身，但不会复制数组中的CardInstance。
func battle_state_init(player:CombatantState,enemy:CombatantState,start_pile:Array[CardInstance],energy_start:int)->bool:
	if player == null:
		push_error("非法玩家对象，战斗初始化失败")
		return false;
	if enemy == null:
		push_error("非法敌人对象，战斗初始化失败")
		return false;
	if not player.is_alive():
		push_error("玩家未存活，战斗初始化失败")
		return false;
	if not enemy.is_alive():
		push_error("敌人未存活，战斗初始化失败")
		return false;
	if energy_start<0:
		push_error("初始能量非法，战斗初始化失败")
		return false;
	if start_pile.is_empty():
		push_error("初始牌组为空，战斗初始化失败")
		return false;
	var start_pile_instance_ids:Dictionary = {};
	for card in start_pile:
		if card == null:
			push_error("牌组中存在空卡牌，战斗初始化失败")
			return false;
		if card.is_invalid_instance():
			push_error("牌组中存在非法卡牌实例，战斗初始化失败")
			return false;
		var card_instance_id:int = card.get_instance_id();
		if start_pile_instance_ids.has(card_instance_id):
			push_error("初始牌组中重复使用了同一个卡牌实例，战斗初始化失败")
			return false;
		start_pile_instance_ids[card_instance_id] = true;
		
	player_state = player;
	enemy_state = enemy;
	
	draw_pile = start_pile.duplicate();
	hand.clear();
	discard_pile.clear();
	current_available_energy = 0;
	current_turn_number = 0;
	current_phase = BattlePhase.SETUP;
	energy_per_turn = energy_start;
	
	return true;

## 检查当前战斗状态是否存在非法数据。
##
## 角色状态为空，能量或回合编号小于0，手牌上限不合法，或者手牌数量超过上限时，
## 推送对应错误并返回true。
## 任意牌堆中存在null、非法CardInstance，或者同一个CardInstance在一个或多个牌堆中
## 重复出现时，推送对应错误并返回true。
## 上述非法情况均不存在时返回false。
## 该方法只检查数据，不会修复或修改当前战斗状态。
func is_invalid_battle()->bool:
	if player_state == null:
		push_error("玩家状态为空，战斗状态非法")
		return true;
	if enemy_state == null:
		push_error("敌人状态为空，战斗状态非法")
		return true;
	if energy_per_turn < 0:
		push_error("每回合能量小于零，战斗状态非法")
		return true;
	if current_available_energy < 0:
		push_error("当前可用能量小于零，战斗状态非法")
		return true;
	if current_turn_number < 0:
		push_error("当前回合编号小于零，战斗状态非法")
		return true;
	if max_hand_size <= 0:
		push_error("手牌上限小于或等于零，战斗状态非法")
		return true;
	if hand.size() > max_hand_size:
		push_error("当前手牌数量超过手牌上限，战斗状态非法")
		return true;
	
	for card in draw_pile:
		if card == null:
			push_error("抽牌堆中存在空卡牌，战斗状态非法")
			return true;
		if card.is_invalid_instance():
			push_error("抽牌堆中存在非法卡牌实例，战斗状态非法")
			return true;
	
	for card in hand:
		if card == null:
			push_error("手牌中存在空卡牌，战斗状态非法")
			return true;
		if card.is_invalid_instance():
			push_error("手牌中存在非法卡牌实例，战斗状态非法")
			return true;
	
	for card in discard_pile:
		if card == null:
			push_error("弃牌堆中存在空卡牌，战斗状态非法")
			return true;
		if card.is_invalid_instance():
			push_error("弃牌堆中存在非法卡牌实例，战斗状态非法")
			return true;

	var all_pile_cards:Array[CardInstance];
	all_pile_cards.append_array(draw_pile);
	all_pile_cards.append_array(hand);
	all_pile_cards.append_array(discard_pile);
	var all_pile_instance_ids:Dictionary = {};
	for card in all_pile_cards:
		var card_instance_id:int = card.get_instance_id();
		if all_pile_instance_ids.has(card_instance_id):
			push_error("多个牌堆中重复存在同一个卡牌实例，战斗状态非法")
			return true;
		all_pile_instance_ids[card_instance_id] = true;
	
	return false;


## 将玩家当前可用能量恢复为每回合基础能量。
##
## 调用后，current_available_energy将等于energy_per_turn。
## 调用方应当保证当前BattleState已经成功初始化且energy_per_turn合法。
## 该方法只负责恢复能量，不负责开始玩家回合，也没有返回值。
func reset_energy_for_turn()->void:
	current_available_energy = energy_per_turn;


## 尝试消耗指定数量的当前可用能量。
##
## energy_cost小于0时推送错误、保持当前能量不变，并返回false。
## 当前能量不足时保持当前能量不变，并返回false。
## 当前能量足够时扣除energy_cost，并返回true。
## energy_cost等于0时不改变当前能量，并返回true。
## 该方法只处理能量，不检查卡牌实例、目标或当前战斗阶段是否合法。
func spend_energy(energy_cost:int)->bool:
	if energy_cost < 0:
		push_error("需要消耗的能量小于零，能量消耗失败")
		return false;
	if current_available_energy < energy_cost:
		return false;
	current_available_energy -= energy_cost;
	return true;


## 随机打乱当前抽牌堆中卡牌实例的排列顺序。
##
## 抽牌堆少于两张卡牌时不执行操作。
## 抽牌堆至少有两张卡牌时调用数组的随机打乱功能。
## 该方法只改变卡牌在draw_pile中的顺序，不会创建、删除或复制卡牌，也没有返回值。
func shuffle_draw_pile()->void:
	if draw_pile.size() < 2:
		return;
	draw_pile.shuffle();


## 尝试从抽牌堆顶端抽取一张卡牌并加入玩家手牌。
##
## 手牌已满时不修改任何牌堆，并返回null。
## draw_pile为空而discard_pile不为空时，先将弃牌堆移动到抽牌堆并进行洗牌。
## 完成上述处理后仍然没有可抽取的卡牌时返回null。
## 成功时从draw_pile末尾取出同一个CardInstance，将其加入hand并返回该实例。
## 该方法不会创建或复制CardInstance。
func draw_one_card()->CardInstance:
	if hand_is_full():
		return null;
	if draw_pile.is_empty() and !discard_pile.is_empty():#如果抽牌堆空了，尝试洗牌
		draw_pile = discard_pile.duplicate();
		discard_pile.clear();
		shuffle_draw_pile();
		
	if draw_pile.is_empty():#如果洗完还是没牌，那就是真没了
		return null;
		
	var drawn_card:CardInstance = draw_pile.pop_back();#数组末尾视为牌堆顶端！
	hand.push_back(drawn_card);
	return drawn_card;


## 检查玩家当前手牌是否已经达到或超过手牌上限。
##
## hand中的卡牌数量小于max_hand_size时返回false。
## hand中的卡牌数量大于或等于max_hand_size时返回true。
## 该方法只读取手牌数量，不会修改任何牌堆。
func hand_is_full()->bool:
	if hand.size()<max_hand_size:
		return false;
	else:
		return true;

## 尝试连续抽取指定数量的卡牌。
##
## draw_count小于或等于0时不修改任何牌堆，并返回空数组。
## 每次抽牌都会调用draw_one_card；当手牌已满或所有牌堆均无牌可抽时提前停止。
## 返回值包含本次实际成功抽到的全部CardInstance，数量可能小于draw_count。
## 如果一张牌也没有成功抽取，则返回空数组。
func draw_multiple_cards(draw_count:int)->Array[CardInstance]:
	var cards_need_drawn:Array[CardInstance];#本次被抽取的那几张牌
	if draw_count<=0:#若要抽的卡牌数量小于等于0，直接返回空数组
		return cards_need_drawn;
	for i in range(draw_count):
		var drawn_card:CardInstance = draw_one_card();
		if drawn_card == null:
			break;
		cards_need_drawn.push_back(drawn_card);
	return cards_need_drawn;


## 尝试将指定卡牌实例从手牌移动到弃牌堆。
##
## card为null时推送错误、保持所有牌堆不变，并返回false。
## card不在hand中时保持所有牌堆不变，并返回false。
## card存在于hand中时，将同一个CardInstance从hand移除并加入discard_pile，然后返回true。
## 该方法不会创建、复制或销毁卡牌实例。
func discard_card_from_hand(card:CardInstance)->bool:
	if card == null:
		push_error("需要弃置的卡牌实例为空，弃牌失败")
		return false;
	if not hand.has(card):
		return false;
	hand.erase(card);
	discard_pile.push_back(card);
	return true;


## 将玩家当前手牌中的所有卡牌实例移动到弃牌堆。
##
## 手牌为空时不执行任何操作。
## 手牌不为空时，将其中的全部CardInstance加入discard_pile，然后清空hand。
## 该方法移动的是原有卡牌实例，不会创建、复制或销毁卡牌，也没有返回值。
func discard_hand()->void:
	discard_pile.append_array(hand);
	hand.clear();


## 判断玩家是否已经取得当前战斗的胜利。
##
## enemy_state为null时返回false，避免把缺少敌人的非法状态误判为胜利。
## enemy_state仍然存活时返回false。
## enemy_state存在且已经死亡时返回true。
## 该方法只读取敌人状态，不会修改角色数据或current_phase。
func is_victory()->bool:
	if enemy_state == null:
		return false;
	if enemy_state.is_alive():
		return false;
	return true;


## 判断玩家是否已经在当前战斗中失败。
##
## player_state为null时返回false，避免把缺少玩家的非法状态误判为失败。
## player_state仍然存活时返回false。
## player_state存在且已经死亡时返回true。
## 该方法只读取玩家状态，不会修改角色数据或current_phase。
func is_defeat()->bool:
	if player_state == null:
		return false;
	if player_state.is_alive():
		return false;
	return true;
	
	
	
	
	
