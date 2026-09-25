## 负责一整局冒险的页面切换与流程编排。
##
## 本控制器属于“流程编排层”：持有跨战斗的 [RunState]，并在主菜单、地图、
## 战斗、奖励和结算页面之间切换。它不负责执行具体战斗逻辑，也不会修改静态资源。
class_name GameFlowController
extends Node

## 用于创建每一局新冒险的静态配置。
@export var run_definition:RunDefinition


## 主菜单页面场景。
@export var main_menu_scene:PackedScene

## 逐轮开局构筑页面，布局可直接在Godot场景中调整。
@export var starting_draft_scene:PackedScene


## 地图页面场景。
@export var map_scene:PackedScene


## 单场战斗页面场景。
@export var battle_scene:PackedScene


## 卡牌奖励页面场景。
@export var reward_scene:PackedScene


## 整局胜利或失败结算页面场景。
@export var result_scene:PackedScene

## 当前整局冒险唯一的运行时状态。
##
## 主菜单阶段为null；开始新局后创建，返回主菜单时释放，再次开始时重新创建。
var run_state:RunState


## 当前显示在page_container中的页面节点。
##
## 切换页面时释放旧节点并保存新节点，保证同时只有一个活动页面。
var current_page:Node


## 当前普通战斗奖励阶段还需要完成的选择次数。
##
## 该变量只管理连续奖励页面的短期流程；真正获得的卡牌仍保存在RunState中。
var _remaining_reward_selections:int = 0


## 所有流程页面共同使用的父节点。
##
## 第12步重组main.tscn时，需要在GameFlowController旁边创建名为
## page_container的全屏Control节点。
@onready var page_container:Control = $"../page_container"


## 在控制器进入场景树后启动整局游戏流程。
##
## 静态配置全部有效时显示主菜单；配置无效时停止启动，避免玩家进入不完整流程。
func _ready()->void:
	if not _validate_configuration(): # 在创建页面前一次性检查流程依赖是否完整。
		return

	_show_main_menu() # 游戏入口固定从主菜单开始。


## 清理上一局状态，创建并显示主菜单页面，再监听玩家的开始请求。
##
## 主菜单只负责报告玩家输入；真正的新局状态由本控制器创建。
func _show_main_menu()->void:
	run_state = null # 返回主菜单即结束上一局，不让生命、牌组或地图进度继续存活。
	_remaining_reward_selections = 0 # 清除仅服务于上一局奖励阶段的临时计数。

	var main_menu:MainMenu = _replace_page(main_menu_scene) as MainMenu # 替换页面并确认具体View类型。
	if main_menu == null:
		push_error("GameFlowController：主菜单场景的根节点必须挂载 MainMenu 脚本。")
		return

	main_menu.start_requested.connect(_start_new_run) # 把界面意图交给流程层处理。


## 根据静态冒险定义创建一份全新的局内状态，并进入地图页面。
##
## 初始化成功前不会覆盖现有 [member run_state]，因此重新开始时也不会留下
## 初始化到一半的局内状态。
func _start_new_run()->void:
	var new_run_state:RunState = RunState.new() # 每次开始都创建独立状态，避免继承上一局数据。
	if not new_run_state.run_state_init(run_definition): # 从只读定义复制初始生命、牌组与地图进度。
		push_error("GameFlowController：新冒险初始化失败。")
		return

	run_state = new_run_state # 初始化完整后再提交为当前冒险的唯一状态。
	_remaining_reward_selections = 0 # 新冒险不能继承上一局尚未完成的奖励次数。
	_show_starting_draft()


## 本轮完整候选按角色卡池顺序筛选，分页只由页面负责。
func _show_starting_draft()->void:
	var candidates:Array[CardDefinition] = CardPoolSampler.filter_pool(
		run_definition.character_definition.reward_card_pool, [run_state.get_draft_rarity()]
	);
	var page:StartingDraftView = _replace_page(starting_draft_scene) as StartingDraftView;
	page.setup(run_state.get_draft_rarity(), candidates, run_state.owned_cards);
	page.card_selected.connect(_handle_starting_card_selected);
	page.back_requested.connect(_show_main_menu);


## 只接受当前轮候选；先提交牌组，再创建下一轮页面或地图。
func _handle_starting_card_selected(card:CardDefinition)->void:
	if not current_page is StartingDraftView:
		return;
	if not current_page.candidates.has(card):
		return;
	if not run_state.choose_starting_card(card):
		return;
	if run_state.status == RunState.RunStatus.DRAFTING:
		_show_starting_draft();
	else:
		_show_map();


## 创建地图页面，并用当前冒险的地图定义与运行时进度设置页面。
##
## [MapView] 只显示状态并报告节点选择，不直接调用 [RunState] 推进冒险。
func _show_map()->void:
	if run_state == null: # 主菜单阶段没有RunState，不能直接进入地图。
		push_error("GameFlowController：尚未创建局内状态，无法显示地图。")
		return
	if run_state.status != RunState.RunStatus.IN_PROGRESS:
		return # 构筑完成前不开放地图。

	var map_view:MapView = _replace_page(map_scene) as MapView # 旧页面会由统一入口负责释放。
	if map_view == null:
		push_error("GameFlowController：地图场景的根节点必须挂载 MapView 脚本。")
		return

	if not map_view.setup(run_definition.map_definition,run_state): # 静态地图决定结构，RunState决定进度。
		push_error("GameFlowController：地图页面设置失败。")
		return

	map_view.node_selected.connect(_handle_map_node_selected) # 流程层负责提交节点选择。


## 接收地图页面报告的节点选择，提交节点进度并进入对应流程。
##
## 战斗与Boss节点共用同一个战斗启动入口；休整节点立即恢复生命、完成节点，
## 然后返回刷新后的地图。节点的运行时进度只通过 [RunState] 修改。
func _handle_map_node_selected(node_id:String)->void:
	if not run_state.enter_node(node_id): # 把节点从“可进入”正式推进为“正在处理”。
		push_error("GameFlowController：无法进入玩家选择的地图节点：%s" % node_id)
		return

	var node:MapNodeDefinition = run_definition.map_definition.get_node_by_id(node_id) # 读取节点的静态类型与内容。
	if node.requires_encounter():
		_start_battle_for_node(node) # 普通战斗和Boss战使用相同的单场战斗入口。
		return

	run_state.heal(node.heal_amount) # 满生命时实际恢复量可以为0，但休整仍然完成。
	if not run_state.complete_current_node(): # 记录休整完成，并解锁静态配置中的后继节点。
		push_error("GameFlowController：休整节点完成失败。")
		return

	_show_map() # 创建新的地图页面，让画面重新读取已经更新的进度。


## 为当前战斗或Boss节点创建战斗页面，并注入本局玩家数据。
##
## [BattleController] 只接收遭遇、玩家定义、当前牌组和生命值；它不会读取
## [RunState]，战斗结束后只通过 [signal BattleController.battle_finished] 报告结果。
func _start_battle_for_node(node:MapNodeDefinition)->void:
	var battle_page:Node = _replace_page(battle_scene) # battle.tscn的根节点是完整战斗页面。
	if battle_page == null:
		return

	var battle_controller:BattleController = (
		battle_page.get_node_or_null("battle_controller") as BattleController
	) # 战斗逻辑控制器是页面根节点下的子节点，而不是场景根节点本身。
	if battle_controller == null:
		push_error("GameFlowController：战斗页面中缺少 BattleController。")
		return

	battle_controller.battle_finished.connect(_handle_battle_finished) # 战斗只报告结果，流程层决定去向。
	if not battle_controller.start_battle(
		node.encounter_definition, # 当前地图节点决定本场敌人与战斗规则。
		run_definition.character_definition.combatant_definition, # 玩家身份来自角色静态定义。
		run_state.owned_cards, # 每个元素会在战斗中重新创建一张CardInstance。
		run_state.current_health, # 使用上一节点结束后保留下来的跨战斗生命。
		run_state.max_health # 最大生命的整局变化同样延续到下一场。
	):
		push_error("GameFlowController：战斗启动失败。")


## 接收单场战斗结果。
##
## 首先把战斗剩余生命与最大生命回写到 [RunState]。失败时标记整局失败并显示结算；
## 普通战斗胜利时进入奖励页面；Boss胜利时完成节点、标记整局胜利并显示结算。
##
## 普通战斗节点会保留为当前节点，直到玩家完成全部奖励选择后才正式完成。
func _handle_battle_finished(
	victory:bool,
	remaining_player_health:int,
	remaining_player_max_health:int
)->void:
	run_state.current_health = remaining_player_health # 单场战斗结果写回跨战斗生命。
	run_state.max_health = remaining_player_max_health # 在奖励、休整或结算前同步本局上限。

	if not victory: # 战败不会完成当前节点，便于终局状态保留失败位置。
		if not run_state.mark_defeat(): # 先提交DEFEAT，再进入只负责显示的结算页面。
			push_error("GameFlowController：无法把当前冒险标记为失败。")
			return

		_show_result(false)
		return

	var current_node:MapNodeDefinition = run_definition.map_definition.get_node_by_id(
		run_state.current_node_id
	) # 战斗期间current_node_id始终保留，因此可以据此判断普通战斗或Boss。
	if current_node.node_type == MapNodeDefinition.NodeType.BOSS: # Boss胜利直接结束整局，不发卡牌奖励。
		if not run_state.complete_current_node(): # 先记录Boss完成并清空当前节点。
			push_error("GameFlowController：Boss节点完成失败。")
			return
		if not run_state.mark_victory(): # RunState会确认完成记录中确实包含Boss。
			push_error("GameFlowController：无法把当前冒险标记为胜利。")
			return

		_show_result(true)
		return

	_remaining_reward_selections = run_definition.reward_selection_count # 开始本次连续奖励流程。
	_show_reward() # 每轮选择后会根据剩余次数决定继续奖励或返回地图。


## 从静态奖励池中排除传说卡，无放回抽取本轮候选，再显示奖励页面。
##
## 只复制和打乱数组结构，数组中的 [CardDefinition] 仍是只读资源引用；
## 不会改变 [member CharacterDefinition.reward_card_pool] 的原始顺序或内容。
func _show_reward()->void:
	var reward_options:Array[CardDefinition] = CardPoolSampler.sample(
		run_definition.character_definition.reward_card_pool,
		run_definition.reward_option_count,
		CardPoolSampler.REWARD_RARITIES
	)
	if reward_options.is_empty():
		return # 抽样器已报告数量不足，保留当前页面，不展示空奖励页。

	var reward_view:RewardView = _replace_page(reward_scene) as RewardView # 用奖励页替换已经结束的战斗页。
	if reward_view == null:
		push_error("GameFlowController：奖励场景的根节点必须挂载 RewardView 脚本。")
		return

	if not reward_view.setup(reward_options): # View只负责把已经抽好的候选显示出来。
		push_error("GameFlowController：奖励页面设置失败。")
		return

	reward_view.reward_selected.connect(_handle_reward_selected) # 真正加卡仍回到流程层执行。


## 接收玩家选择的奖励卡，并推进当前连续奖励流程。
##
## 每次选择都先把卡牌加入本局牌组；仍有剩余次数时显示下一轮奖励，
## 全部选择完成后才提交普通战斗节点并返回地图。
func _handle_reward_selected(card_definition:CardDefinition)->void:
	if not run_state.add_card(card_definition): # 追加资源引用，表示本局实际多拥有一张卡。
		push_error("GameFlowController：奖励卡加入本局牌组失败。")
		return

	_remaining_reward_selections -= 1 # 当前选择已经成功写入牌组，再消耗一次流程计数。
	if _remaining_reward_selections > 0:
		_show_reward() # 创建新页面会重置RewardView的单次选择保护。
		return

	if not run_state.complete_current_node(): # 奖励领取成功后，普通战斗节点才算完整结束。
		push_error("GameFlowController：普通战斗节点完成失败。")
		return

	_show_map() # 新地图页会显示增加后的牌组数量和新解锁节点。


## 显示整局胜利或失败结算页面，并监听再次启程请求。
##
## 结算页面只显示传入结果；玩家请求再次启程时先返回主菜单，只有之后点击
## 主菜单的开始按钮才会通过 [method _start_new_run] 创建新的 [RunState]。
func _show_result(victory:bool)->void:
	var run_result:RunResult = _replace_page(result_scene) as RunResult # 终局页面替换战斗或其他流程页。
	if run_result == null:
		push_error("GameFlowController：结算场景的根节点必须挂载 RunResult 脚本。")
		return

	run_result.setup(victory) # 页面根据结果选择当前项目中已经确定的结算文本。
	run_result.restart_requested.connect(_show_main_menu) # 再次启程先回到主菜单并清理旧RunState。


## 检查开始游戏流程所需的静态配置和场景引用是否完整。
##
## 本方法只读取配置，不创建 [RunState]、不实例化页面，也不修改任何资源。
## 由于需要读取 [member page_container]，应当在节点完成 [code]@onready[/code]
## 初始化后调用。
##
## 返回 [code]true[/code] 表示配置完整，可以继续启动游戏流程；任一检查失败时
## 会输出有针对性的错误信息并返回 [code]false[/code]。
func _validate_configuration()->bool:
	if run_definition == null: # 整局玩家、牌组、地图和奖励都从这一个入口配置读取。
		push_error("GameFlowController：未配置 run_definition。")
		return false

	if run_definition.is_invalid(): # 具体静态字段交给RunDefinition自身验证。
		push_error("GameFlowController：run_definition 的内容无效，请检查其错误信息。")
		return false

	if main_menu_scene == null:
		push_error("GameFlowController：未配置 main_menu_scene。")
		return false
	if starting_draft_scene == null:
		push_error("GameFlowController：未配置 starting_draft_scene。");
		return false;

	if map_scene == null:
		push_error("GameFlowController：未配置 map_scene。")
		return false

	if battle_scene == null:
		push_error("GameFlowController：未配置 battle_scene。")
		return false

	if reward_scene == null:
		push_error("GameFlowController：未配置 reward_scene。")
		return false

	if result_scene == null:
		push_error("GameFlowController：未配置 result_scene。")
		return false

	if page_container == null or not is_instance_valid(page_container): # 所有页面都必须拥有同一个挂载位置。
		push_error("GameFlowController：未找到可用的 page_container。")
		return false

	return true # 所有流程依赖均已准备好，可以进入主菜单。


## 使用指定场景替换当前流程页面，并返回新页面的根节点。
##
## 新页面会先在内存中创建；只有创建和类型检查成功后，旧页面才会被移除。
## 这样即使传入了错误场景，也不会先破坏当前仍可用的页面。
##
## [param page_scene] 必须是以 [Control] 为根节点的页面场景。
## 替换失败时保留旧页面，并返回 [code]null[/code]。
func _replace_page(page_scene:PackedScene)->Node:
	if page_scene == null: # 空场景无法生成新的活动页面。
		push_error("GameFlowController：无法切换页面，传入的 page_scene 为空。")
		return null

	if page_container == null or not is_instance_valid(page_container): # 没有容器时不能建立页面所有权。
		push_error("GameFlowController：无法切换页面，page_container 不可用。")
		return null

	var new_page:Node = page_scene.instantiate() # 先创建新页面，避免失败时丢失旧页面。
	if new_page == null:
		push_error("GameFlowController：页面场景实例化失败。")
		return null

	if not new_page is Control: # 主菜单、地图、战斗、奖励和结算都属于全屏UI页面。
		push_error("GameFlowController：页面场景的根节点必须继承 Control。")
		new_page.free() # 节点尚未加入场景树，可以立即安全释放。
		return null

	if current_page != null and is_instance_valid(current_page):
		var old_parent:Node = current_page.get_parent() # 页面所有权异常时不应误删其他树中的节点。
		if old_parent != null and old_parent != page_container:
			push_error("GameFlowController：current_page 不属于 page_container，已取消页面切换。")
			new_page.free()
			return null

		if old_parent == page_container:
			page_container.remove_child(current_page) # 立即停止旧页面的输入与布局参与。

		current_page.queue_free() # 延迟释放旧页面，避免在其回调中切换时破坏调用栈。

	current_page = null # 同时处理旧引用已失效的情况，恢复清晰的所有权状态。
	page_container.add_child(new_page) # 加入场景树后，新页面的_ready与@onready会立即完成。
	current_page = new_page # 控制器从此只持有并管理这个活动页面。

	return current_page
