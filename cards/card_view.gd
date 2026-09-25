## 负责显示一张战斗卡牌的界面，并报告玩家对该卡牌的点击。
##
## 该脚本读取CardInstance及其CardDefinition中的数据刷新UI，
## 不负责消耗能量、执行卡牌效果或移动任何牌堆。
extends Control
class_name CardView

## 卡牌可以使用时采用的正常显示颜色。
##
## Color.WHITE不会改变场景原本的颜色与透明度。
const PLAYABLE_MODULATE:Color = Color.WHITE;

## 卡牌当前不可使用时采用的灰暗半透明显示颜色。
##
## 该颜色只提供视觉反馈，不代表CardView拥有或执行出牌合法性规则。
const UNPLAYABLE_MODULATE:Color = Color(0.55,0.55,0.55,0.65);

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

## 与开局、奖励页共用卡面，外层只负责实例与出牌输入。
@onready var card_face:CardFace = $card_face;


func _ready()->void:
	custom_minimum_size = card_face.get_combined_minimum_size();

## 绑定已经初始化的卡牌实例；进入场景树后调用。
func bind_card_instance(new_card_instance:CardInstance)->void:
	card_instance = new_card_instance;
	refresh_card_view();


## 从已绑定的实例刷新费用与卡面，不重新校验静态资源。
func refresh_card_view()->void:
	card_face.show_card(card_instance.definition, card_instance.current_energy_cost);
	tooltip_text = card_face.tooltip_text;


## 显示控制器提供的当前预览文案；视图不读取双方战斗状态或计算伤害。
func set_description(text:String)->void:
	card_face.set_description(text);
	# 子标签穿透鼠标，悬停说明由接收输入的卡牌根节点显示。
	tooltip_text = card_face.tooltip_text;


## 根据控制器提供的合法性结果切换卡牌可用或不可用的显示外观。
##
## is_playable为true时恢复正常颜色；为false时显示为灰暗半透明状态。
## 该方法只修改当前CardView的modulate，不读取能量或回合，不修改CardInstance，
## 也不阻止点击和发出card_selected信号；最终出牌合法性仍由BattleController判断。
func set_playable_visual(is_playable:bool)->void:
	if is_playable:#控制器已经确认当前卡牌在此刻可以尝试使用
		modulate = PLAYABLE_MODULATE;#恢复场景原有颜色与完全不透明的外观
		return;#正常外观已经设置完成，无需继续处理不可用分支
	modulate = UNPLAYABLE_MODULATE;#用灰暗半透明外观提示当前卡牌不可使用
	
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
