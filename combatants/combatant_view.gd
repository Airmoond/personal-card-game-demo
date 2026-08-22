## 负责显示一名战斗角色的界面。
##
## 该脚本将CombatantState中的名称、生命和格挡等运行时数据同步到UI节点，
## 不负责修改角色状态、处理战斗规则或判断角色是否存活。
extends Control
class_name CombatantView

## 当前界面正在显示的角色运行时状态。
##
## 通过bind_combatant_state方法完成绑定；界面只读取该对象中的数据，
## 不应将UI节点中的显示值反向作为真实战斗数据。
var combatant_state:CombatantState;

## 用于显示角色原画的纹理节点。
@onready var artwork:TextureRect = $main_layout/artwork;

## 用于显示角色名称的文本节点。
@onready var name_label:Label = $main_layout/name_label;

## 用于直观显示角色当前生命与最大生命的进度条。
@onready var health_bar:ProgressBar = $main_layout/health_bar;

## 用于以文字形式显示角色当前生命与最大生命。
@onready var health_label:Label = $main_layout/health_label;

## 用于显示角色当前格挡值。
@onready var block_label:Label = $main_layout/block_label;

## 用于显示敌人下一步行动意图。
@onready var intent_label:Label = $main_layout/enemy_intent_label;


## 让当前界面开始显示传入的角色状态。
##
## new_combatant_state为空时推送错误，不修改原有绑定，并返回false。
## 传入有效对象时保存其引用、立即刷新界面，并返回true。
## 死亡角色也允许绑定，以便界面正常显示0生命。
## 应在当前节点进入场景树、@onready节点引用准备完成后调用。
func bind_combatant_state(new_combatant_state:CombatantState)->bool:
	if new_combatant_state == null:
		push_error("需要绑定的角色状态为空，角色界面绑定失败");
		return false;
	combatant_state = new_combatant_state;
	refresh_combatant_view();
	return true;


## 根据当前绑定的CombatantState刷新角色名称、生命和格挡显示。
##
## 尚未绑定角色状态时推送错误并立即结束。
## CombatantState目前没有原画和行动意图数据，因此这里不会修改对应节点。
func refresh_combatant_view()->void:
	if combatant_state == null:
		push_error("尚未绑定角色状态，角色界面刷新失败");
		return;
	name_label.text = combatant_state.combatant_name;
	health_bar.max_value = combatant_state.max_health;
	health_bar.value = combatant_state.current_health;
	health_label.text = "%d / %d" % [combatant_state.current_health, combatant_state.max_health];
	block_label.text = "格挡：%d" % combatant_state.current_block;
	block_label.visible = combatant_state.current_block > 0;


## 设置当前界面显示的敌人行动意图文字。
##
## intent_text为空时清空并隐藏意图标签；不为空时更新文字并显示标签。
## 该方法只负责更新界面，不会执行意图所描述的攻击、格挡或其他行动。
## 应在当前节点进入场景树、@onready节点引用准备完成后调用。
func set_intent(intent_text:String)->void:
	if intent_text.is_empty():#传入空文本时不应继续显示旧的敌人意图
		intent_label.text = "";#清除标签中原有的意图文字
		intent_label.hide();#隐藏当前没有内容的意图标签
		return;#空文本的处理已经完成，提前结束方法
	intent_label.text = intent_text;#使用传入文本更新敌人意图
	intent_label.show();#确保带有内容的意图标签显示出来


## 节点进入场景树并且@onready节点引用准备完成后，设置界面的初始显示状态。
##
## 初始状态下隐藏格挡和敌人意图标签。
## 该方法不会创建CombatantState，也不会擅自绑定玩家或敌人。
func _ready()->void:
	block_label.hide();#尚未绑定角色状态时，不显示默认格挡文字
	intent_label.hide();#尚未设置敌人意图时，不显示默认意图文字
