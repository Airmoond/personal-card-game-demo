## 一局冒险的静态定义资源。
##
## 保存冒险的稳定ID、玩家定义、初始牌组条目、地图定义、卡牌奖励池、每轮
## 展示数量和连续选择次数。GameFlowController以后读取一份RunDefinition创建新的
## RunState，使同一套流程可以加载不同玩家、地图、牌组和奖励配置。
##
## 该资源在运行时必须视为只读数据。当前生命、实际拥有的卡牌、地图进度和
## 整局胜负等变化必须保存在RunState中，不能写回RunDefinition或其引用的资源。
class_name RunDefinition
extends Resource


## 程序内部使用的稳定唯一冒险ID，例如default_run。
##
## 该字段用于识别一份整局配置，不应随着显示名称或语言变化而改变，且不能为空。
@export var run_id:String


## 本局冒险使用的玩家静态定义。
##
## 用于提供玩家ID、显示名称、最大生命和原画。RunState初始化时从这里取得
## 最大生命，但之后的当前生命只能保存在RunState中。
@export var player_definition:CombatantDefinition


## 本局冒险的静态初始牌组条目。
##
## 每个DeckEntryDefinition使用“卡牌定义+数量”紧凑描述一种起始卡牌。
## RunState初始化时会按照count将其展开为实际拥有的CardDefinition引用列表。
@export var starting_deck_entries:Array[DeckEntryDefinition] = []


## 本局冒险使用的静态地图定义。
##
## 用于提供全部节点、起点和连接关系；节点是否可进入或已经完成由RunState保存。
@export var map_definition:MapDefinition


## 普通战斗胜利后可以抽取的静态卡牌奖励池。
##
## 每个元素都是一份只读CardDefinition引用，card_id必须互不重复。
## 奖励卡可以与初始牌组中的卡牌同名，因为获得奖励代表再拥有一张该卡牌。
@export var reward_pool:Array[CardDefinition] = []


## 每次卡牌奖励页面需要随机展示的不同卡牌数量。
##
## 该数值必须大于0，并且不能超过reward_pool中的卡牌数量。
@export var reward_option_count:int = 3


## 普通战斗胜利后连续进行的卡牌奖励选择次数。
##
## 每次选择都会重新从reward_pool中抽取reward_option_count张候选；不同轮次
## 允许再次出现同一张卡。该数值必须大于0。
@export var reward_selection_count:int = 3


## 检查当前整局冒险定义是否包含非法静态数据。
##
## 冒险ID为空，玩家、地图、初始牌组或奖励池缺失或非法，初始牌组重复配置
## 同一个card_id，奖励池包含重复card_id，或者奖励展示与选择次数不合法时，
## 推送对应错误并返回true。所有字段均满足第三阶段规则时返回false。
##
## 该方法只验证静态资源，不修复数组、不展开实际牌组，也不创建或修改RunState。
func is_invalid()->bool:
	if run_id.is_empty():#每份整局配置都必须拥有稳定且非空的内部ID
		push_error("Invalid run_id! 冒险定义ID为空");#报告无法识别当前整局配置
		return true;#缺少身份的定义不能用于创建RunState
	if player_definition == null:#没有玩家定义就无法确定玩家身份和最大生命
		push_error("Invalid player_definition! 冒险的玩家定义为空");#报告缺少玩家静态数据
		return true;#不创建缺少玩家的局内状态
	if player_definition.is_invalid():#玩家定义中的ID、名称、生命和原画必须完整合法
		push_error("Invalid player_definition! 冒险的玩家定义无效");#补充整局配置层的错误上下文
		return true;#非法玩家资源不能成为RunState的数据来源
	if starting_deck_entries.is_empty():#新冒险必须至少拥有一种起始卡牌
		push_error("Invalid starting_deck_entries! 冒险的初始牌组为空");#报告无法建立局内牌组
		return true;#空牌组不能进入当前阶段的战斗流程

	var configured_starting_card_ids:Dictionary = {};#记录已配置的起始卡牌ID，防止重复条目
	for entry_index in range(starting_deck_entries.size()):#按照资源数组顺序验证全部牌组条目
		var deck_entry:DeckEntryDefinition = starting_deck_entries[entry_index];#取得当前位置的静态牌组条目
		if deck_entry == null:#牌组数组中不能存在没有实际资源的空位置
			push_error("Invalid deck entry! 初始牌组条目[%d]为空" % entry_index);#报告空条目的准确下标
			return true;#空条目无法展开为任何CardDefinition引用
		if deck_entry.is_invalid():#复用条目自身的卡牌定义和数量检查
			push_error("Invalid deck entry! 初始牌组条目[%d]无效" % entry_index);#补充整局牌组中的位置上下文
			return true;#任意条目非法时整份冒险定义都不能使用

		var starting_card_id:String = deck_entry.card_definition.card_id;#合法条目可以安全提供稳定卡牌ID
		if configured_starting_card_ids.has(starting_card_id):#同一种起始卡应通过一个条目的count配置数量
			push_error("Invalid deck entry! 初始牌组重复配置card_id：%s" % starting_card_id);#报告重复卡牌ID
			return true;#重复来源会让实际开局数量难以维护
		configured_starting_card_ids[starting_card_id] = true;#记录已经完整验证的起始卡牌ID

	if map_definition == null:#没有地图就无法确定冒险起点、节点内容和终点
		push_error("Invalid map_definition! 冒险的地图定义为空");#报告缺少整局路线配置
		return true;#无地图配置不能创建可推进的RunState
	if map_definition.is_invalid():#地图的节点、连接、起点和可达性必须全部合法
		push_error("Invalid map_definition! 冒险的地图定义无效");#补充整局配置层的错误上下文
		return true;#非法地图不能交给局内流程使用
	if reward_pool.is_empty():#普通战斗胜利后必须有可展示的卡牌奖励来源
		push_error("Invalid reward_pool! 冒险的卡牌奖励池为空");#报告缺少构筑成长内容
		return true;#空奖励池无法满足第三阶段三选一流程

	var configured_reward_card_ids:Dictionary = {};#记录奖励卡牌ID，保证无放回抽取拥有唯一候选
	for reward_index in range(reward_pool.size()):#逐一验证奖励池中的全部卡牌定义
		var reward_card:CardDefinition = reward_pool[reward_index];#取得当前位置的静态奖励卡资源
		if reward_card == null:#奖励池中不能存在没有实际资源的空位置
			push_error("Invalid reward card! 奖励池卡牌[%d]为空" % reward_index);#报告空奖励的准确下标
			return true;#空卡牌无法显示或加入RunState牌组
		if reward_card.is_invalid():#奖励卡的ID、名称、费用和效果必须完整合法
			push_error("Invalid reward card! 奖励池卡牌[%d]无效" % reward_index);#补充奖励池中的位置上下文
			return true;#非法卡牌不能成为玩家奖励
		if configured_reward_card_ids.has(reward_card.card_id):#同一个稳定卡牌ID在奖励池中只能出现一次
			push_error("Invalid reward card! 奖励池重复配置card_id：%s" % reward_card.card_id);#报告重复奖励来源
			return true;#重复候选会破坏一次奖励展示互不相同的约定

		configured_reward_card_ids[reward_card.card_id] = true;#记录已经完整验证的奖励卡牌ID

	if reward_option_count <= 0:#奖励页面至少需要展示一个可选择项目
		push_error("Invalid reward_option_count! 奖励展示数量必须大于0");#报告非正数奖励规则
		return true;#没有可展示选项时无法完成奖励流程
	if reward_option_count > reward_pool.size():#无放回抽取不能请求超过奖励池容量的不同卡牌
		push_error("Invalid reward_option_count! 奖励展示数量不能超过奖励池大小");#报告互相冲突的奖励配置
		return true;#无法满足的展示数量不能交给流程控制器抽取
	if reward_selection_count <= 0:#普通战斗胜利后至少需要完成一次奖励选择
		push_error("Invalid reward_selection_count! 奖励选择次数必须大于0");#报告无法推进的奖励流程配置
		return true;#非正数次数无法形成有效的奖励阶段

	return false;#玩家、牌组、地图和奖励规则均合法，当前定义可以创建RunState
