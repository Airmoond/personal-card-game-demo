## 负责显示一张战斗卡牌的界面，并报告玩家对该卡牌的点击。
##
## 该脚本读取CardInstance及其CardDefinition中的数据刷新UI，
## 不负责消耗能量、执行卡牌效果或移动任何牌堆。
extends Control
class_name CardView

## 玩家左键点击一张已经成功绑定的卡牌时发出。
##
## selected_card是被点击界面当前绑定的CardInstance。
## 该信号只报告玩家选择，不代表卡牌一定可以使用。
signal card_selected(selected_card:CardInstance);

## 当前界面正在显示的卡牌运行时实例。
##
## 通过bind_card_instance方法完成绑定；界面只读取该实例及其定义，
## 不应直接修改费用、卡牌效果或所在牌堆。
var card_instance:CardInstance;

## 用于显示卡牌当前费用。
@onready var cost_label:Label = $cost_label;

## 用于显示卡牌名称。
@onready var name_label:Label = $name_label;

## 用于显示卡牌原画。
@onready var artwork:TextureRect = $artwork;

## 用于显示卡牌效果说明。
@onready var description_label:RichTextLabel = $description_label;

## 让当前界面开始显示传入的卡牌实例。
##
## new_card_instance为空或实例无效时推送错误，不修改原有绑定，并返回false。
## 传入有效实例时保存其引用、立即刷新界面，并返回true。
## 应在当前节点进入场景树、@onready节点引用准备完成后调用。
func bind_card_instance(new_card_instance:CardInstance)->bool:
	if new_card_instance == null:
		push_error("需要绑定的卡牌实例为空，卡牌界面绑定失败");
		return false;
	if new_card_instance.is_invalid_instance():
		push_error("需要绑定的卡牌实例无效，卡牌界面绑定失败");
		return false;
	card_instance = new_card_instance;
	refresh_card_view();
	return true;
	
## 根据当前绑定的CardInstance刷新费用、名称、原画和描述。
##
## 尚未绑定卡牌实例或当前实例无效时推送错误并立即结束。
## 该方法只刷新界面，不修改CardInstance或CardDefinition。
func refresh_card_view()->void:
	if card_instance == null:
		push_error("尚未绑定卡牌实例，卡牌界面刷新失败");
		return;
	if card_instance.is_invalid_instance():
		push_error("当前绑定的卡牌实例无效，卡牌界面刷新失败");
		return;
	
	cost_label.text = str(card_instance.current_energy_cost);
	name_label.text = card_instance.definition.card_name;
	artwork.texture = card_instance.definition.artwork;
	description_label.text = card_instance.definition.description;
	
## 接收发生在当前卡牌界面范围内的鼠标输入。
##
## 仅在鼠标左键按下且已经绑定卡牌实例时发出card_selected信号。
## 其他鼠标按键、鼠标释放和非鼠标输入均被忽略。
func _gui_input(event:InputEvent)->void:
	var mouse_event:InputEventMouseButton = event as InputEventMouseButton;#尝试将输入转换为鼠标按键事件
	if mouse_event == null:#不是鼠标按键事件时不处理
		return;
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:#不是鼠标左键时不处理
		return;
	if not mouse_event.pressed:#只在按下时触发，释放时不重复触发
		return;
	if card_instance == null:#未绑定卡牌时不能报告选择
		push_error("当前卡牌界面尚未绑定卡牌实例，无法报告点击");
		return;
	card_selected.emit(card_instance);#只报告被选择的实例，不执行卡牌效果
