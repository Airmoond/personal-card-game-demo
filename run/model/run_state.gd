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
	DEFEAT
}


## 创建当前运行时冒险所使用的静态定义资源。
##
## 成功初始化后保存传入RunDefinition的只读引用，用于查询玩家最大生命、地图结构
## 和其他固定规则。运行时不得修改该资源或它引用的任何.tres内容。
var definition:RunDefinition


## 玩家在当前整局冒险中剩余的生命值。
##
## 初始化时等于player_definition.max_health；战斗结束时由GameFlowController回写，
## 休整时由RunState.heal修改。该数值不能超过玩家最大生命，也不能小于0。
var current_health:int = 0


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
## 新对象默认为SETUP；成功初始化后变为IN_PROGRESS，最终由结算方法切换为
## VICTORY或DEFEAT。
var status:RunStatus = RunStatus.SETUP


## 使用一份静态冒险定义初始化全新的局内运行时状态。
##
## new_definition为空或定义非法时推送错误，保持当前RunState原有数据不变并返回false。
## 定义合法时，先在局部数组中按照DeckEntryDefinition.count展开初始牌组，并复制
## 地图起点；全部准备成功后再提交定义、满生命、牌组、地图进度和IN_PROGRESS状态。
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

	var initial_owned_cards:Array[CardDefinition] = [];#局部保存展开后的实际拥有卡牌，避免产生半成品状态
	for deck_entry in new_definition.starting_deck_entries:#按照静态牌组条目的配置顺序展开初始牌组
		for _card_index in range(deck_entry.count):#count决定本局实际拥有这种卡牌的数量
			initial_owned_cards.append(deck_entry.card_definition);#每个元素代表一张卡，但共享同一份只读定义

	if initial_owned_cards.is_empty():#合法定义正常不会触发，保留防御性检查避免提交空牌组
		push_error("初始牌组展开结果为空，局内状态初始化失败");#报告无法建立实际拥有卡牌列表
		return false;#局部构建失败时保持当前RunState原有数据不变

	var initial_available_node_ids:Array[String] = (
		new_definition.map_definition.starting_node_ids.duplicate()
	);#复制静态起点数组，防止后续运行时移除节点时污染MapDefinition
	if initial_available_node_ids.is_empty():#合法地图正常至少拥有一个起点
		push_error("地图起点复制结果为空，局内状态初始化失败");#报告无法建立初始可进入节点
		return false;#未准备好完整地图进度前不提交任何新状态

	definition = new_definition;#保存静态冒险定义的只读引用
	current_health = new_definition.player_definition.max_health;#新冒险从玩家定义的满生命开始
	owned_cards = initial_owned_cards;#提交已经完整展开的本局实际拥有卡牌列表
	current_node_id = "";#新冒险尚未进入任何地图节点
	available_node_ids = initial_available_node_ids;#提交独立于静态地图数组的初始可进入节点列表
	completed_node_ids.clear();#全新冒险不能继承此前已经完成的节点
	status = RunStatus.IN_PROGRESS;#全部运行时数据建立完成后，最后允许流程正式推进

	return true;#当前RunState已经完整初始化，可以交给GameFlowController使用


## 检查当前局内运行时状态是否包含非法或互相冲突的数据。
##
## 冒险定义为空或非法、状态枚举无效或仍为SETUP、生命越界、实际牌组为空或包含
## 非法卡牌，以及当前、可进入、已完成节点不存在、重复或同时出现在多个进度位置时，
## 推送对应错误并返回true。进行中或胜利状态下生命为0时也返回true。
## 所有数据满足第三阶段局内规则时返回false。
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

	var max_health:int = definition.player_definition.max_health;#最大生命始终读取只读玩家定义
	if current_health < 0:#生命最低只能为0，不能出现负数运行时数据
		push_error("当前生命小于0，局内状态非法");#报告战斗回写或治疗计算破坏了生命下限
		return true;#负生命不能继续传入下一场战斗
	if current_health > max_health:#跨战斗生命不能超过玩家定义中的基础最大生命
		push_error("当前生命超过最大生命，局内状态非法");#报告生命回写或治疗没有正确限制上限
		return true;#超出静态最大值的生命状态不能使用
	if (
		status == RunStatus.IN_PROGRESS or status == RunStatus.VICTORY
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


## 尝试将一个可进入地图节点设为当前正在处理的节点。
##
## 当前RunState非法或can_enter_node返回false时保持所有节点进度不变并返回false。
## 节点合法且可进入时，从available_node_ids中移除该ID，再保存到current_node_id，
## 然后返回true。移除后可防止同一节点在战斗或休整期间被重复进入。
##
## 该方法只提交“开始处理节点”的运行时状态，不启动战斗、不治疗、不完成节点，
## 也不修改MapNodeDefinition或MapDefinition；后续流程由GameFlowController编排。
func enter_node(node_id:String)->bool:
	if is_invalid():#任何局内数据损坏时都不能继续提交新的地图进度
		push_error("当前局内状态无效，无法进入地图节点");#补充节点进入阶段的错误上下文
		return false;#完整验证失败前保持节点数组和当前节点不变
	if not can_enter_node(node_id):#再次验证状态、当前节点、地图归属、完成记录和解锁状态
		return false;#锁定、完成、不存在或当前不可进入都属于安全拒绝

	var available_index:int = available_node_ids.find(node_id);#取得目标在可进入数组中的准确位置
	if available_index < 0:#can_enter_node正常通过时不应发生，保留防御性检查
		push_error("可进入节点数组中找不到目标节点，进入失败");#报告查询结果与数组状态不一致
		return false;#未找到目标时不能误删其他节点或设置当前节点

	available_node_ids.remove_at(available_index);#进入后立即移除解锁入口，防止重复点击同一节点
	current_node_id = node_id;#保存唯一当前节点，供战斗、休整和完成流程共同读取

	return true;#节点进度已经从“可进入”成功切换为“正在处理”


## 尝试完成当前正在处理的地图节点，并解锁它的合法后继节点。
##
## 当前RunState非法、整局不处于IN_PROGRESS、没有当前节点或无法取得对应静态节点时，
## 保持全部地图进度不变并返回false。验证通过后，先在局部数组中记录当前节点并
## 加入尚未完成、尚未解锁的后继ID，全部准备完成后再提交数组并清空current_node_id。
##
## 该方法只完成地图进度的“正在处理→已完成”转换，不发放卡牌、不恢复生命，
## 也不根据BOSS类型标记整局胜利。调用时机和后续页面由GameFlowController决定。
func complete_current_node()->bool:
	if is_invalid():#任何局内数据损坏时都不能继续提交节点完成结果
		push_error("当前局内状态无效，无法完成地图节点");#补充节点完成阶段的错误上下文
		return false;#完整验证失败时保持三个地图进度字段不变
	if status != RunStatus.IN_PROGRESS:#胜利或失败后不能再次完成节点并解锁路线
		return false;#终局状态下安全拒绝重复结算请求
	if current_node_id.is_empty():#空字符串表示当前没有正在处理的节点
		return false;#没有目标时不能产生完成记录或解锁后继

	var current_node:MapNodeDefinition = (
		definition.map_definition.get_node_by_id(current_node_id)
	);#通过静态地图的统一查询入口取得当前节点内容
	if current_node == null:#is_invalid正常通过时不应发生，保留防御性检查
		push_error("找不到当前地图节点，节点完成失败");#报告运行时ID与静态地图不一致
		return false;#缺少节点时无法安全读取后继连接

	var next_available_node_ids:Array[String] = available_node_ids.duplicate();#在局部副本中准备新的解锁列表
	var next_completed_node_ids:Array[String] = completed_node_ids.duplicate();#在局部副本中准备新的完成记录
	next_completed_node_ids.append(current_node_id);#当前节点通过结算后只记录一次完成状态

	for next_node_id in current_node.next_node_ids:#按照静态地图配置顺序处理全部后继连接
		if next_completed_node_ids.has(next_node_id):#已经完成的节点不能被重新解锁
			continue;#汇合路线可能再次指向旧节点，直接保留原完成状态
		if next_available_node_ids.has(next_node_id):#多个前置节点可能解锁同一个后继节点
			continue;#已经解锁时不重复追加相同ID
		if not definition.map_definition.has_node(next_node_id):#合法地图正常不会触发，保留提交前防御检查
			push_error("后继地图节点不存在，节点完成失败：%s" % next_node_id);#报告损坏的静态连接目标
			return false;#局部数组尚未提交，失败不会留下部分解锁结果

		next_available_node_ids.append(next_node_id);#保存首次解锁且尚未完成的合法后继节点

	available_node_ids = next_available_node_ids;#提交完整计算后的可进入节点数组
	completed_node_ids = next_completed_node_ids;#提交包含当前节点的新完成记录
	current_node_id = "";#当前节点处理结束，返回地图页面后可以进入下一节点

	return true;#地图进度已经成功从当前节点推进到其后继节点


## 尝试让玩家在当前冒险中实际拥有一张新的卡牌。
##
## 当前RunState非法、整局不处于IN_PROGRESS、card_definition为空或卡牌定义非法时，
## 保持owned_cards不变并返回false。全部检查通过时，将传入的只读CardDefinition
## 引用追加一次并返回true。
##
## 该方法允许同一个CardDefinition或card_id重复出现，因为每次追加都代表玩家
## 额外获得了一张同名卡。它不创建CardInstance、不修改卡牌资源，也不要求卡牌
## 必须来自reward_pool；奖励候选是否合法由GameFlowController在调用前负责确认。
func add_card(card_definition:CardDefinition)->bool:
	if is_invalid():#损坏的生命、牌组或地图进度不能继续接受新的运行时变化
		push_error("当前局内状态无效，无法添加卡牌");#补充卡牌成长阶段的错误上下文
		return false;#完整验证失败时保持owned_cards原有内容不变
	if status != RunStatus.IN_PROGRESS:#胜利或失败后不能继续改变本局牌组
		return false;#终局状态下安全拒绝奖励或其他加卡请求
	if card_definition == null:#空引用无法提供卡牌身份、费用和效果
		push_error("需要添加的卡牌定义为空");#报告调用方没有传入实际卡牌资源
		return false;#空卡牌不能进入玩家实际拥有的牌组
	if card_definition.is_invalid():#新卡的ID、名称、费用和效果必须完整合法
		push_error("需要添加的卡牌定义无效");#报告无法安全带入后续战斗的静态数据
		return false;#非法卡牌不能破坏当前已经合法的owned_cards

	owned_cards.append(card_definition);#只追加一份只读资源引用，代表实际获得一张新卡
	return true;#本局牌组已经成功增加一个CardDefinition元素


## 尝试为玩家恢复指定数量的局内当前生命，并返回实际恢复量。
##
## 当前RunState非法、整局不处于IN_PROGRESS或amount小于等于0时，保持生命不变
## 并返回0。参数合法时，实际恢复量取amount与“最大生命减当前生命”中的较小值，
## 因此治疗不会让current_health超过玩家定义中的最大生命。
##
## 该方法只执行通用局内治疗规则，不检查当前节点是否为REST，也不读取或修改
## MapNodeDefinition.heal_amount；治疗时机和传入数值由GameFlowController负责决定。
func heal(amount:int)->int:
	if is_invalid():#损坏的生命、牌组或地图进度不能继续接受治疗变化
		push_error("当前局内状态无效，无法恢复生命");#补充局内治疗阶段的错误上下文
		return 0;#完整验证失败时保持current_health原值不变
	if status != RunStatus.IN_PROGRESS:#胜利或失败后不再处理普通局内治疗
		return 0;#终局状态下安全拒绝治疗请求
	if amount <= 0:#治疗请求必须提供正数基础恢复量
		push_error("治疗量必须大于0");#报告调用方传入零或负数治疗配置
		return 0;#非法数值不能改变玩家生命

	var max_health:int = definition.player_definition.max_health;#最大生命始终读取只读玩家定义
	var missing_health:int = max_health - current_health;#计算当前距离满生命还缺少多少点
	if missing_health <= 0:#玩家已经满生命时不存在可以实际恢复的空间
		return 0;#不修改生命，并明确报告本次实际恢复量为0

	var actual_heal_amount:int = min(amount,missing_health);#治疗量受到剩余生命缺口限制
	current_health += actual_heal_amount;#只提交已经限制在最大生命以内的实际恢复量

	return actual_heal_amount;#调用方可以使用返回值显示“实际恢复了多少生命”


## 尝试将当前整局冒险标记为胜利状态。
##
## 只有整局仍处于IN_PROGRESS、当前没有尚未完成的节点，并且completed_node_ids中
## 至少包含一个已经完成的BOSS节点时，才尝试切换为VICTORY。候选胜利状态通过
## is_invalid完整验证后返回true；验证失败时恢复原状态并返回false。
##
## 该方法只改变status，不完成节点、不增加卡牌、不修改生命，也不清空地图进度。
## GameFlowController应当先回写战斗生命并完成Boss节点，再调用本方法。
func mark_victory()->bool:
	if status != RunStatus.IN_PROGRESS:#胜利只能从仍在进行的冒险状态产生
		return false;#SETUP、VICTORY或DEFEAT都不能重复或反向切换状态
	if definition == null or definition.map_definition == null:#缺少静态定义时无法确认Boss完成记录
		push_error("冒险或地图定义为空，无法标记胜利");#报告终局判断缺少唯一静态来源
		return false;#定义不完整时保持IN_PROGRESS不变
	if not current_node_id.is_empty():#胜利前必须先完成当前Boss节点并清空当前节点
		push_error("当前地图节点尚未完成，无法标记胜利");#报告流程控制器调用顺序错误
		return false;#正在处理节点时不能提前进入胜利结算

	var has_completed_boss:bool = false;#记录完成列表中是否存在可以结束冒险的Boss节点
	for completed_node_id in completed_node_ids:#逐一检查当前已经完成的静态地图节点
		var completed_node:MapNodeDefinition = (
			definition.map_definition.get_node_by_id(completed_node_id)
		);#通过地图统一查询入口取得完成记录对应的节点定义
		if completed_node == null:#损坏的完成ID不能作为可信胜利依据
			push_error("已完成节点不存在，无法标记胜利：%s" % completed_node_id);#报告错误完成记录
			return false;#保持原状态，避免非法进度进入胜利结算
		if completed_node.node_type == MapNodeDefinition.NodeType.BOSS:#完成Boss代表达到本阶段整局终点
			has_completed_boss = true;#记录已经找到合法Boss完成证据
			break;#一个已完成Boss已经足以满足当前胜利规则

	if not has_completed_boss:#普通战斗或休整完成记录不能产生整局胜利
		push_error("尚未完成任何Boss节点，无法标记胜利");#报告缺少终局节点完成证据
		return false;#不允许流程控制器在Boss之前提前结算

	var previous_status:RunStatus = status;#保存原状态，候选终局状态验证失败时用于完整回滚
	status = RunStatus.VICTORY;#暂存候选胜利状态，让is_invalid验证状态与生命等数据是否一致
	if is_invalid():#胜利状态要求玩家存活，并且其余牌组和地图进度仍然完整合法
		status = previous_status;#候选状态非法时恢复调用前的IN_PROGRESS
		push_error("候选胜利状态验证失败，无法标记整局胜利");#补充终局提交阶段的错误上下文
		return false;#回滚完成后报告状态切换失败

	return true;#候选状态已经通过完整验证，当前冒险正式进入VICTORY


## 尝试将当前整局冒险标记为失败状态。
##
## 只有整局仍处于IN_PROGRESS时才尝试切换为DEFEAT。方法先暂存候选失败状态，
## 再调用is_invalid验证定义、生命范围、牌组和地图进度；验证失败时恢复原状态。
## 成功时返回true，重复失败、胜利后失败或未初始化状态均返回false。
##
## DEFEAT允许current_health为0，也允许保留current_node_id，用于记录玩家在哪个节点
## 失败。该方法只改变status，不完成失败节点，也不清空牌组、生命或地图进度。
func mark_defeat()->bool:
	if status != RunStatus.IN_PROGRESS:#失败只能从仍在进行的冒险状态产生
		return false;#SETUP、VICTORY或DEFEAT都不能重复或反向切换状态

	var previous_status:RunStatus = status;#保存原状态，候选失败状态验证失败时用于回滚
	status = RunStatus.DEFEAT;#先暂存候选状态，使0生命能够按照合法终局数据接受验证
	if is_invalid():#失败状态仍然要求定义、生命范围、牌组和地图进度完整合法
		status = previous_status;#候选状态非法时恢复调用前的IN_PROGRESS
		push_error("候选失败状态验证失败，无法标记整局失败");#补充终局提交阶段的错误上下文
		return false;#回滚完成后报告状态切换失败

	return true;#候选状态已经通过完整验证，当前冒险正式进入DEFEAT
