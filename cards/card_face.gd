## 共用卡面：只展示传入的数据，不持有战斗实例，也不处理点击。
class_name CardFace
extends Control

const TYPE_NAMES:Array[String] = ["攻击", "技能", "能力", "武器"];
const RARITY_COLORS:Array[Color] = [Color.WHITE, Color("3b82f6"), Color("a855f7"), Color("ffa500")];


@onready var cost_label:Label = $cost_label;
@onready var name_label:Label = $name_label;
@onready var artwork:TextureRect = $artwork;
@onready var description_label:CardDescriptionLabel = $description_label;


## 费用由外层选择基础值或当前值，其他固定信息共用同一份定义。
func show_card(definition:CardDefinition, energy_cost:int)->void:
	cost_label.text = str(energy_cost);
	name_label.text = definition.card_name;
	artwork.texture = definition.artwork;
	$cardtype_label.text = TYPE_NAMES[definition.card_type];
	$expansion_type_label.text = "标";
	for child in get_children():
		if child is Label or child is RichTextLabel:
			# 场景中的样式可能被多张卡共享，不能直接改原资源。
			var style:StyleBoxFlat = child.get_theme_stylebox("normal").duplicate();
			style.border_color = RARITY_COLORS[definition.rarity];
			child.add_theme_stylebox_override("normal", style);
	set_description(definition.format_description());


## 战斗外显示基础描述，战斗中可由控制器传入伤害预览。
func set_description(value:String)->void:
	description_label.set_description(value);
	tooltip_text = "标准扩展包\n" + value;
