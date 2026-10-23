class_name TechDialog
extends Control

## Janela de tecnologia descoberta: aparece quando uma pesquisa termina, com o
## nome, a ilustração (Technology.image) e a descrição. "Continuar" (Enter ou
## Esc) fecha; em seguida o jogo pede a próxima pesquisa (ResearchDialog).

signal closed

## Tamanho da ilustração na janela; a imagem é recortada para preencher.
const IMAGE_SIZE := Vector2(560, 315)

var _title: Label
var _image: TextureRect
var _text: Label


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


func open(tech: int) -> void:
	_title.text = "Nova tecnologia: %s" % Technology.tech_name(tech)
	_image.texture = Technology.image(tech)
	_image.visible = _image.texture != null
	_text.text = Technology.DATA[tech]["description"]
	show()


func _input(event: InputEvent) -> void:
	if (visible and event is InputEventKey and event.pressed and not event.echo
			and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]):
		get_viewport().set_input_as_handled()
		_finish()


func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CityWindow.make_panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(header)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.draw.connect(func() -> void: Icons.draw_science(icon, Rect2(Vector2.ZERO, icon.size)))
	header.add_child(icon)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", CityWindow.SECTION_COLOR)
	header.add_child(_title)
	# Moldura escura em volta da ilustração
	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color.BLACK
	frame_style.set_content_margin_all(3)
	frame_style.set_border_width_all(1)
	frame_style.border_color = Color(1, 0.85, 0.2, 0.6)
	frame.add_theme_stylebox_override("panel", frame_style)
	box.add_child(frame)
	_image = TextureRect.new()
	_image.custom_minimum_size = IMAGE_SIZE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.clip_contents = true
	frame.add_child(_image)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = IMAGE_SIZE.x
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", 18)
	box.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var button := Button.new()
	button.text = "Continuar [Enter]"
	button.custom_minimum_size.x = 180
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_finish)
	CityWindow.style_button(button)
	buttons.add_child(button)


func _finish() -> void:
	hide()
	closed.emit()
