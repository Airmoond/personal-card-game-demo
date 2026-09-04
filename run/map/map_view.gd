## 显示一张静态地图及其当前局内进度的完整页面。
##
## GameFlowController以后实例化MapView，并通过setup传入同一局冒险使用的
## MapDefinition与RunState。页面根据静态节点位置创建MapNodeView和连接线，
## 根据运行时进度显示锁定、可进入与已完成状态，并报告玩家选择的节点ID。
##
## MapView属于视图与输入层。它可以只读访问RunState以刷新生命、牌组和按钮状态，
## 但不能调用enter_node、complete_current_node、heal或其他推进游戏状态的方法。
class_name MapView
extends Control


## 每个地图节点使用的可复用界面场景模板。
##
## refresh_map会为MapDefinition.nodes中的每个元素分别实例化一个独立组件。
const MAP_NODE_VIEW_SCENE:PackedScene = preload(
	"res://run/map/map_node_view.tscn"
)


## 地图节点连接线使用的基础宽度。
const CONNECTION_WIDTH:float = 4.0


## 地图节点连接线使用的灰白色。
const CONNECTION_COLOR:Color = Color(0.78,0.8,0.86,0.9)


## 玩家首次选择一个当前真正可进入的节点时发出。
##
## node_id是MapNodeDefinition中的稳定节点ID。信号只报告玩家意图，
## GameFlowController收到后仍需调用RunState.enter_node执行最终状态提交。
signal node_selected(node_id:String)


## 当前页面正在显示的静态地图定义。
##
## 通过setup完成绑定，只用于读取节点、位置和连接；运行时不得修改该Resource。
var map_definition:MapDefinition


## 当前页面正在显示的局内运行时状态。
##
## MapView只读取生命、牌组和地图进度，不通过该引用直接推进或结算冒险。
var run_state:RunState


## 按稳定node_id保存当前页面创建的MapNodeView实例。
##
## 字典只用于连接线查找和统一禁用按钮，不属于真实地图进度；刷新页面时会重建。
var _node_views:Dictionary = {}


## 当前这次地图刷新之后是否已经报告过一项节点选择。
##
## 用于阻止快速点击不同节点时重复触发页面切换或创建多个战斗页面。
var _selection_reported:bool = false


## 动态连接线的父节点。
##
## 场景中应当位于node_layer之前，使Line2D显示在地图节点组件下方。
@onready var connection_layer:Control = $connection_layer


## 动态MapNodeView实例的父节点。
##
## 该节点必须是普通Control而不是Container，否则静态map_position可能被自动排版覆盖。
@onready var node_layer:Control = $node_layer


## 显示玩家当前局内生命与最大生命的顶部标签。
@onready var health_label:Label = $top_bar/health_label


## 显示玩家当前实际拥有卡牌数量的顶部标签。
@onready var deck_label:Label = $top_bar/deck_label


## 使用一份静态地图及其对应的局内状态设置当前地图页面。
##
## 地图或RunState为空、任意一方非法，或者RunState引用的地图与传入地图不是
## 同一份资源时，推送对应错误并返回false。输入合法时保存只读引用、重置选择状态，
## 再调用refresh_map创建完整页面；刷新失败时清理绑定并返回false。
##
## 该方法应在页面进入场景树、@onready节点引用准备完成后调用。
func setup(new_map_definition:MapDefinition,new_run_state:RunState)->bool:
	if new_map_definition == null:#没有静态地图就无法确定节点、位置和连接
		push_error("需要显示的地图定义为空");#报告流程控制器没有传入实际地图资源
		return false;#验证失败前保持当前页面原有绑定不变
	if new_map_definition.is_invalid():#地图ID、节点、起点、连接和可达性必须完整合法
		push_error("需要显示的地图定义无效");#补充地图View层的错误上下文
		return false;#非法地图不能成为界面生成的数据来源
	if new_run_state == null:#没有局内状态就无法确定生命、牌组和节点进度
		push_error("需要显示的局内状态为空");#报告流程控制器缺少本局唯一状态对象
		return false;#空状态不能用于计算任何节点外观或交互
	if new_run_state.is_invalid():#只允许完整合法的局内状态进入地图显示流程
		push_error("需要显示的局内状态无效");#补充地图页面设置阶段的错误上下文
		return false;#损坏状态不能生成可能误导玩家的地图界面
	if new_run_state.definition.map_definition != new_map_definition:#显示与进度必须引用同一份静态地图
		push_error("局内状态使用的地图与需要显示的地图不一致");#报告两个地图真相源发生冲突
		return false;#拒绝把一张地图的进度显示到另一张地图上

	map_definition = new_map_definition;#保存静态地图的只读引用，供节点和连接生成使用
	run_state = new_run_state;#保存局内状态引用，但只通过查询读取其当前数据
	_selection_reported = false;#新的页面设置周期尚未报告过任何节点选择

	if not refresh_map():#根据已经验证的数据生成顶部信息、节点和连接线
		_clear_dynamic_content();#刷新失败时移除可能创建出的部分界面节点
		map_definition = null;#清除未能成功显示的静态地图绑定
		run_state = null;#清除未能成功显示的局内状态绑定
		push_error("地图页面刷新失败，设置没有完成");#报告界面生成阶段失败
		return false;#不把半成品地图页面交给流程控制器使用

	return true;#静态地图与局内进度已经完整显示


## 根据当前绑定的MapDefinition和RunState完整重建地图页面。
##
## 方法先验证绑定，清理旧节点与连接，更新生命和牌组信息，再创建全部MapNodeView
## 及Line2D连接。任意动态实例创建或设置失败时清理半成品并返回false；成功时返回true。
##
## 该方法只重建显示节点，不修改RunState或任何静态Resource。整页重建会丢弃旧组件
## 的悬停等临时外观，但能简单可靠地保证画面与当前运行时进度一致。
func refresh_map()->bool:
	if map_definition == null:#缺少静态地图时无法重新创建节点和连接
		push_error("尚未绑定地图定义，无法刷新地图页面");#报告setup尚未成功完成
		return false;#保持现有页面内容不变
	if run_state == null:#缺少局内状态时无法计算进度和顶部信息
		push_error("尚未绑定局内状态，无法刷新地图页面");#报告页面缺少唯一运行时数据源
		return false;#没有数据时不能生成可信界面
	if map_definition.is_invalid() or run_state.is_invalid():#刷新前再次防御性验证两个数据来源
		push_error("地图定义或局内状态无效，无法刷新地图页面");#报告绑定数据在刷新前已经损坏
		return false;#非法数据不能覆盖当前界面
	if run_state.definition.map_definition != map_definition:#防止绑定后出现地图引用不一致
		push_error("局内状态与当前地图定义不一致，无法刷新地图页面");#报告显示来源发生冲突
		return false;#不允许把错误进度继续显示到当前页面

	_clear_dynamic_content();#验证通过后再清理旧动态内容，避免失败时无故清空页面
	_selection_reported = false;#完整刷新代表开始一个新的地图交互周期
	_refresh_run_info();#顶部信息始终从当前RunState重新读取

	if not _create_node_views():#先创建全部节点组件，供随后连接线查询中心位置
		_clear_dynamic_content();#实例化或设置失败时移除已经产生的部分节点
		return false;#半成品节点集合不能继续创建连接或接收输入
	if not _create_connection_lines():#节点全部存在后再根据静态next_node_ids生成连线
		_clear_dynamic_content();#连接失败时清理节点与已创建的部分线段
		return false;#不显示结构不完整的地图

	return true;#顶部信息、节点外观、交互状态和连接线均已完整建立


## 清理当前页面中此前动态创建的全部连接线和地图节点组件。
##
## 只移除connection_layer与node_layer的运行时子节点，不删除背景、顶部信息或静态资源。
func _clear_dynamic_content()->void:
	for connection in connection_layer.get_children():#逐一处理上一次刷新创建的Line2D
		connection_layer.remove_child(connection);#立即移出场景树，避免旧连线继续显示
		connection.queue_free();#在当前帧安全结束后释放旧连接节点

	for node_view in node_layer.get_children():#逐一处理上一次刷新创建的MapNodeView
		node_layer.remove_child(node_view);#立即移出场景树和输入系统
		node_view.queue_free();#在当前帧安全结束后释放旧地图节点组件

	_node_views.clear();#删除仅用于当前界面的node_id到View映射


## 从RunState刷新顶部生命与实际牌组数量文字。
##
## 该方法只读取数据并更新Label，不把标签中的文字反向作为游戏状态。
func _refresh_run_info()->void:
	var max_health:int = run_state.definition.player_definition.max_health;#最大生命读取只读玩家定义
	health_label.text = "生命：%d / %d" % [
		run_state.current_health,
		max_health
	];#组合运行时当前生命与静态最大生命
	deck_label.text = "牌组：%d张" % run_state.owned_cards.size();#每个CardDefinition元素代表实际拥有的一张卡


## 为静态地图中的每个节点创建、设置并保存一个MapNodeView。
##
## 全部组件先加入node_layer以完成@onready，再调用setup、设置静态坐标、连接点击信号，
## 并用RunState.can_enter_node设置最终交互权限。任意步骤失败时返回false。
func _create_node_views()->bool:
	for node_definition in map_definition.nodes:#按照静态资源数组顺序创建全部地图节点组件
		var new_node_view:MapNodeView = MAP_NODE_VIEW_SCENE.instantiate() as MapNodeView;#由统一场景模板创建独立View
		if new_node_view == null:#场景根节点没有挂载MapNodeView脚本时类型转换会失败
			push_error("MapNodeView场景实例化失败");#报告模板场景与脚本契约不一致
			return false;#缺少任何一个节点组件时整张地图都不完整

		node_layer.add_child(new_node_view);#必须先进入场景树，内部@onready node_button才会准备完成
		new_node_view.position = node_definition.map_position;#静态坐标表示组件左上角位置，不写回资源

		var visual_state:int = _get_node_visual_state(node_definition.node_id);#根据运行时进度计算显示状态
		if not new_node_view.setup(node_definition,visual_state):#绑定静态定义并刷新节点文字与颜色
			node_layer.remove_child(new_node_view);#设置失败时先从场景树移除当前半成品组件
			new_node_view.queue_free();#安全释放无法使用的节点View
			return false;#任意节点设置失败都会终止整页生成

		new_node_view.pressed.connect(_on_map_node_pressed);#节点点击先回到MapView进行页面级二次验证
		new_node_view.set_interactable(
			run_state.can_enter_node(node_definition.node_id)
		);#最终按钮权限只使用RunState的真实查询结果
		_node_views[node_definition.node_id] = new_node_view;#保存View映射供连接线和统一禁用使用

	return true;#全部静态节点都已经拥有对应的运行时界面组件


## 根据当前RunState取得一个节点应当显示的NodeState。
##
## 已完成节点优先返回COMPLETED，已解锁节点返回AVAILABLE，其余返回LOCKED。
## 该方法只计算外观；最终按钮权限仍由RunState.can_enter_node决定。
func _get_node_visual_state(node_id:String)->int:
	if run_state.completed_node_ids.has(node_id):#完成记录优先于其他显示状态
		return MapNodeView.NodeState.COMPLETED;#已完成节点需要保留可见但不能再次进入
	if run_state.available_node_ids.has(node_id):#解锁数组表示节点已经具备可进入外观
		return MapNodeView.NodeState.AVAILABLE;#是否真正可点仍受到整局状态和当前节点限制
	return MapNodeView.NodeState.LOCKED;#未完成且未解锁的节点统一显示为锁定


## 根据MapDefinition中的next_node_ids创建全部静态连接线。
##
## 每条连接使用两个MapNodeView的中心点作为端点，并加入connection_layer，
## 从而显示在node_layer中的按钮下方。找不到任一端点时推送错误并返回false。
func _create_connection_lines()->bool:
	for source_definition in map_definition.nodes:#每个静态节点都可能声明零个或多个后继连接
		var source_view:MapNodeView = _node_views.get(source_definition.node_id) as MapNodeView;#取得连接起点View
		if source_view == null:#节点创建成功时正常不会发生，保留防御性检查
			push_error("找不到连接起点的地图节点界面：%s" % source_definition.node_id);#报告缺失起点
			return false;#缺少端点时无法绘制可信连接

		for target_node_id in source_definition.next_node_ids:#按照静态配置顺序创建当前节点的全部出边
			var target_view:MapNodeView = _node_views.get(target_node_id) as MapNodeView;#取得连接终点View
			if target_view == null:#合法地图与完整节点集合正常不会触发
				push_error("找不到连接终点的地图节点界面：%s" % target_node_id);#报告缺失目标
				return false;#连接端点不完整时停止整页生成

			var connection_line:Line2D = Line2D.new();#每项静态连接使用一个独立Line2D显示
			connection_line.name = "connection_%s_to_%s" % [
				source_definition.node_id,
				target_node_id
			];#使用稳定ID生成便于调试的运行时节点名称
			connection_line.width = CONNECTION_WIDTH;#统一所有地图连接的线条粗细
			connection_line.default_color = CONNECTION_COLOR;#统一使用不抢夺节点视觉重点的灰白色
			connection_line.add_point(_get_node_view_center(source_view));#连接起点位于来源按钮中心
			connection_line.add_point(_get_node_view_center(target_view));#连接终点位于目标按钮中心
			connection_layer.add_child(connection_line);#连接层位于节点层下方，因此线条不会覆盖按钮

	return true;#全部静态连接都已经转换为可见Line2D


## 计算一个MapNodeView在MapView局部坐标中的中心位置。
##
## 优先使用场景配置的custom_minimum_size，未配置时再读取当前size。
## map_position表示节点左上角，因此中心点等于position加上显示尺寸的一半。
func _get_node_view_center(node_view:MapNodeView)->Vector2:
	var display_size:Vector2 = node_view.custom_minimum_size;#当前模板使用170×90的静态最小尺寸
	if display_size == Vector2.ZERO:#允许未来模板不设置自定义最小尺寸
		display_size = node_view.size;#退回读取Control进入场景树后的实际尺寸
	return node_view.position + display_size * 0.5;#将左上角静态坐标转换为连接线中心点


## 接收MapNodeView报告的玩家选择，并进行页面级最终验证。
##
## 已经报告过选择、尚未绑定状态或节点此刻不可进入时忽略或报告错误；首次合法
## 选择会禁用全部节点组件，再发出node_selected。该方法不调用RunState.enter_node。
func _on_map_node_pressed(node_id:String)->void:
	if _selection_reported:#页面切换完成前可能快速点击不同的可进入节点
		return;#同一次地图显示周期最多报告一个选择
	if run_state == null:#没有唯一局内状态时无法执行最终节点合法性检查
		push_error("尚未绑定局内状态，无法报告地图节点选择");#报告setup调用顺序错误
		return;#缺少真实进度时不能转发玩家输入
	if not run_state.can_enter_node(node_id):#View外观不能替代RunState的最终进入条件
		push_error("玩家选择了当前不可进入的地图节点：%s" % node_id);#报告显示与真实状态不一致
		return;#锁定、完成或不存在的节点不能进入流程层

	_selection_reported = true;#先提交页面级防重复状态，阻止不同按钮的连续输入
	for node_view_value in _node_views.values():#统一禁用当前页面创建的全部地图节点组件
		var node_view:MapNodeView = node_view_value as MapNodeView;#从Dictionary的Variant值恢复具体类型
		if node_view != null:#防御性忽略损坏映射中的非MapNodeView值
			node_view.set_interactable(false);#等待GameFlowController处理选择并替换当前页面

	node_selected.emit(node_id);#只报告稳定ID，由流程控制器调用RunState.enter_node并切换流程
