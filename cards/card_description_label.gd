## 按实际排版高度缩小字号，不截断文案；空间恢复后重新从场景字号尝试。
class_name CardDescriptionLabel
extends RichTextLabel

@onready var _base_font_size:int = get_theme_font_size("normal_font_size");


func _ready()->void:
	resized.connect(_fit_text);


func set_description(value:String)->void:
	text = value;
	_fit_text();


func _fit_text()->void:
	var font_size:int = _base_font_size;
	add_theme_font_size_override("normal_font_size", font_size);
	var available_height:float = size.y - get_theme_stylebox("normal").get_minimum_size().y;
	while font_size > 1 and get_content_height() > available_height:
		font_size -= 1;
		add_theme_font_size_override("normal_font_size", font_size);
