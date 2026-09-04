## 一项固定地图节点的静态定义资源。
##
## 保存节点的稳定ID、显示名称、节点类型、地图位置、后继节点ID，以及该节点
## 使用的遭遇或治疗数值。MapDefinition会组合多个MapNodeDefinition，形成整张
## 地图的连接关系；GameFlowController以后根据节点类型决定进入战斗还是执行休整。
##
## 该资源在运行时必须视为只读数据。节点是否锁定、可进入或已经完成等变化
## 应保存在RunState中，不能写回MapNodeDefinition或对应的.tres资源。
class_name MapNodeDefinition
extends Resource


## 地图节点支持的基础类型。
enum NodeType {
	## 普通战斗节点，进入后启动encounter_definition指定的遭遇。
	BATTLE,

	## 休整节点，进入后按照heal_amount恢复玩家生命。
	REST,

	## Boss战斗节点，进入后启动遭遇，胜利时可以结束整局冒险。
	BOSS
}


## 程序内部使用的稳定唯一节点ID，例如goblin_battle。
##
## MapDefinition使用该字段查找节点和验证连接，不应随着显示名称或语言变化而改变。
@export var node_id:String


## 显示给玩家的地图节点名称，例如“哥布林营地”。
##
## 该字段只负责显示，不作为程序查找节点或记录地图进度的依据。
@export var display_name:String


## 当前节点的基础类型，决定流程控制器应当启动战斗、执行休整还是处理Boss结算。
@export var node_type:NodeType


## 当前节点在地图界面中的静态显示坐标。
##
## MapView以后使用该坐标布置节点；它不表示玩家位置，也不保存地图进度。
@export var map_position:Vector2


## 完成当前节点后可以解锁的后继节点ID。
##
## 数组只保存稳定ID，不直接保存节点资源引用。目标是否存在、自连接和整图可达性
## 由MapDefinition统一验证。
@export var next_node_ids:Array[String] = []


## 普通战斗或Boss节点使用的静态遭遇定义。
##
## BATTLE和BOSS节点必须提供合法遭遇；REST节点不会读取该字段。
## 该资源在运行时必须视为只读，当前生命、牌堆和回合不能写入其中。
@export var encounter_definition:EncounterDefinition


## 休整节点尝试为玩家恢复的基础生命值。
##
## REST节点必须配置正数；实际恢复量和最大生命限制以后由RunState处理。
## BATTLE和BOSS节点不会读取该字段。
@export var heal_amount:int = 0


## 判断当前节点类型是否需要一份遭遇定义。
##
## BATTLE或BOSS节点返回true，REST及未知类型返回false。
## 该方法只查询节点类型，不验证遭遇内容，也不启动战斗。
func requires_encounter()->bool:
	return node_type == NodeType.BATTLE or node_type == NodeType.BOSS;#只有两种战斗节点需要EncounterDefinition


## 检查当前地图节点定义是否包含非法的局部静态数据。
##
## 节点ID或显示名称为空、节点类型不属于NodeType、后继ID中存在空字符串、
## 战斗节点缺少合法遭遇，或者休整节点的治疗量不是正数时，推送对应错误并返回true。
## 所有局部字段均满足第三阶段规则时返回false。
##
## 该方法只验证当前节点本身，不检查后继节点是否存在、自连接、整图是否包含Boss
## 或节点是否能够从起点到达；这些跨节点关系由MapDefinition统一验证。
func is_invalid()->bool:
	if node_id.is_empty():#每个节点都必须拥有可用于查找和保存进度的稳定ID
		push_error("Invalid node_id! 地图节点ID为空");#报告无法识别当前节点的静态配置错误
		return true;#缺少节点身份时不能继续参与地图验证
	if display_name.is_empty():#地图界面必须拥有可以显示给玩家的节点名称
		push_error("Invalid display_name! 地图节点显示名称为空");#报告缺少显示信息
		return true;#无显示名称的节点不满足本阶段内容要求
	if not NodeType.values().has(node_type):#防止资源中出现枚举范围之外的非法整数
		push_error("Invalid node_type! 地图节点类型无效");#报告流程控制器无法解释的节点类型
		return true;#未知类型不能安全决定战斗或休整流程

	for next_node_index in range(next_node_ids.size()):#逐一检查当前节点声明的全部后继ID
		if next_node_ids[next_node_index].is_empty():#空ID无法在MapDefinition中找到实际目标节点
			push_error("Invalid next_node_id! 后继节点ID[%d]为空" % next_node_index);#报告空连接的准确位置
			return true;#无效连接不能进入整张地图的关系验证

	if requires_encounter():#普通战斗和Boss节点需要读取遭遇资源启动单场战斗
		if encounter_definition == null:#缺少遭遇时无法确定敌人和单场战斗规则
			push_error("Invalid encounter_definition! 战斗节点的遭遇定义为空");#报告战斗内容配置缺失
			return true;#没有遭遇的战斗节点不能进入地图
		if encounter_definition.is_invalid():#节点不能引用字段不完整的静态遭遇资源
			push_error("Invalid encounter_definition! 战斗节点的遭遇定义无效");#补充地图节点层的错误上下文
			return true;#非法遭遇不能交给BattleController启动
	elif node_type == NodeType.REST:#休整节点不需要遭遇，只需要合法的基础治疗量
		if heal_amount <= 0:#零或负数无法表达本阶段有效的休整收益
			push_error("Invalid heal_amount! 休整节点的治疗量必须大于0");#报告休整内容配置错误
			return true;#非法治疗量不能交给RunState结算

	return false;#全部局部静态字段均合法，当前节点可以加入MapDefinition
