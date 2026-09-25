## 地图页面中显示一项固定地图节点的可复用界面组件。
##
## MapView以后为每个MapNodeDefinition创建一个MapNodeView，并根据RunState计算出的
## 进度传入锁定、可进入或已完成状态。该组件负责显示节点名称与状态、接收按钮
## 输入，并通过pressed信号报告玩家选择的稳定节点ID。
##
## MapNodeView属于视图与输入层，不保存RunState，不进入节点，不启动战斗或治疗，
## 也不修改MapNodeDefinition等静态资源；全部流程决定由外部控制器负责。
class_name MapNodeView
extends Control


## 地图节点可以呈现的三种运行时界面状态。
##
## 该枚举只描述地图进度外观，不能与MapNodeDefinition.NodeType中的
## BATTLE、REST和BOSS内容类型混用。
enum NodeState {
	## 节点尚未解锁，显示为灰暗状态且不可点击。
	LOCKED,

	## 节点已经解锁，可以响应玩家选择。
	AVAILABLE,

	## 节点已经完成，显示完成反馈且不能再次点击。
	COMPLETED
}


## 锁定节点使用的灰暗半透明颜色。
const LOCKED_MODULATE:Color = Color(0.45,0.45,0.45,0.75)


## 可进入节点使用的明亮淡金色，用于提示玩家当前可选路线。
const AVAILABLE_MODULATE:Color = Color(1.0,0.9,0.55,1.0)


## 已完成节点使用的淡绿色，用于和锁定状态明确区分。
const COMPLETED_MODULATE:Color = Color(0.55,0.85,0.6,0.9)


## 玩家首次点击当前已经绑定且允许交互的节点时发出。
##
## node_id是MapNodeDefinition中的稳定节点ID。该信号只报告玩家选择，不代表
## 节点已经进入或完成；MapView与GameFlowController仍需执行最终合法性检查。
signal pressed(node_id:String)


## 当前界面正在显示的静态地图节点定义。
##
## 通过setup完成绑定。该资源只能读取，不能把锁定、完成等运行时进度写回其中。
var node_definition:MapNodeDefinition


## 当前界面使用的地图进度显示状态。
##
## 由MapView根据RunState计算后传入，只决定文字与颜色，不单独决定真实节点进度。
var current_state:NodeState = NodeState.LOCKED


## 当前这次setup之后是否已经报告过玩家点击。
##
## 用于防止页面切换完成前的快速连续点击重复创建战斗或重复结算休整节点。
var _press_reported:bool = false


## 显示节点名称、状态并接收点击输入的内部按钮。
##
## 节点路径要求map_node_view.tscn的根节点下直接存在名为node_button的Button。
@onready var node_button:Button = $node_button


## 组件节点准备完成后连接内部按钮，并保持初始不可交互状态。
##
## setup完成绑定后，MapView还需要调用set_interactable并传入RunState的最终判断。
func _ready()->void:
	node_button.pressed.connect(_on_node_button_pressed);#把按钮输入统一转交给当前View的私有处理方法
	node_button.disabled = true;#尚未绑定节点和运行时进度前不能报告任何地图选择


## 接收已验证的节点定义，以及地图页面计算出的显示状态。
func setup(new_node_definition:MapNodeDefinition,new_state:NodeState)->void:
	node_definition = new_node_definition;
	current_state = new_state;
	_press_reported = false;
	_refresh_visual();
	set_interactable(false);


## 根据外部流程计算结果设置当前节点是否允许玩家点击。
##
## 只有enabled为true、组件已经绑定节点、当前外观为AVAILABLE且尚未报告过点击时，
## 按钮才会启用；其他情况统一禁用。该方法只改变按钮交互，不修改任何地图进度。
func set_interactable(enabled:bool)->void:
	var can_interact:bool = (
		enabled
		and node_definition != null
		and current_state == NodeState.AVAILABLE
		and not _press_reported
	);#外部合法性结果和当前View准备状态必须同时成立
	node_button.disabled = not can_interact;#Button使用disabled表达是否拒绝玩家点击


## 根据当前绑定节点和NodeState刷新按钮文字与颜色。
##
## 文字始终读取MapNodeDefinition.display_name，状态说明与颜色由当前界面枚举决定。
## 该方法只更新表现，不检查RunState，也不改变按钮最终是否可以交互。
func _refresh_visual()->void:
	match current_state:#把外部计算的进度状态翻译为玩家可理解的文字与颜色
		NodeState.LOCKED:
			node_button.text = "%s\n[锁定]" % node_definition.display_name;#显示静态名称与锁定反馈
			node_button.modulate = LOCKED_MODULATE;#灰暗外观提示该节点当前无法进入
		NodeState.AVAILABLE:
			node_button.text = "%s\n[可进入]" % node_definition.display_name;#提示玩家当前可以选择该节点
			node_button.modulate = AVAILABLE_MODULATE;#使用明亮颜色强调可选路线
		NodeState.COMPLETED:
			node_button.text = "%s\n[已完成]" % node_definition.display_name;#保留节点名称并显示完成结果
			node_button.modulate = COMPLETED_MODULATE;#使用淡绿色区分已经完成与尚未解锁
		_:
			push_error("当前地图节点显示状态无效，无法刷新节点界面");#防御性处理绕过setup的非法状态修改


## 接收内部按钮点击，并且只报告一次有效地图节点选择。
##
## 尚未绑定节点、按钮不可交互或本次setup已经报告过点击时忽略输入；首次有效
## 点击会先保存防重复状态、禁用按钮，再发出包含稳定节点ID的pressed信号。
func _on_node_button_pressed()->void:
	if node_definition == null:#没有静态节点时不能生成可信的node_id参数
		push_error("尚未绑定地图节点定义，无法报告节点点击");#报告组件未完成setup
		return;#空绑定不能发出地图选择信号
	if node_button.disabled:#外部流程已经判定当前节点不能交互
		return;#锁定、完成或尚未开放的节点不报告玩家选择
	if _press_reported:#页面替换完成前可能收到快速连续输入
		return;#同一次设置周期中只允许报告一个节点选择

	_press_reported = true;#先提交本地防重复状态，阻止同一调用链中的再次进入
	node_button.disabled = true;#立即锁定当前按钮，等待外部流程处理选择结果
	pressed.emit(node_definition.node_id);#只报告稳定ID，不直接进入节点或修改RunState
