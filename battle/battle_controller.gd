## 可由外部游戏流程启动的单场战斗编排器。
##
## 负责根据遭遇、玩家、本局牌组和跨战斗剩余生命创建全新战斗，
## 处理玩家出牌、回合切换、敌人行动和效果结算，并通过battle_finished
## 报告胜负与玩家剩余生命。战斗只能由外部流程通过start_battle启动。
##
## BattleState是战斗运行时数据的唯一可信来源；ActionQueue按顺序执行伤害、格挡与抽牌；
## CombatantView和CardView只负责显示数据与报告玩家输入，不直接修改战斗状态。
## BattleController不读取RunState，不发放奖励、完成地图节点或决定页面切换。
extends Node
class_name BattleController

## CardView的场景模板；每张手牌都会由它实例化出一个独立界面。
const CARD_VIEW_SCENE:PackedScene = preload("res://cards/card_view.tscn");

## 当前单场战斗首次产生最终结果时发出。
##
## victory表示玩家是否击败敌人；remaining_player_health是战斗结束时玩家的
## 实际剩余生命。该信号只报告单场战斗结果，不修改RunState、不完成地图节点，
## 也不决定下一页显示地图、奖励还是整局结算。
signal battle_finished(
	victory:bool,
	remaining_player_health:int
)

## 当前战斗的唯一数据源。
##
## 界面刷新时只读取这份状态；每次start_battle都会用全新的BattleState替换它。
var battle_state:BattleState;

## 当前战斗使用的同步行为队列。
##
## 控制器先将伤害、格挡或抽牌行为按顺序加入队列，再统一结算。
var action_queue:ActionQueue = ActionQueue.new();

## 当前这场战斗是否已经向外报告过最终结果。
##
## _check_battle_result可能在出牌后、敌人行动后和回合切换前被多次调用，
## 因此需要该标记保证同一场战斗最多发出一次battle_finished。
## 每次start_battle成功建立新战斗时必须重新设为false。
var _battle_result_reported:bool = false

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

## 控制器进入场景树后连接战斗页面自己的输入信号。
##
## 本方法不再自动创建战斗；外部GameFlowController会在页面准备完成后调用
## start_battle，并传入当前地图节点与RunState对应的数据。
func _ready()->void:
	end_turn_button.pressed.connect(_on_end_turn_button_pressed);#按下“结束回合”时转到控制器处理
	
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


## 根据一组实际拥有的静态卡牌定义，创建当前单场战斗使用的完整牌组。
##
## deck_definitions中的每个元素都代表玩家实际拥有的一张卡，因此即使多个元素
## 引用同一份CardDefinition，也会分别创建彼此独立的CardInstance。
## 方法先验证整个输入数组，再进入实例创建阶段，避免在发现后续非法定义前
## 已经产生部分牌组。
##
## 数组为空、包含null、包含非法CardDefinition，或任意CardInstance创建失败时，
## 推送对应错误并返回空数组。成功时返回元素数量与deck_definitions完全一致的新牌组。
## 该方法不修改传入数组或任何静态.tres资源。
func _create_deck_from_definitions(
	deck_definitions:Array[CardDefinition]
)->Array[CardInstance]:
	var new_deck:Array[CardInstance] = [];#局部保存当前正在构建的全部独立卡牌实例
	if deck_definitions.is_empty():#无卡牌时无法创建当前阶段要求的可用战斗牌组
		push_error("卡牌定义数组为空，无法创建战斗牌组");#报告外部流程没有传入本局实际拥有的卡牌
		return new_deck;#保持空数组，让战斗初始化统一中止

	for card_index in range(deck_definitions.size()):#第一轮只验证，避免非法后续元素产生半成品牌组
		var card_definition:CardDefinition = deck_definitions[card_index];#取得当前位置代表的一张实际拥有卡牌
		if card_definition == null:#空引用无法提供卡牌身份、费用或效果
			push_error("卡牌定义[%d]为空，无法创建战斗牌组" % card_index);#报告非法元素的准确下标
			return new_deck;#实例创建尚未开始，因此数组仍然为空
		if card_definition.is_invalid():#卡牌ID、名称、费用、描述和效果必须完整合法
			push_error("卡牌定义[%d]无效，无法创建战斗牌组" % card_index);#补充牌组输入中的位置上下文
			return new_deck;#非法静态资源不能用于创建任何运行时卡牌

	for card_definition in deck_definitions:#全部定义合法后，再按原数组顺序创建每张卡的独立实例
		var card_instance:CardInstance = _create_card_instance(card_definition);#每次循环都会创建一个新CardInstance
		if card_instance == null:#任意一张卡创建失败都会使整副战斗牌组不完整
			push_error("战斗牌组中的卡牌实例创建失败");#报告已进入运行时实例创建阶段
			return [];#丢弃局部半成品，不把缺牌的牌组交给BattleState

		new_deck.append(card_instance);#一个输入元素只对应追加一个已完整初始化的新实例

	return new_deck;#成功时元素数量与deck_definitions一致，并保留输入顺序


## 使用外部游戏流程提供的静态数据启动一场全新战斗。
##
## encounter只提供敌人与单场战斗规则；player_definition提供玩家静态属性；
## deck_definitions中的每个元素都代表玩家在当前整局中实际拥有的一张卡；
## starting_player_health是上一场战斗或休整结算后保存的跨战斗生命。
##
## 方法会验证全部输入，在局部变量中创建全新的CombatantState、EnemyState、
## CardInstance牌组和BattleState。全部初始化成功后才替换battle_state，
## 清理旧行为队列、重置结果上报状态、绑定界面并开始第一个玩家回合。
##
## 成功时返回true。控制器尚未进入场景树，或任意输入、运行时对象创建、
## BattleState初始化或角色界面绑定失败时，推送对应错误并返回false。
## 该方法不读取或修改RunState，也不修改任何传入的静态Resource。
## 调用方必须先把battle.tscn实例加入场景树，再调用本方法。
func start_battle(
	encounter:EncounterDefinition,
	player_definition:CombatantDefinition,
	deck_definitions:Array[CardDefinition],
	starting_player_health:int
)->bool:
	if not is_node_ready():#@onready界面引用准备好之前不能绑定角色或刷新战斗画面
		push_error("BattleController尚未准备完成，无法开始战斗");#报告外部流程调用时机错误
		return false;#不在缺少界面节点的情况下创建部分战斗
	if encounter == null:#没有遭遇时无法确定敌人和单场规则
		push_error("遭遇定义为空，无法开始战斗");#报告流程控制器没有传入地图节点的遭遇
		return false;#空遭遇不能成为战斗的静态数据源
	if encounter.is_invalid():#EncounterDefinition负责验证敌人与所有单场规则
		push_error("遭遇定义无效，无法开始战斗");#补充外部战斗入口的错误上下文
		return false;#非法静态规则不能进入运行时战斗
	if player_definition == null:#外部流程必须明确提供本局使用的玩家定义
		push_error("玩家定义为空，无法开始战斗");#报告无法创建玩家运行时状态
		return false;#空玩家定义不能用于创建本场CombatantState
	if player_definition.is_invalid():#玩家ID、名称、最大生命和原画必须完整合法
		push_error("玩家定义无效，无法开始战斗");#补充玩家运行时初始化上下文
		return false;#非法定义不能成为CombatantState的数据源
	if starting_player_health <= 0:#0生命表示整局已失败，不能进入下一场战斗
		push_error("战斗起始生命必须大于0");#报告流程层尝试使用死亡玩家启动战斗
		return false;#非正数生命不能写入新CombatantState
	if starting_player_health > player_definition.max_health:#跨战斗生命不能突破玩家静态上限
		push_error("战斗起始生命不能超过玩家最大生命");#报告RunState回写或治疗计算可能已损坏
		return false;#不通过静默截断掩盖外部状态错误

	var new_player_state:CombatantState = CombatantState.new();#为本场战斗创建全新玩家生命与格挡状态
	if not new_player_state.combatant_init_from_definition(player_definition):#先从外部玩家定义建立最大生命和显示数据
		push_error("玩家状态初始化失败，无法开始战斗");#报告运行时玩家创建失败
		return false;#不使用未完整初始化的CombatantState
	if not new_player_state.set_current_health(starting_player_health):#再把RunState保存的剩余生命写入新玩家状态
		push_error("玩家剩余生命设置失败，无法开始战斗");#补充跨战斗生命注入阶段的上下文
		return false;#生命设置失败时不继续构建敌人或牌组

	var new_enemy_state:EnemyState = EnemyState.new();#每场战斗都使用新的敌人生命、格挡和行动下标
	if not new_enemy_state.enemy_state_init(encounter.enemy_definition):#敌人内容只来自当前地图节点传入的遭遇
		push_error("敌人状态初始化失败，无法开始战斗");#报告敌人定义或行动模式初始化失败
		return false;#缺少合法当前意图的敌人不能进入战斗

	var new_deck:Array[CardInstance] = _create_deck_from_definitions(
		deck_definitions
	);#按本局实际拥有的每个定义创建一张独立运行时卡牌
	if new_deck.is_empty():#输入非法或任意实例创建失败都会得到空数组
		push_error("战斗牌组创建失败，无法开始战斗");#补充整场战斗初始化阶段的错误上下文
		return false;#不允许空牌组或半成品牌组进入BattleState

	var new_battle_state:BattleState = BattleState.new();#在局部变量中组装本场战斗的唯一运行时数据源
	if not new_battle_state.battle_state_init(
		new_player_state,
		new_enemy_state,
		new_deck,
		encounter.energy_per_turn,
		encounter.cards_per_turn,
		encounter.max_hand_size
	):#单场能量、抽牌和手牌上限规则仍只来自EncounterDefinition
		push_error("战斗状态初始化失败，无法开始战斗");#报告运行时组装未通过BattleState验证
		return false;#局部半成品不会覆盖控制器当前的battle_state

	new_battle_state.shuffle_draw_pile();#初始牌组全部位于抽牌堆，正式提交前先随机打乱顺序

	if not player_view.bind_combatant_state(new_battle_state.player_state):#使玩家View读取本场新建的玩家状态
		push_error("玩家界面绑定失败，无法开始战斗");#报告战斗场景与运行时状态的契约不一致
		return false;#不提交无法完整显示玩家的新战斗
	if not enemy_view.bind_combatant_state(new_battle_state.enemy_state):#使敌人View读取本场新建的敌人状态
		push_error("敌人界面绑定失败，无法开始战斗");#报告敌人界面不能正常读取EnemyState
		return false;#不提交无法完整显示的新战斗

	action_queue.clear_actions();#全部新数据已组装并绑定成功，现在才放弃上一场的残留行为
	battle_state = new_battle_state;#全部初始化成功后一次性提交新的唯一战斗状态
	_battle_result_reported = false;#全新战斗尚未向GameFlowController报告任何胜负结果
	end_turn_button.disabled = false;#新战斗准备完成后恢复玩家的回合操作入口

	_start_player_turn();#统一恢复能量、增加回合编号、抽取起始手牌并刷新画面
	return true;#新BattleState已提交，并已进入第一个玩家回合

## 根据敌人当前行动的名称和真实效果生成纯显示用的意图文字。
##
## 伤害、格挡数值和重复次数只从action.effects读取，不从intent_text反推规则。
## 单效果与多效果行动都按照效果数组顺序显示；敌人不支持的DRAW效果会使生成失败。
## action为空或非法时推送错误并返回空字符串，让View清除旧意图。
## 该方法只生成文字，不执行效果，也不修改EnemyActionDefinition资源。
func _build_enemy_intent_text(action:EnemyActionDefinition)->String:
	if action == null or action.is_invalid():#只有完整合法的当前行动才能生成可信意图
		push_error("敌人当前行动无效，无法生成意图文字");#报告运行时敌人缺少可显示行动
		return "";#空字符串会让CombatantView隐藏旧意图

	var effect_descriptions:PackedStringArray = [];#按照行动效果顺序收集每一项显示说明
	for effect in action.effects:#显示与执行遍历同一份效果数组，避免产生两套数值来源
		var effect_description:String = "";#保存当前效果生成的局部说明
		match effect.effect_type:#根据效果类型选择玩家容易理解的显示名称
			CombatEffectDefinition.EffectType.DAMAGE:
				effect_description = "%d点伤害" % effect.amount;#伤害数值直接来自真实效果
			CombatEffectDefinition.EffectType.BLOCK:
				effect_description = "%d点格挡" % effect.amount;#格挡数值直接来自真实效果
			CombatEffectDefinition.EffectType.DRAW:
				push_error("敌人行动不能生成抽牌意图");#第二阶段敌人没有自己的牌堆
				return "";#拒绝显示无法正确执行的敌人效果
			_:
				push_error("敌人行动包含不支持的效果类型");#防止未知枚举被静默显示
				return "";#未知效果无法生成可信意图

		if effect.repeat_count > 1:#多段效果需要明确告诉玩家实际执行次数
			effect_description += " × %d" % effect.repeat_count;#例如显示为“3点伤害 × 2”
		effect_descriptions.append(effect_description);#保留行动资源中的原始效果顺序

	return "%s：%s" % [
		action.intent_text,
		"；".join(effect_descriptions)
	];#行动名称负责语义，效果列表负责提供不会失真的真实数值

## 从当前BattleState重新读取数据，统一刷新角色、能量、牌堆数量和手牌。
##
## 这是“数据改变后通知界面更新”的入口；敌人意图也从EnemyState.current_action
## 生成。该方法只读取并显示数据，不在刷新过程中扣血、扣能量或移动卡牌。
func _refresh_battle_view()->void:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法刷新战斗界面");
		return;
	
	player_view.refresh_combatant_view();#角色View会从已绑定的CombatantState中重新读取生命和格挡
	enemy_view.refresh_combatant_view();
	enemy_view.set_intent(
		_build_enemy_intent_text(battle_state.enemy_state.current_action)
	);#显示和敌人回合共同读取同一个当前行动资源
	energy_label.text = "能量：%d / %d" % [
		battle_state.current_available_energy,
		battle_state.energy_per_turn
	];#%d会按数组顺序填入“当前能量 / 每回合能量”
	draw_pile_label.text = "抽牌堆：%d" % battle_state.draw_pile.size();#size()返回数组中的卡牌数量
	discard_pile_label.text = "弃牌堆：%d" % battle_state.discard_pile.size();
	_rebuild_hand();#以BattleState.hand为标准，让屏幕上的手牌与数据完全一致
	
	
## 判断一张卡牌在当前战斗时刻是否应当显示为可以使用。
##
## 只有战斗状态存在、处于玩家回合、胜负尚未产生、卡牌实例合法且仍在手牌中，
## 并且玩家当前能量足以支付费用时才返回true。其他情况均返回false。
## 该方法只读取状态并返回显示判断，不消耗能量、不移动卡牌，也不执行任何效果。
## _on_card_selected仍会独立进行最终合法性检查，不能用本方法替代真实出牌验证。
func _card_is_playable(card:CardInstance)->bool:
	if battle_state == null:#没有战斗状态时无法确认回合、手牌归属或当前能量
		return false;#缺少判断依据时统一显示为不可使用
	if battle_state.current_phase != BattleState.BattlePhase.PLAYER_TURN:#只有玩家回合允许使用手牌
		return false;#设置阶段反馈，但不在View中阻止点击
	if battle_state.is_victory() or battle_state.is_defeat():#战斗结果产生后所有普通出牌都应停止
		return false;#结算状态下手牌统一显示为不可使用
	if card == null or card.is_invalid_instance():#空实例或非法实例不能成为合法出牌对象
		return false;#拒绝根据损坏数据显示可用状态
	if not battle_state.hand.has(card):#只有当前真实手牌中的实例才可能被玩家使用
		return false;#其他牌堆中的卡牌不能显示为可用手牌

	return card.can_afford(battle_state.current_available_energy);#最后根据当前费用与真实可用能量决定外观


## 删除旧的CardView，并以BattleState.hand为标准重新创建全部手牌界面。
##
## CardInstance是牌的真实运行时数据，CardView只是显示这份数据的UI节点。
## 这里删除的只是hand_area中的旧View，不会删除battle_state.hand里的CardInstance。
## 每张新View绑定成功后，由控制器计算当前是否可用，并调用纯显示方法更新外观。
## 整手重建会牺牲旧View的临时动画状态，但能简单、可靠地保证数据与画面一致。
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
		
		new_card_view.set_playable_visual(
			_card_is_playable(card_in_hand)
		);#控制器计算回合、胜负、手牌归属和能量，CardView只显示结果
		
		new_card_view.card_selected.connect(_on_card_selected);#以后点击任意手牌都会回到控制器处理


## 将一张卡牌的效果数组交给通用效果入队流程。
##
## 玩家是卡牌效果的行动者，当前敌人是行动者的对手。
## 该方法只验证卡牌入口并传递上下文，不消耗能量、不移动卡牌，也不执行效果。
func _queue_card_effect(card:CardInstance)->bool:
	if battle_state == null:#没有战斗状态时无法取得玩家、敌人和牌堆
		push_error("尚未创建战斗状态，无法安排卡牌效果");#报告调用时机错误
		return false;#保持队列和战斗数据不变
	if card == null or card.is_invalid_instance():#空卡牌或非法实例不能进入效果解释流程
		push_error("需要安排效果的卡牌实例无效");#报告传入卡牌错误
		return false;#拒绝安排任何行为

	return _queue_effect_list(
		card.definition.effects,
		battle_state.player_state,
		battle_state.enemy_state
	);#卡牌由玩家使用，因此SELF是玩家，OPPONENT是敌人


## 验证并按照数组顺序将一组战斗效果加入行为队列。
##
## actor_state是效果行动者，opponent_state是行动者的对手。
## 方法先验证全部效果，再调用_queue_single_effect逐项入队，确保非法的后续效果
## 不会让前面的部分效果单独留下。任意步骤失败时清空队列并返回false。
## 该方法不修改效果资源，也不立即执行已经加入的行为。
func _queue_effect_list(
	effects:Array[CombatEffectDefinition],
	actor_state:CombatantState,
	opponent_state:CombatantState
)->bool:
	if battle_state == null:#抽牌效果和玩家身份判断都需要当前战斗状态
		push_error("尚未创建战斗状态，无法安排效果列表");#报告缺少通用入队上下文
		action_queue.clear_actions();#保证失败时没有残留行为
		return false;#无法安全解释效果列表
	if actor_state == null:#SELF目标必须能够指向一个实际行动者
		push_error("效果行动者为空，无法安排效果列表");#报告调用方传入的行动者错误
		action_queue.clear_actions();#清除可能已经存在的本次行为
		return false;#缺少行动者时拒绝继续
	if opponent_state == null:#OPPONENT目标必须能够指向一个实际对手
		push_error("效果对手为空，无法安排效果列表");#报告调用方传入的对手错误
		action_queue.clear_actions();#保证失败返回时队列为空
		return false;#缺少对手时拒绝继续
	if actor_state == opponent_state:#行动者和对手不能引用同一个角色状态
		push_error("效果行动者与对手相同，无法安排效果列表");#避免SELF和OPPONENT失去实际区别
		action_queue.clear_actions();#清除无法正确解释目标的行为
		return false;#上下文非法时结束
	if effects.is_empty():#效果列表至少需要包含一项静态效果定义
		push_error("效果数组为空，无法安排效果列表");#指出静态效果资源存在配置遗漏
		action_queue.clear_actions();#保持失败后的队列为空
		return false;#空数组没有可以执行的内容

	for effect_index in range(effects.size()):#第一轮只验证，保证开始入队前全部效果都合法
		var effect_to_validate:CombatEffectDefinition = effects[effect_index];#取得当前下标对应的效果
		if effect_to_validate == null:#防止效果数组中存在空资源位置
			push_error("效果[%d]为空，无法安排效果列表" % effect_index);#报告具体的非法下标
			action_queue.clear_actions();#保证失败返回时队列为空
			return false;#不继续解释剩余效果
		if effect_to_validate.is_invalid():#让效果定义检查自身的类型、目标、数值和次数
			push_error("效果[%d]无效，无法安排效果列表" % effect_index);#补充效果数组中的位置上下文
			action_queue.clear_actions();#保证非法列表不会留下待执行行为
			return false;#全部效果没有通过验证，不能进入第二轮

	for effect_to_queue in effects:#第二轮严格按照资源数组顺序安排全部效果
		if not _queue_single_effect(effect_to_queue,actor_state,opponent_state):#把一项效果的目标、类型和次数交给单项方法处理
			action_queue.clear_actions();#撤销列表中此前已经加入但尚未执行的全部行为
			return false;#任何一项失败都会让整组效果入队失败

	return true;#全部效果均按照设计顺序成功加入队列


## 将一项已经验证的战斗效果转换为一个或多个ActionQueue行为。
##
## SELF选择actor_state，OPPONENT选择opponent_state；repeat_count决定加入多少次
## 独立行为。DAMAGE、BLOCK和DRAW分别转换为伤害、格挡和玩家抽牌。
## 第二阶段不允许敌人抽牌，因此DRAW的行动者必须是当前玩家。
## 该方法不负责清空队列；失败后的整体回滚由_queue_effect_list统一处理。
func _queue_single_effect(
	effect:CombatEffectDefinition,
	actor_state:CombatantState,
	opponent_state:CombatantState
)->bool:
	if battle_state == null:#抽牌行为和玩家身份检查需要当前战斗状态
		push_error("尚未创建战斗状态，无法安排单项效果");#报告缺少执行上下文
		return false;#无法安全加入行为
	if effect == null or effect.is_invalid():#即使被单独调用，也要拒绝空效果或非法配置
		push_error("需要安排的单项效果无效");#报告传入效果错误
		return false;#不向队列加入任何新行为
	if actor_state == null or opponent_state == null:#目标解释需要行动者和对手同时存在
		push_error("单项效果缺少行动者或对手");#报告调用方传入的角色上下文错误
		return false;#缺少实际目标时拒绝入队
	if actor_state == opponent_state:#SELF和OPPONENT必须对应不同角色
		push_error("单项效果的行动者与对手相同");#报告无法区分目标的上下文
		return false;#阻止效果作用到错误角色

	var effect_target:CombatantState = actor_state;#SELF默认选择效果行动者自己
	if effect.target_type == CombatEffectDefinition.TargetType.OPPONENT:#OPPONENT要求切换到行动者的对手
		effect_target = opponent_state;#保存本项效果的实际角色目标

	if effect.effect_type == CombatEffectDefinition.EffectType.DRAW and actor_state != battle_state.player_state:#当前牌堆系统只属于玩家
		push_error("第二阶段不允许敌人执行抽牌效果");#防止敌人DRAW错误地操作玩家牌堆
		return false;#拒绝无法正确表达的敌人抽牌

	for _repeat_index in range(effect.repeat_count):#每次循环都加入一次独立行为，保留多段效果语义
		var queued_successfully:bool = false;#记录当前这一段效果是否成功进入队列
		match effect.effect_type:#把静态效果类型翻译为ActionQueue支持的基础行为
			CombatEffectDefinition.EffectType.DAMAGE:#伤害效果作用于选择出的角色目标
				queued_successfully = action_queue.queue_damage(effect_target,effect.amount);#加入一段独立伤害
			CombatEffectDefinition.EffectType.BLOCK:#格挡效果作用于选择出的角色目标
				queued_successfully = action_queue.queue_block(effect_target,effect.amount);#加入一次独立格挡
			CombatEffectDefinition.EffectType.DRAW:#抽牌效果操作当前玩家的BattleState牌堆
				queued_successfully = action_queue.queue_draw(battle_state,effect.amount);#加入一次玩家抽牌行为
			_:#即使资源绕过前置验证，也不能静默忽略未知类型
				push_error("遇到不支持的战斗效果类型，无法安排单项效果");#报告无法解释的枚举值

		if not queued_successfully:#任意一次重复入队失败都会让当前效果失败
			return false;#交给效果列表方法统一清空已经加入的行为

	return true;#当前效果的全部重复次数均成功加入队列

## 提交当前单场战斗的最终结果，并且只向外报告一次。
##
## victory为true时必须已满足BattleState.is_victory，为false时必须已满足
## BattleState.is_defeat。成功提交后将阶段设为FINISHED、清空未执行行为、
## 禁用普通回合输入、刷新最终战斗状态，再把结果报告给外部流程。
##
## 方法在发出battle_finished前先保存_battle_result_reported，防止多个胜负
## 检查点对同一场战斗重复发奖、完成节点或切换页面。信号发出后不再访问
## 当前战斗界面，因为外部接收者可能在信号回调中立即替换本页面。
func _finish_battle(victory:bool)->void:
	if battle_state == null:#没有当前单场战斗时无法取得可信的胜负和剩余生命
		push_error("尚未创建战斗状态，无法结束战斗");#报告结算方法被过早或错误调用
		return;#空状态不能发出任何战斗结果
	if _battle_result_reported:#当前start_battle周期已经完成过一次结果上报
		return;#同一场战斗不重复提交状态或发出结果信号
	if victory and not battle_state.is_victory():#胜利参数必须与敌人的实际存活状态一致
		push_error("当前战斗尚未胜利，无法提交胜利结果");#阻止调用者使用错误布尔值结束战斗
		return;#保留当前回合与未上报状态
	if not victory and not battle_state.is_defeat():#失败参数必须与玩家的实际存活状态一致
		push_error("当前战斗尚未失败，无法提交失败结果");#阻止尚存活的玩家被错误结算
		return;#不改变战斗阶段、队列或界面

	var remaining_player_health:int = (
		battle_state.player_state.current_health
	);#在外部流程可能替换战斗页面前，先快照玩家最终剩余生命

	battle_state.current_phase = BattleState.BattlePhase.FINISHED;#阻止继续出牌或结束回合
	action_queue.clear_actions();#战斗结束后不应继续执行残留行为
	end_turn_button.disabled = true;#让按钮在画面上也表现为不可操作

	_refresh_battle_view();#显示双方最终生命、格挡和牌堆状态

	_battle_result_reported = true;#先提交一次性标记，防止信号回调或后续检查再次进入结算
	battle_finished.emit(
		victory,
		remaining_player_health
	);#作为最后一步报告结果，由GameFlowController决定奖励、地图或整局结算

## 检查当前战斗是否已经产生胜负结果。
##
## 敌人死亡时使用true提交胜利，玩家死亡时使用false提交失败。
## 检测到新结果，或当前战斗已经报告过结果时返回true，让调用者立即
## 停止出牌、抽牌或敌人行动等后续流程；双方都存活且尚未结算时返回false。
func _check_battle_result()->bool:
	if battle_state == null:#缺少状态时无法判断任何真实胜负
		push_error("尚未创建战斗状态，无法检查战斗结果");#报告战斗检查被过早调用
		return false;#没有实际结果可以提交
	if _battle_result_reported:#同一场战斗的结果已经发送给外部流程
		return true;#继续告诉所有调用者立即停止普通战斗流程

	if battle_state.is_victory():#敌人已经失去全部生命
		_finish_battle(true);#使用结构化布尔值提交单场胜利
		return true;#阻止当前调用点再刷新普通回合或执行其他行为

	if battle_state.is_defeat():#玩家已经失去全部生命
		_finish_battle(false);#使用结构化布尔值提交单场失败
		return true;#阻止敌人行动推进或新玩家回合继续开始

	return false;#双方都存活，当前战斗应继续运行

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
	
	if not action_queue.queue_draw(battle_state,battle_state.cards_per_turn):#每回合抽牌数读取BattleState保存的遭遇规则
		push_error("新玩家回合的抽牌行为加入失败");
		return;
	
	if not action_queue.resolve_all():
		push_error("新玩家回合的抽牌行为执行失败");
		return;
	
	battle_state.current_phase = BattleState.BattlePhase.PLAYER_TURN;
	_refresh_battle_view();

## 执行EnemyState中已经提前准备好的当前敌人行动。
##
## 先验证当前行动，再清除敌人的旧格挡，并将current_action.effects按照原顺序
## 交给通用效果入队流程。效果结算后检查战斗结果；玩家存活时推进固定行动模式，
## 准备下一次意图，然后进入新的玩家回合。
## 显示和执行始终引用同一个current_action，不从意图文字反推任何战斗规则。
func _run_enemy_turn()->void:
	if battle_state == null:
		push_error("尚未创建战斗状态，无法执行敌人回合");
		return;
	
	if battle_state.current_phase != BattleState.BattlePhase.ENEMY_TURN:
		push_error("当前不是敌人回合，无法执行敌人行动");
		return;
	
	if _check_battle_result():
		return;

	var current_enemy_action:EnemyActionDefinition = battle_state.enemy_state.current_action;#保存本回合将要显示和执行的同一行动引用
	if current_enemy_action == null or current_enemy_action.is_invalid():#无效行动不能进入部分结算流程
		push_error("敌人当前行动无效，无法执行敌人回合");#报告EnemyState没有准备好合法意图
		_refresh_battle_view();#保持画面与当前未执行的状态一致
		return;#不清除格挡、不执行效果，也不推进行动模式
	
	battle_state.enemy_state.clear_block();#敌人在自己的回合开始时清除旧格挡
	action_queue.clear_actions();
	
	if not _queue_effect_list(
		current_enemy_action.effects,
		battle_state.enemy_state,
		battle_state.player_state
	):#敌人是行动者，因此SELF指向敌人，OPPONENT指向玩家
		push_error("敌人当前行动效果加入失败");
		_refresh_battle_view();
		return;
	
	if not action_queue.resolve_all():
		push_error("敌人当前行动效果执行失败");
		_refresh_battle_view();
		return;
	
	if _check_battle_result():#敌人行动可能在这里让玩家生命归零
		return;

	if not battle_state.enemy_state.advance_to_next_action():#只有本次行动完成且玩家存活时才准备下一项意图
		push_error("敌人行动模式推进失败");#报告EnemyState无法建立下一回合的当前行动
		_refresh_battle_view();#显示已经结算的生命和格挡，同时保留当前行动便于定位错误
		return;#模式推进失败时不开始新的玩家回合
	
	_start_player_turn();#玩家回合刷新界面时会显示推进后的新current_action

## 接收玩家的结束回合请求。
##
## 只有玩家回合中才能结束回合。成功后弃掉剩余手牌，
## 将阶段切换为敌人回合，并立即执行EnemyState已经准备好的当前行动。
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
