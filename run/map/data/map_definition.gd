## 一张固定地图的静态定义资源。
##
## 保存地图的稳定ID、全部节点定义和新冒险开始时允许进入的节点ID。
## MapNodeDefinition描述单个节点自身，MapDefinition负责验证节点ID、起点、
## 连接目标和整张地图的可达性，并为其他模块提供统一的节点查询入口。
##
## 该资源在运行时必须视为只读数据。当前节点、可进入节点和已完成节点等
## 冒险进度应保存在RunState中，不能写回MapDefinition或其中的节点资源。
class_name MapDefinition
extends Resource


## 程序内部使用的稳定唯一地图ID，例如first_map。
##
## 该字段用于识别地图，不应随着显示名称或语言变化而改变，且不能为空。
@export var map_id:String


## 当前地图包含的全部静态节点定义。
##
## 每个元素都必须存在并且合法，所有node_id必须唯一。数组只描述地图内容，
## 不表示节点当前是否锁定、可进入或已经完成。
@export var nodes:Array[MapNodeDefinition] = []


## 新冒险开始时允许进入的地图节点ID。
##
## 首张线性地图只配置一个起点；使用数组可以为未来的多起点地图保留表达能力。
## 每个ID都必须非空、互不重复，并且能够在nodes中找到对应节点。
@export var starting_node_ids:Array[String] = []


## 根据稳定节点ID查找当前地图中的节点定义。
##
## node_id为空、数组中没有对应节点，或者对应位置为null时返回null。
## 找到第一项ID相同且非空的MapNodeDefinition时立即返回该资源引用。
## 该方法只读取地图数据，不验证整张地图，也不修改任何静态资源或运行时进度。
func get_node_by_id(node_id:String)->MapNodeDefinition:
	if node_id.is_empty():#空ID不可能对应一项合法地图节点
		return null;#查询方法不推送配置错误，把未找到统一表达为null

	for node_definition in nodes:#按照资源数组顺序查找目标节点
		if node_definition == null:#允许查询方法在地图尚未完整配置时安全跳过空位置
			continue;#空元素没有可以比较的node_id
		if node_definition.node_id == node_id:#稳定ID一致时已经找到目标节点
			return node_definition;#返回原静态资源引用，不创建或复制节点定义

	return null;#遍历结束仍未找到时统一返回null


## 判断当前地图是否包含指定稳定ID的节点。
##
## get_node_by_id能够取得节点时返回true；ID为空或节点不存在时返回false。
## 该方法只提供便捷查询，不修改地图资源，也不代表节点当前可以进入。
func has_node(node_id:String)->bool:
	return get_node_by_id(node_id) != null;#复用唯一查询入口，避免维护另一套查找规则


## 检查当前地图定义是否包含非法静态数据或连接关系。
##
## 第一阶段验证地图ID、节点数组、每个节点自身、节点ID唯一性和Boss数量；
## 第二阶段再验证起点、连接目标、自连接以及所有节点能否从起点到达。
## 任意检查失败时推送对应错误并返回true，全部满足第三阶段规则时返回false。
##
## 该方法只读取和验证静态资源，不修复连接、不改变数组，也不创建RunState。
func is_invalid()->bool:
	if map_id.is_empty():#每张地图都必须拥有稳定且非空的内部ID
		push_error("Invalid map_id! 地图ID为空");#报告无法识别当前地图的配置错误
		return true;#缺少地图身份时不能继续建立局内状态
	if nodes.is_empty():#地图至少需要包含一个可以进入的节点
		push_error("Invalid nodes! 地图节点数组为空");#报告缺少地图内容
		return true;#没有节点时无法继续验证起点和连接

	var configured_node_ids:Dictionary = {};#记录已经出现的节点ID，同时供连接验证查询
	var boss_node_count:int = 0;#统计Boss节点数量，保证整局冒险拥有明确终点

	for node_index in range(nodes.size()):#第一阶段按照数组顺序验证全部节点及其唯一身份
		var node_definition:MapNodeDefinition = nodes[node_index];#取得当前位置的静态节点资源
		if node_definition == null:#节点数组中不能存在没有实际资源的空位置
			push_error("Invalid map node! 地图节点[%d]为空" % node_index);#报告空节点的准确下标
			return true;#空元素无法参与节点查询和连接验证
		if node_definition.is_invalid():#让节点定义检查自身类型、遭遇、治疗量和局部字段
			push_error("Invalid map node! 地图节点[%d]无效" % node_index);#补充节点在地图数组中的位置
			return true;#任意节点非法时整张地图都不能使用
		if configured_node_ids.has(node_definition.node_id):#节点ID必须能唯一定位一项节点资源
			push_error("Invalid node_id! 地图中重复配置节点ID：%s" % node_definition.node_id);#报告发生冲突的稳定ID
			return true;#重复ID会让查询和进度记录产生歧义

		configured_node_ids[node_definition.node_id] = true;#保存合法且首次出现的节点ID
		if node_definition.node_type == MapNodeDefinition.NodeType.BOSS:#Boss节点代表当前阶段的整局终点
			boss_node_count += 1;#允许未来存在多个Boss，但至少必须存在一个

	if boss_node_count == 0:#没有Boss时无法满足本阶段的胜利结算流程
		push_error("Invalid nodes! 地图中没有Boss节点");#报告缺少明确终点的地图结构
		return true;#无Boss地图不能作为第三阶段的完整冒险地图
	if starting_node_ids.is_empty():#新冒险必须至少拥有一个可以进入的起点
		push_error("Invalid starting_node_ids! 地图起点数组为空");#报告无法开始地图流程
		return true;#没有起点时所有节点都会保持不可进入

	var configured_starting_node_ids:Dictionary = {};#记录起点ID，阻止同一个节点被重复配置为起点
	for starting_index in range(starting_node_ids.size()):#逐一验证全部静态起点引用
		var starting_node_id:String = starting_node_ids[starting_index];#取得当前位置的起点ID
		if starting_node_id.is_empty():#空字符串无法指向实际地图节点
			push_error("Invalid starting_node_id! 地图起点ID[%d]为空" % starting_index);#报告空起点的准确位置
			return true;#非法起点不能用于可达性遍历
		if configured_starting_node_ids.has(starting_node_id):#同一个起点只需要配置一次
			push_error("Invalid starting_node_id! 地图重复配置起点ID：%s" % starting_node_id);#报告重复起点
			return true;#重复起点属于难以维护的冗余静态配置
		if not configured_node_ids.has(starting_node_id):#起点必须指向当前nodes中真实存在的节点
			push_error("Invalid starting_node_id! 地图起点不存在：%s" % starting_node_id);#报告悬空起点引用
			return true;#不存在的起点无法开始图遍历或冒险流程

		configured_starting_node_ids[starting_node_id] = true;#记录已经完整验证的起点ID

	for node_definition in nodes:#第二阶段验证每个节点声明的全部连接关系
		for next_node_id in node_definition.next_node_ids:#按照静态配置顺序检查后继节点ID
			if next_node_id == node_definition.node_id:#节点不能把自己声明为自己的直接后继
				push_error("Invalid connection! 节点不能连接到自身：%s" % node_definition.node_id);#报告自连接节点
				return true;#自连接无法表达有效的地图推进关系
			if not configured_node_ids.has(next_node_id):#每条连接都必须指向当前地图中的真实节点
				push_error("Invalid connection! 节点%s连接到不存在的节点：%s" % [
					node_definition.node_id,
					next_node_id
				]);#同时报告连接来源与缺失目标，方便定位资源
				return true;#悬空连接不能交给RunState解锁

	if not _all_nodes_are_reachable():#结构合法后，再确认不存在永远无法进入的孤立节点
		push_error("Invalid map graph! 地图中存在无法从起点到达的节点");#报告整图可达性错误
		return true;#包含孤立内容的地图不能通过最终验证

	return false;#地图身份、节点、起点、连接和可达性均合法


## 判断当前地图中的所有节点能否从至少一个起点到达。
##
## 使用starting_node_ids作为遍历入口，沿每个节点的next_node_ids向后访问，
## 最后比较已访问节点数量与nodes数量。全部节点可达时返回true，否则返回false。
##
## 调用前应先完成节点唯一性、起点存在性和连接目标存在性检查；该方法只进行
## 只读图遍历，不推送错误、不修改地图资源，也不保存任何运行时进度。
func _all_nodes_are_reachable()->bool:
	var pending_node_ids:Array[String] = starting_node_ids.duplicate();#复制起点数组作为局部待访问队列，避免修改静态资源
	var visited_node_ids:Dictionary = {};#使用节点ID记录已经访问的节点，防止环形连接导致无限遍历
	var pending_index:int = 0;#用下标读取队列，避免反复从数组开头移除元素

	while pending_index < pending_node_ids.size():#队列中仍有尚未处理的节点ID时继续遍历
		var current_node_id:String = pending_node_ids[pending_index];#读取当前需要访问的节点ID
		pending_index += 1;#下次循环处理队列中的下一项

		if visited_node_ids.has(current_node_id):#多个连接可能把同一个节点加入队列
			continue;#已经展开过该节点时无需重复处理其后继

		var current_node:MapNodeDefinition = get_node_by_id(current_node_id);#通过地图的统一查询入口取得节点资源
		if current_node == null:#前置验证正常时不应发生，保留防御性检查避免访问空对象
			return false;#无法取得待访问节点时整图不能判定为完全可达

		visited_node_ids[current_node_id] = true;#标记当前节点已经成功访问
		for next_node_id in current_node.next_node_ids:#沿当前节点的静态连接继续向后遍历
			if not visited_node_ids.has(next_node_id):#已访问节点无需再次加入待访问队列
				pending_node_ids.append(next_node_id);#保存尚未展开的后继ID，供后续循环处理

	return visited_node_ids.size() == nodes.size();#访问数量与节点总数一致时说明不存在孤立节点
