## 保存一局冒险在战斗之外持续存在的全部运行时状态。
##
## 包含玩家当前生命、本局实际拥有的卡牌定义、正在处理的地图节点、可进入节点、
## 已完成节点和整局状态。GameFlowController以后持有唯一的RunState，并通过这里的
## 方法推进冒险；地图、奖励和结算View只读取状态并报告输入。
##
## RunState不进入场景树，不保存单场战斗的能量、格挡、牌堆或CardInstance，
## 也不修改RunDefinition、MapDefinition、CardDefinition等静态Resource。
class_name RunState
extends RefCounted


## 当前整局冒险所处的运行状态。
enum RunStatus {
	## 对象尚未使用合法RunDefinition完成初始化。
	SETUP,

	## 冒险已经成功初始化，仍允许进入节点、治疗、加卡和继续流程。
	IN_PROGRESS,

	## 玩家已经击败最终Boss并取得整局胜利。
	VICTORY,

	## 玩家已经在战斗中失败，整局流程不再允许继续推进。
	DEFEAT,

	## 正在逐轮构筑初始牌组，完成后才允许进入地图。
	DRAFTING
}

## 已完成的选牌轮数，也是当前轮在DRAFT_RARITIES中的下标。
var draft_round:int = 0;


## 创建当前运行时冒险所使用的静态定义资源。
##
## 成功初始化后保存传入RunDefinition的只读引用，用于查询玩家初始最大生命、地图结构
## 和其他固定规则。运行时不得修改该资源或它引用的任何.tres内容。
var definition:RunDefinition


## 玩家在当前整局冒险中剩余的生命值。
##
## 初始化时等于角色combatant_definition.max_health；战斗结束时由GameFlowController回写，
## 休整时由RunState.heal修改。该数值不能超过玩家最大生命，也不能小于0。
var current_health:int = 0


## 本局实际最大生命；新冒险从静态定义初始化，战斗结束时同步永久变化。
var max_health:int = 0


## 玩家在当前整局冒险中实际拥有的全部卡牌定义引用。
##
## 每个数组元素代表实际拥有的一张卡，因此允许同一个CardDefinition重复出现。
## 进入战斗时再根据每个元素创建独立CardInstance；这里不保存牌堆和临时费用。
var owned_cards:Array[CardDefinition] = []


## 当前正在处理的地图节点ID。
##
## 位于地图页面、尚未进入节点或节点已经完成时为空字符串；进入节点后保存该节点
## 的稳定ID。同一时刻最多只能有一个当前节点。
var current_node_id:String = ""


## 当前已经解锁并允许玩家进入的地图节点ID。
##
## 初始化时复制MapDefinition.starting_node_ids；进入节点时移除对应ID，完成节点后
## 再根据其next_node_ids解锁后继。该数组属于运行时状态，不得与静态数组共用。
var available_node_ids:Array[String] = []


## 当前整局冒险中已经完成的地图节点ID。
##
## 完成节点后保存其稳定ID，用于阻止重复进入并刷新地图显示。初始化时必须为空，
## 且同一个ID不能重复出现。
var completed_node_ids:Array[String] = []


## 当前整局冒险的运行状态。
##
## 新对象默认为SETUP；成功初始化后变为DRAFTING，选满三轮后变为IN_PROGRESS，最终由结算方法切换为
## VICTORY或DEFEAT。
var status:RunStatus = RunStatus.SETUP


## 只在DRAFTING阶段查询；轮次由初始化和choose_starting_card推进。
func get_draft_rarity()->int:
	return RunDefinition.DRAFT_RARITIES[draft_round];


## 单轮选择直接加入真实牌组；静态卡牌合法性已由冒险定义验证。
func choose_starting_card(card:CardDefinition)->bool:
	if status != RunStatus.DRAFTING:
		return false;
	if not definition.character_definition.reward_card_pool.has(card):
		return false;
	if card.rarity != get_draft_rarity():
		return false;
	owned_cards.append(card);
	draft_round += 1;
	if draft_round == RunDefinition.DRAFT_RARITIES.size():
		status = RunStatus.IN_PROGRESS;
	return true;


## 使用一份静态冒险定义初始化全新的局内运行时状态。
##
## new_definition为空或定义非法时推送错误，保持当前RunState原有数据不变并返回false。
## 定义合法时，先在局部数组中按照DeckEntryDefinition.count展开初始牌组，并复制
## 地图起点；全部准备成功后再提交定义、满生命、牌组、地图进度和DRAFTING状态。
##
## owned_cards中的重复CardDefinition引用代表多张同名卡，属于合法状态。
## 该方法只复制数组结构和静态资源引用，不创建CardInstance，也不修改任何静态资源。
func run_state_init(new_definition:RunDefinition)->bool:
	if new_definition == null:#空引用无法提供玩家、牌组、地图和奖励配置
		push_error("冒险定义为空，局内状态初始化失败");#报告调用方缺少静态整局配置
		return false;#验证失败前不修改当前RunState中的任何数据
	if new_definition.is_invalid():#让RunDefinition完整验证玩家、牌组、地图和奖励池
		push_error("冒险定义无效，局内状态初始化失败");#补充运行时初始化阶段的错误上下文
		return false;#非法静态数据不能成为局内状态的数据来源

	var character:CharacterDefinition = new_definition.character_definition;
	var initial_owned_cards:Array[CardDefinition] = [];#局部保存展开后的实际拥有卡牌，避免产生半成品状态
	for deck_entry in character.starting_deck_entries:#按照角色基础牌组的配置顺序展开
		for _card_index in range(deck_entry.count):#count决定本局实际拥有这种卡牌的数量
			initial_owned_cards.append(deck_entry.card_definition);#每个元素代表一张卡，但共享同一份只读定义

	var initial_available_node_ids:Array[String] = (
		new_definition.map_definition.starting_node_ids.duplicate()
	);#复制静态起点数组，防止后续运行时移除节点时污染MapDefinition

	definition = new_definition;#保存静态冒险定义的只读引用
	max_health = character.combatant_definition.max_health;
	current_health = max_health;#新冒险恢复角色原始上限并从满生命开始。
	owned_cards = initial_owned_cards;#提交已经完整展开的本局实际拥有卡牌列表
	current_node_id = "";#新冒险尚未进入任何地图节点
	available_node_ids = initial_available_node_ids;#提交独立于静态地图数组的初始可进入节点列表
	completed_node_ids.clear();#全新冒险不能继承此前已经完成的节点
	draft_round = 0;
	status = RunStatus.DRAFTING;#先逐轮选牌，再开放地图。

	return true;#当前RunState已经完整初始化，可以交给GameFlowController使用


## 检查当前局内运行时状态是否包含非法或互相冲突的数据。
##
## 冒险定义为空或非法、状态枚举无效或仍为SETUP、生命越界、实际牌组为空或包含
## 非法卡牌，以及当前、可进入、已完成节点不存在、重复或同时出现在多个进度位置时，
## 推送对应错误并返回true。进行中或胜利状态下生命为0时也返回true。
## 供测试和排查问题时完整检查；日常状态操作不重复扫描静态配置。
##
## owned_cards允许重复保存同一个CardDefinition或card_id，因为每个数组元素代表
## 玩家实际拥有的一张卡。该方法只读取并验证状态，不修复数据，也不修改静态资源。
func is_invalid()->bool:
	if definition == null:#没有静态冒险定义时无法验证玩家、地图和基础规则
		push_error("冒险定义为空，局内状态非法");#报告当前RunState尚未完成初始化
		return true;#缺少唯一静态来源时不能继续验证运行时数据
	if definition.is_invalid():#运行时状态不能依赖字段不完整的玩家、地图或奖励配置
		push_error("冒险定义无效，局内状态非法");#补充局内状态层的错误上下文
		return true;#非法静态定义不能成为合法RunState的基础
	if not RunStatus.values().has(status):#防止运行时状态保存枚举范围之外的非法整数
		push_error("整局状态枚举无效，局内状态非法");#报告流程控制器无法解释的状态
		return true;#未知状态不能安全决定是否允许继续推进
	if status == RunStatus.SETUP:#成功初始化后的完整RunState不应继续停留在准备阶段
		push_error("整局状态仍为SETUP，局内状态尚未完成初始化");#报告对象仍是未提交状态
		return true;#未初始化对象不能交给页面和流程控制器使用

	if max_health <= 0:
		push_error("本局最大生命必须大于0");
		return true;
	if current_health < 0:#生命最低只能为0，不能出现负数运行时数据
		push_error("当前生命小于0，局内状态非法");#报告战斗回写或治疗计算破坏了生命下限
		return true;#负生命不能继续传入下一场战斗
	if current_health > max_health:#跨战斗生命不能超过本局实际最大生命
		push_error("当前生命超过最大生命，局内状态非法");#报告生命回写或治疗没有正确限制上限
		return true;#超出静态最大值的生命状态不能使用
	if (
		status in [RunStatus.DRAFTING, RunStatus.IN_PROGRESS, RunStatus.VICTORY]
	) and current_health == 0:#仍在冒险或已经胜利都意味着玩家必须存活
		push_error("进行中或胜利状态的玩家生命为0，局内状态非法");#报告生命与整局状态互相冲突
		return true;#死亡玩家不能继续流程，也不能取得Boss胜利

	if owned_cards.is_empty():#初始化成功的冒险必须拥有至少一张实际卡牌
		push_error("本局拥有的卡牌数组为空，局内状态非法");#报告牌组初始化或后续修改破坏了战斗入口
		return true;#空牌组不能创建下一场BattleState
	for card_index in range(owned_cards.size()):#逐一验证玩家实际拥有的全部卡牌定义引用
		var owned_card:CardDefinition = owned_cards[card_index];#取得当前位置代表的一张实际拥有卡牌
		if owned_card == null:#每个数组元素都必须指向一份真实卡牌定义
			push_error("本局拥有的卡牌[%d]为空，局内状态非法" % card_index);#报告空卡牌的准确下标
			return true;#空元素无法在战斗开始时创建CardInstance
		if owned_card.is_invalid():#卡牌名称、费用和效果等静态内容必须完整合法
			push_error("本局拥有的卡牌[%d]无效，局内状态非法" % card_index);#补充实际牌组中的位置上下文
			return true;#非法卡牌不能带入下一场战斗

	var map_definition:MapDefinition = definition.map_definition;#后续所有节点查询都读取同一份只读地图定义
	if not current_node_id.is_empty():#空字符串表示当前位于地图页面，没有正在处理的节点
		if not map_definition.has_node(current_node_id):#非空当前节点必须指向地图中的真实节点
			push_error("当前地图节点不存在：%s" % current_node_id);#报告损坏的运行时节点引用
			return true;#不存在的节点无法完成、结算或取得后继连接

	var available_node_id_set:Dictionary = {};#记录可进入节点ID，用于检查重复和进度集合冲突
	for available_index in range(available_node_ids.size()):#逐一验证当前已经解锁的节点
		var available_node_id:String = available_node_ids[available_index];#取得当前位置的可进入节点ID
		if available_node_id.is_empty():#空字符串不能代表一项真实的可进入节点
			push_error("可进入节点ID[%d]为空，局内状态非法" % available_index);#报告空ID的准确位置
			return true;#空节点不能显示为有效地图入口
		if not map_definition.has_node(available_node_id):#可进入节点必须来自当前静态地图
			push_error("可进入节点不存在：%s" % available_node_id);#报告运行时进度引用了错误地图内容
			return true;#不存在的节点不能交给GameFlowController进入
		if available_node_id_set.has(available_node_id):#同一个节点不能被重复解锁
			push_error("可进入节点ID重复：%s" % available_node_id);#报告重复的运行时进度数据
			return true;#重复入口可能导致重复创建页面或重复结算节点
		if available_node_id == current_node_id:#已经进入的节点应当从可进入数组中移除
			push_error("当前节点同时存在于可进入节点中：%s" % available_node_id);#报告两个进度位置发生冲突
			return true;#同一节点不能同时是待进入和正在处理状态

		available_node_id_set[available_node_id] = true;#记录已经完整验证的可进入节点ID

	var completed_node_id_set:Dictionary = {};#记录已完成节点ID，用于检查重复和跨集合冲突
	for completed_index in range(completed_node_ids.size()):#逐一验证当前已经完成的节点
		var completed_node_id:String = completed_node_ids[completed_index];#取得当前位置的已完成节点ID
		if completed_node_id.is_empty():#空字符串不能代表一项真实的完成记录
			push_error("已完成节点ID[%d]为空，局内状态非法" % completed_index);#报告空ID的准确位置
			return true;#空记录无法用于地图刷新或阻止重复进入
		if not map_definition.has_node(completed_node_id):#完成记录必须属于当前静态地图
			push_error("已完成节点不存在：%s" % completed_node_id);#报告运行时进度引用了错误地图内容
			return true;#不存在的节点不能成为合法完成记录
		if completed_node_id_set.has(completed_node_id):#同一个节点只能完成一次
			push_error("已完成节点ID重复：%s" % completed_node_id);#报告重复的完成记录
			return true;#重复完成会破坏地图推进和奖励结算边界
		if completed_node_id == current_node_id:#正在处理的节点尚未进入完成状态
			push_error("当前节点同时存在于已完成节点中：%s" % completed_node_id);#报告当前与完成状态冲突
			return true;#同一节点不能同时是正在处理和已经完成
		if available_node_id_set.has(completed_node_id):#完成节点不能再次处于可进入状态
			push_error("节点同时存在于可进入和已完成数组中：%s" % completed_node_id);#报告两个进度集合冲突
			return true;#已完成节点重新解锁会允许玩家重复获取节点收益

		completed_node_id_set[completed_node_id] = true;#记录已经完整验证的完成节点ID

	return false;#静态定义、状态、生命、牌组和地图进度均合法


## 判断当前时刻是否允许进入指定地图节点。
##
## 只有RunState已经绑定定义、整局处于IN_PROGRESS、没有其他正在处理的节点、
## node_id非空且存在于当前地图、位于available_node_ids中，并且尚未完成时返回true。
## 任意条件不满足时返回false。
##
## 该方法是供MapView刷新按钮状态使用的纯查询，不推送错误、不移动节点ID，
## 也不修改任何静态资源。enter_node仍会在真正提交前再次进行最终检查。
func can_enter_node(node_id:String)->bool:
	if definition == null:#尚未初始化时无法取得当前地图和节点进度
		return false;#缺少判断依据时所有地图节点都不可进入
	if status != RunStatus.IN_PROGRESS:#胜利、失败或准备阶段都不允许继续推进地图
		return false;#终局状态下地图按钮应当保持不可操作
	if not current_node_id.is_empty():#同一时刻最多只能处理一个地图节点
		return false;#已有当前节点时不能并行进入另一节点
	if node_id.is_empty():#空字符串不能指向一项真实地图节点
		return false;#无效查询不应成为可进入请求
	if definition.map_definition == null:#保留防御性检查，避免读取损坏定义中的空地图
		return false;#没有地图时无法判断节点是否存在
	if not definition.map_definition.has_node(node_id):#只能进入当前静态地图实际包含的节点
		return false;#不存在的节点ID不能交给流程控制器处理
	if completed_node_ids.has(node_id):#已经完成的节点不能再次提供战斗、治疗或奖励
		return false;#阻止玩家重复取得同一节点收益

	return available_node_ids.has(node_id);#最后以运行时解锁列表作为是否允许进入的直接依据


## 进入当前可用节点；移除入口后，同一节点不能被重复进入。
func enter_node(node_id:String)->bool:
	if not can_enter_node(node_id):
		return false;
	available_node_ids.erase(node_id);
	current_node_id = node_id;
	return true;


## 完成当前节点并解锁后继；地图连接已在冒险初始化时验证。
func complete_current_node()->bool:
	if status != RunStatus.IN_PROGRESS or current_node_id.is_empty():
		return false;
	var current_node:MapNodeDefinition = definition.map_definition.get_node_by_id(current_node_id);
	completed_node_ids.append(current_node_id);
	for next_node_id in current_node.next_node_ids:
		if not completed_node_ids.has(next_node_id) and not available_node_ids.has(next_node_id):
			available_node_ids.append(next_node_id);
	current_node_id = "";
	return true;


## 在冒险进行期间加入一张卡；只验证新加入的定义，不重查整局配置。
func add_card(card_definition:CardDefinition)->bool:
	if status != RunStatus.IN_PROGRESS:
		return false;
	if card_definition == null or card_definition.is_invalid():
		push_error("需要添加的卡牌定义无效");
		return false;
	owned_cards.append(card_definition);
	return true;


## 恢复局内生命，返回实际治疗量；不能超过本局实际最大生命。
func heal(amount:int)->int:
	if status != RunStatus.IN_PROGRESS or amount <= 0:
		return 0;
	var actual_heal_amount:int = mini(amount, max_health - current_health);
	current_health += actual_heal_amount;
	return actual_heal_amount;


## 玩家存活且已完成 Boss 后，结束本局冒险。
func mark_victory()->bool:
	if status != RunStatus.IN_PROGRESS or current_health <= 0 or not current_node_id.is_empty():
		return false;
	for completed_node_id in completed_node_ids:
		var completed_node:MapNodeDefinition = definition.map_definition.get_node_by_id(completed_node_id);
		if completed_node.node_type == MapNodeDefinition.NodeType.BOSS:
			status = RunStatus.VICTORY;
			return true;
	return false;


## 标记本局失败，保留失败节点和牌组供结算读取。
func mark_defeat()->bool:
	if status != RunStatus.IN_PROGRESS:
		return false;
	status = RunStatus.DEFEAT;
	return true;
