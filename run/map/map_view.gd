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


## 绑定已初始化的冒险与地图，确认二者属于同一局后显示。
func setup(new_map_definition:MapDefinition,new_run_state:RunState)->bool:
	if new_map_definition == null or new_run_state == null:
		push_error("地图页面缺少地图定义或局内状态");
		return false;
	if new_run_state.definition.map_definition != new_map_definition:
		push_error("局内状态与需要显示的地图不一致");
		return false;
	map_definition = new_map_definition;
	run_state = new_run_state;
	refresh_map();
	return true;


## 从已绑定的状态重建地图；静态地图在冒险初始化时验证。
func refresh_map()->void:
	_clear_dynamic_content();
	_selection_reported = false;
	_refresh_run_info();
	_create_node_views();
	_create_connection_lines();


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
	health_label.text = "生命：%d / %d" % [
		run_state.current_health,
		run_state.max_health
	];#当前生命与最大生命都来自本局运行时状态。
	deck_label.text = "牌组：%d张" % run_state.owned_cards.size();#每个CardDefinition元素代表实际拥有的一张卡


## 为每个配置节点建立对应界面。
func _create_node_views()->void:
	for node_definition in map_definition.nodes:
		var view:MapNodeView = MAP_NODE_VIEW_SCENE.instantiate();
		node_layer.add_child(view);
		view.position = node_definition.map_position;
		view.setup(node_definition, _get_node_visual_state(node_definition.node_id));
		view.pressed.connect(_on_map_node_pressed);
		view.set_interactable(run_state.can_enter_node(node_definition.node_id));
		_node_views[node_definition.node_id] = view;


## 根据当前RunState取得一个节点应当显示的NodeState。
##
## 已完成节点优先返回COMPLETED，已解锁节点返回AVAILABLE，其余返回LOCKED。
## 该方法只计算外观；最终按钮权限仍由RunState.can_enter_node决定。
func _get_node_visual_state(node_id:String)->MapNodeView.NodeState:
	if run_state.completed_node_ids.has(node_id):#完成记录优先于其他显示状态
		return MapNodeView.NodeState.COMPLETED;#已完成节点需要保留可见但不能再次进入
	if run_state.available_node_ids.has(node_id):#解锁数组表示节点已经具备可进入外观
		return MapNodeView.NodeState.AVAILABLE;#是否真正可点仍受到整局状态和当前节点限制
	return MapNodeView.NodeState.LOCKED;#未完成且未解锁的节点统一显示为锁定


## 节点界面创建完成后，按已经验证的地图连接绘制路线。
func _create_connection_lines()->void:
	for source in map_definition.nodes:
		var source_view:MapNodeView = _node_views[source.node_id];
		for target_node_id in source.next_node_ids:
			var target_view:MapNodeView = _node_views[target_node_id];
			var line:Line2D = Line2D.new();
			line.name = "connection_%s_to_%s" % [source.node_id, target_node_id];
			line.width = CONNECTION_WIDTH;
			line.default_color = CONNECTION_COLOR;
			line.add_point(_get_node_view_center(source_view));
			line.add_point(_get_node_view_center(target_view));
			connection_layer.add_child(line);


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
	for node_view:MapNodeView in _node_views.values():
		node_view.set_interactable(false);

	node_selected.emit(node_id);#只报告稳定ID，由流程控制器调用RunState.enter_node并切换流程
