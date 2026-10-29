class_name CityNameDialog
extends Control

## Pergunta o nome da nova cidade quando o jogador funda uma.
## Já vem preenchido com uma sugestão da lista City.NAMES.
## Enter ou "Fundar" confirmam; Esc ou "Cancelar" desistem (o colono continua).

## Nome escolhido, ou "" se o jogador cancelou.
signal confirmed(city_name: String)

const MAX_LENGTH := 24

var _suggested := ""
var _name_edit: LineEdit


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


func open(suggested_name: String) -> void:
	_suggested = suggested_name
	_name_edit.text = suggested_name
	_name_edit.placeholder_text = suggested_name
	show()
	_name_edit.grab_focus()
	_name_edit.select_all()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish("")


func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CityWindow.make_panel_style())
	panel.theme = StoneStyle.theme()
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Nova cidade"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", CityWindow.SECTION_COLOR)
	box.add_child(title)

	var question := Label.new()
	question.text = "Qual será o nome da cidade?"
	box.add_child(question)

	_name_edit = LineEdit.new()
	_name_edit.max_length = MAX_LENGTH
	_name_edit.custom_minimum_size.x = 340
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _confirm())
	box.add_child(_name_edit)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "Cancelar [Esc]"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_finish.bind(""))
	CityWindow.style_button(cancel)
	buttons.add_child(cancel)
	var ok := Button.new()
	ok.text = "Fundar cidade [Enter]"
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(_confirm)
	CityWindow.style_button(ok)
	buttons.add_child(ok)


## Nome vazio (só espaços) usa a sugestão.
func _confirm() -> void:
	var city_name := _name_edit.text.strip_edges()
	_finish(city_name if not city_name.is_empty() else _suggested)


func _finish(city_name: String) -> void:
	_name_edit.release_focus()
	hide()
	confirmed.emit(city_name)
