## 第一阶段单场战斗的流程控制器。
##
## 负责创建测试战斗、处理玩家出牌与回合切换、驱动敌人固定行动，
## 并在任意一方生命归零后完成胜负结算与重开。
##
## BattleState是战斗运行时数据的唯一可信来源；ActionQueue按顺序执行伤害、格挡与抽牌；
## CombatantView和CardView只负责显示数据与报告玩家输入，不直接修改战斗状态。
extends Node
class_name BattleController

## CardView的场景模板；每张手牌都会由它实例化出一个独立界面。
const CARD_VIEW_SCENE:PackedScene = preload("res://cards/card_view.tscn");

## 测试牌组使用的静态卡牌定义；多个CardInstance可以共享同一份定义。
const STRIKE_DEFINITION:CardDefinition = preload("res://cards/data/strike.tres");
const DEFEND_DEFINITION:CardDefinition = preload("res://cards/data/defend.tres");

## 测试玩家的固定初始数据。
const PLAYER_NAME:String = "玩家";
const PLAYER_MAX_HEALTH:int = 50;

## 测试敌人的固定初始数据；攻击值同时用于显示意图和结算敌人行动。
const ENEMY_NAME:String = "测试敌人";
const ENEMY_MAX_HEALTH:int = 30;
const ENEMY_ATTACK_DAMAGE:int = 6;

## 玩家每回合恢复的基础能量，以及战斗开始时的起手牌数。
const ENERGY_PER_TURN:int = 3;
const STARTING_HAND_SIZE:int = 5;

## 测试牌组中两种卡牌各自的数量。
const STARTING_STRIKE_COUNT:int = 5;
const STARTING_DEFEND_COUNT:int = 5;

## 当前战斗的唯一数据源。
##
## 界面刷新时只读取这份状态；重新开始时会将它替换为全新的BattleState。
var battle_state:BattleState;

## 当前战斗使用的同步行为队列。
##
## 控制器先将伤害、格挡或抽牌行为按顺序加入队列，再统一结算。
var action_queue:ActionQueue = ActionQueue.new();

## 下列@onready引用会在控制器进入场景树后取得实际UI节点。
## battle_controller与main_layout同为battle的子节点，因此路径先用".."回到battle。
## 玩家角色界面。
@onready var player_view:CombatantView = $"../main_layout/player_area/player_view";

## 敌人角色界面。
@onready var enemy_view:CombatantView = $"../main_layout/enemy_area/enemy_view";

## 左下角战斗信息。
@onready var energy_label:Label = $"../main_layout/battle_info_area/energy_label";
@onready var draw_pile_label:Label = $"../main_layout/battle_info_area/draw_pile_label";
@onready var discard_pile_label:Label = $"../main_layout/battle_info_area/discard_pile_label";

## 底部手牌区域。
@onready var hand_area:HBoxContainer = $"../main_layout/hand_area";

## 右下角结束回合按钮。
@onready var end_turn_button:Button = $"../main_layout/end_turn_button";

## 胜负结算时覆盖普通战斗界面的结果遮罩。
@onready var result_overlay:PanelContainer = $"../result_overlay";
## 请求创建一场全新测试战斗的按钮。
@onready var restart_button:Button = $"../result_overlay/result_layout/restart_button";

## 显示“胜利”或“失败”的结果文字。
@onready var result_label:Label = $"../result_overlay/result_layout/result_label";

## 控制器进入场景树后，连接按钮信号、隐藏结算遮罩，并安排战斗初始化。
##
## 使用call_deferred可以把初始化推迟到当前场景就绪之后，确保兄弟UI节点的
## _ready和@onready都已完成，再去绑定角色与卡牌数据。
func _ready()->void:
	end_turn_button.pressed.connect(_on_end_turn_button_pressed);#按下“结束回合”时转到控制器处理
	restart_button.pressed.connect(_on_restart_button_pressed);#按下“重新开始”时创建全新战斗
	result_overlay.hide();#新战斗开始时不显示胜负遮罩
	call_deferred("_start_test_battle");#等所有UI节点就绪后再启动测试战斗
	
## 根据一份静态CardDefinition，创建并初始化一张独立的运行时卡牌。
##
## 每次成功调用都会返回不同的CardInstance，所以它们可以分别保存临时费用等状态。
## definition为空或实例初始化失败时推送错误，不产生半成品，并返回null。
func _create_card_instance(definition:CardDefinition)->CardInstance:
	if definition == null:#没有卡牌定义，就无法确定名称、费用和效果数值
		push_error("卡牌定义为空，无法创建卡牌实例");
		return null;
	
	var new_card_instance:CardInstance = CardInstance.new();#先创建一张尚未填入定义的运行时卡牌
	if not new_card_instance.card_instance_init(definition):#验证定义，并复制初始费用
		push_error("卡牌实例初始化失败");
		return null;
	
	return new_card_instance;#只有完整初始化后才交给调用者
	
## 创建包含指定数量打击和防御的全新测试牌组。
##
## 每个循环都会创建新的CardInstance，而不是把同一个实例重复放入牌组。
## 任意卡牌创建失败时返回空数组，使调用者可以放弃启动这场战斗。
func _create_starting_deck()->Array[CardInstance]:
	var starting_deck:Array[CardInstance] = [];#这个局部数组暂存刚创建的全部卡牌实例
	
	for _card_index in range(STARTING_STRIKE_COUNT):#range(5)会让循环执行5次
		var strike_instance:CardInstance = _create_card_instance(STRIKE_DEFINITION);
		if strike_instance == null:#只要有一张创建失败，就不使用这份不完整的牌组
			return [];
		starting_deck.append(strike_instance);
	
	for _card_index in range(STARTING_DEFEND_COUNT):#循环变量加下划线，表示这里不需要使用其数值
		var defend_instance:CardInstance = _create_card_instance(DEFEND_DEFINITION);
		if defend_instance == null:
			return [];
		starting_deck.append(defend_instance);
	
	return starting_deck;#成功时交出10个彼此独立的CardInstance


## 创建全新的玩家、敌人、牌组和BattleState，并开始第一个玩家回合。
##
## 方法先在局部变量中组装完整战斗；任何一步失败都立即结束。
## 核心数据初始化成功后，将其保存到battle_state、重新绑定角色界面，
## 恢复普通战斗UI，最后调用_start_player_turn开始第一回合。
func _start_test_battle()->void:
	action_queue.clear_actions();#防止上一场未执行的行为残留到新战斗
	
	var player_state:CombatantState = CombatantState.new();#创建全新的玩家状态
	player_state.combatant_init(
		PLAYER_NAME,
		PLAYER_MAX_HEALTH
	);#初始化玩家名称、生命和格挡
	
	var enemy_state:CombatantState = CombatantState.new();#创建全新的敌人状态
	enemy_state.combatant_init(
		ENEMY_NAME,
		ENEMY_MAX_HEALTH
	);#初始化敌人名称、生命和格挡
	
	var starting_deck:Array[CardInstance] = _create_starting_deck();#创建全新的运行时牌组
	
	if starting_deck.is_empty():
		push_error("初始牌组创建失败，无法开始测试战斗");
		return;
	
	var new_battle_state:BattleState = BattleState.new();#暂时在局部变量中创建新战斗
	
	if not new_battle_state.battle_state_init(
		player_state,
		enemy_state,
		starting_deck,
		ENERGY_PER_TURN
	):
		push_error("战斗状态初始化失败");
		return;
	
	new_battle_state.shuffle_draw_pile();#所有卡牌初始化在抽牌堆中，开始前先洗牌
	
	battle_state = new_battle_state;#初始化成功，正式保存为当前战斗状态
	
	if not player_view.bind_combatant_state(battle_state.player_state):
		push_error("玩家界面绑定失败");
		return;
	
	if not enemy_view.bind_combatant_state(battle_state.enemy_state):
		push_error("敌人界面绑定失败");
		return;
	
	enemy_view.set_intent(
		"攻击：%d" % ENEMY_ATTACK_DAMAGE
	);#显示敌人的固定攻击意图
	
	result_overlay.hide();#重新开始时隐藏上一场战斗的结果界面
	
	end_turn_button.disabled = false;#新战斗允许玩家再次结束回合
	
	_start_player_turn();#统一恢复能量、增加回合编号、抽牌并刷新界面
	
## 从当前BattleState重新读取数据，统一刷新角色、能量、牌堆数量和手牌。
##
## 这是“数据改变后通知界面更新”的入口；它只读取并显示数据，
## 不在刷新过程中扣血、扣能量或移动卡牌。
func _refresh_battle_view()->void:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法刷新战斗界面");
		return;
	
	player_view.refresh_combatant_view();#角色View会从已绑定的CombatantState中重新读取生命和格挡
	enemy_view.refresh_combatant_view();
	energy_label.text = "能量：%d / %d" % [
		battle_state.current_available_energy,
		battle_state.energy_per_turn
	];#%d会按数组顺序填入“当前能量 / 每回合能量”
	draw_pile_label.text = "抽牌堆：%d" % battle_state.draw_pile.size();#size()返回数组中的卡牌数量
	discard_pile_label.text = "弃牌堆：%d" % battle_state.discard_pile.size();
	_rebuild_hand();#以BattleState.hand为标准，让屏幕上的手牌与数据完全一致
	
	
## 删除旧的CardView，并以BattleState.hand为标准重新创建全部手牌界面。
##
## CardInstance是牌的真实运行时数据，CardView只是显示这份数据的UI节点。
## 这里删除的只是hand_area中的旧View，不会删除battle_state.hand里的CardInstance。
## 整手重建会牺牲旧View的临时动画状态，但在第一阶段能简单、可靠地保证数据与画面一致。
func _rebuild_hand()->void:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法重建手牌界面");
		return;
	
	for child in hand_area.get_children():#取得并逐一处理当前所有旧手牌界面
		hand_area.remove_child(child);#立即从HBoxContainer中移走，让容器不再参与它的排版
		child.queue_free();#在当前帧安全结束后销毁节点，避免立即释放干扰当前流程
	
	for card_in_hand in battle_state.hand:#手牌数组中每个CardInstance都要有一个对应View
		var new_card_view:CardView = CARD_VIEW_SCENE.instantiate() as CardView;#由场景模板创建一份独立UI
		if new_card_view == null:#场景根节点没有CardView脚本时，as转换会得到null
			push_error("CardView场景实例化失败");
			return;
		
		hand_area.add_child(new_card_view);#必须先进入场景树，CardView中的@onready引用才会准备完成
		
		if not new_card_view.bind_card_instance(card_in_hand):#将这张真实卡牌数据交给新View显示
			hand_area.remove_child(new_card_view);#绑定失败时清理刚创建的空壳界面
			new_card_view.queue_free();
			continue;#只跳过当前无效卡牌，继续尝试显示后面的手牌
		
		new_card_view.card_selected.connect(_on_card_selected);#以后点击任意手牌都会回到控制器处理


## 根据卡牌目标与基础数值，将这张牌的伤害和格挡效果加入队列。
##
## 指向自己的卡牌以玩家为目标，指向敌人的卡牌以当前敌人为目标。
## 该方法只安排效果，不消耗能量、不移动卡牌，也不立即执行效果。
func _queue_card_effect(card:CardInstance)->bool:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法安排卡牌效果");
		return false;
	if card == null or card.is_invalid_instance():
		push_error("需要安排效果的卡牌实例无效");
		return false;
	
	var effect_target:CombatantState = battle_state.player_state;#默认以玩家自己为目标
	
	if card.definition.requires_target():
		effect_target = battle_state.enemy_state;#第一阶段只有一个敌人，不需要额外选择目标
	
	var has_queued_effect:bool = false;
	
	if card.definition.base_damage_amount > 0:
		if not action_queue.queue_damage(
			effect_target,
			card.definition.base_damage_amount
		):
			action_queue.clear_actions();
			return false;
		has_queued_effect = true;
	
	if card.definition.base_block_amount > 0:
		if not action_queue.queue_block(
			effect_target,
			card.definition.base_block_amount
		):
			action_queue.clear_actions();
			return false;
		has_queued_effect = true;
	
	if not has_queued_effect:
		push_error("卡牌没有可以执行的伤害或格挡效果");
		return false;
	
	return true;

## 结束当前战斗，并显示指定的战斗结果。
##
## 调用后将阶段设为FINISHED，清空未执行行为，禁用结束回合按钮，
## 然后刷新双方最终状态并显示结果遮罩。
func _finish_battle(result_text:String)->void:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法结束战斗");
		return;
	
	battle_state.current_phase = BattleState.BattlePhase.FINISHED;#阻止继续出牌或结束回合
	action_queue.clear_actions();#战斗结束后不应继续执行残留行为
	end_turn_button.disabled = true;#让按钮在画面上也表现为不可操作
	
	result_label.text = result_text;#显示“胜利”或“失败”
	_refresh_battle_view();#显示双方最终生命、格挡和牌堆状态
	result_overlay.show();#用结果界面覆盖普通战斗界面

## 检查当前战斗是否已经产生胜负结果。
##
## 敌人死亡时以胜利结束战斗，玩家死亡时以失败结束战斗。
## 检测到结果并完成结算时返回true；双方都存活时返回false。
func _check_battle_result()->bool:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法检查战斗结果");
		return false;
	
	if battle_state.is_victory():
		_finish_battle("胜利!");
		return true;
	
	if battle_state.is_defeat():
		_finish_battle("失败!");
		return true;
	
	return false;

## 接收CardView报告的玩家选择，并尝试打出这张卡牌。
##
## 只有玩家回合中、卡牌仍在手牌里且能量充足时才能打出。
## 成功后扣除能量、将卡牌移入弃牌堆、执行效果并刷新界面。
func _on_card_selected(selected_card:CardInstance)->void:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法打出卡牌");
		return;
	
	if battle_state.current_phase != BattleState.BattlePhase.PLAYER_TURN:
		return;#不是玩家回合时忽略卡牌点击
	
	if battle_state.is_victory() or battle_state.is_defeat():
		return;#战斗结果已经产生时不再处理卡牌点击
	
	if selected_card == null or selected_card.is_invalid_instance():
		push_error("CardView报告了无效卡牌实例");
		return;
	
	if not battle_state.hand.has(selected_card):
		push_error("玩家选择的卡牌已经不在手牌中");
		return;
	
	if not selected_card.can_afford(battle_state.current_available_energy):
		print("能量不足，无法打出：%s" % selected_card.definition.card_name);
		return;
	
	action_queue.clear_actions();#确保本次结算从空队列开始
	
	if not _queue_card_effect(selected_card):
		return;
	
	if not battle_state.spend_energy(selected_card.current_energy_cost):
		action_queue.clear_actions();
		push_error("卡牌费用消耗失败");
		return;
	
	if not battle_state.discard_card_from_hand(selected_card):
		action_queue.clear_actions();
		push_error("卡牌无法从手牌移动到弃牌堆");
		return;
	
	var resolved_successfully:bool = action_queue.resolve_all();

	if not resolved_successfully:
		push_error("卡牌行为没有完整执行");
		_refresh_battle_view();
		return;

	if _check_battle_result():#攻击可能在这里让敌人生命归零
		return;

	_refresh_battle_view();


## 开始一个新的玩家回合。
##
## 先确认战斗尚未结束，再清除玩家上回合剩余格挡、恢复能量、
## 增加回合编号并同步执行抽牌。全部成功后切换至PLAYER_TURN并刷新界面。
func _start_player_turn()->void:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法开始玩家回合");
		return;
	
	if _check_battle_result():
		return;
	
	battle_state.player_state.clear_block();#玩家上回合剩余的格挡在新回合开始时清除
	battle_state.reset_energy_for_turn();#把当前能量恢复为每回合基础能量
	battle_state.current_turn_number += 1;#进入下一个回合
	
	action_queue.clear_actions();
	
	if not action_queue.queue_draw(battle_state,STARTING_HAND_SIZE):
		push_error("新玩家回合的抽牌行为加入失败");
		return;
	
	if not action_queue.resolve_all():
		push_error("新玩家回合的抽牌行为执行失败");
		return;
	
	battle_state.current_phase = BattleState.BattlePhase.PLAYER_TURN;
	_refresh_battle_view();

## 执行第一阶段的固定敌人回合。
##
## 敌人清除自己的旧格挡，然后通过ActionQueue执行当前固定攻击意图。
## 攻击后检查战斗结果；玩家存活时立即进入下一个玩家回合。
func _run_enemy_turn()->void:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法执行敌人回合");
		return;
	
	if battle_state.current_phase != BattleState.BattlePhase.ENEMY_TURN:
		push_error("当前不是敌人回合，无法执行敌人行动");
		return;
	
	if _check_battle_result():
		return;
	
	battle_state.enemy_state.clear_block();#敌人在自己的回合开始时清除旧格挡
	action_queue.clear_actions();
	
	if not action_queue.queue_damage(
		battle_state.player_state,
		ENEMY_ATTACK_DAMAGE
	):
		push_error("敌人攻击行为加入失败");
		_refresh_battle_view();
		return;
	
	if not action_queue.resolve_all():
		push_error("敌人攻击行为执行失败");
		_refresh_battle_view();
		return;
	
	if _check_battle_result():#敌人攻击可能在这里让玩家生命归零
		return;
	
	_start_player_turn();

## 接收玩家的结束回合请求。
##
## 只有玩家回合中才能结束回合。成功后弃掉剩余手牌，
## 将阶段切换为敌人回合，并立即执行固定敌人行动。
func _on_end_turn_button_pressed()->void:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法结束回合");
		return;
	
	if battle_state.current_phase != BattleState.BattlePhase.PLAYER_TURN:
		return;
	
	if _check_battle_result():
		return;
	
	battle_state.current_phase = BattleState.BattlePhase.ENEMY_TURN;#先切换阶段，阻止继续出牌
	battle_state.discard_hand();#把玩家没有打出的剩余手牌全部移入弃牌堆
	_run_enemy_turn();
	
## 放弃旧的测试战斗，并从初始数据创建一场全新战斗。
##
## 旧BattleState在没有引用后会自动释放。_start_test_battle会重置角色、牌堆、能量、
## 回合和行为队列，隐藏结果遮罩，最后根据新的手牌数据重建界面。
func _on_restart_button_pressed()->void:
	_start_test_battle();#复用同一条初始化流程，避免维护两套重复逻辑
