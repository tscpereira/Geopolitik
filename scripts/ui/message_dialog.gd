class_name MessageDialog
extends Control

## Pergunta ou aviso no meio da tela, no mármore das janelas (desde
## 30/10/2026: primeiro encontro, declaração de guerra, guerra surpresa,
## propostas de paz). Um botão por opção; Enter escolhe a primeira e Esc a
## última. Use Hud.ask, que espera a escolha.

## Botão escolhido (índice em [param buttons] de open).
signal chosen(index: int)

var _title: Label
var _text: RichTextLabel
var _buttons: HBoxContainer
var _count := 0


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CityWindow.make_panel_style())
	panel.theme = StoneStyle.theme()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", CityWindow.SECTION_COLOR)
	box.add_child(_title)
	box.add_child(StoneStyle.separator())
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size.x = 480
	_text.add_theme_font_size_override("normal_font_size", 18)
	_text.add_theme_font_size_override("bold_font_size", 18)
	box.add_child(_text)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 10)
	box.add_child(_buttons)


## Mostra a mensagem. [param text] aceita BBCode.
func open(title: String, text: String, buttons: Array = ["OK"]) -> void:
	_title.text = title
	_text.text = text
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	_count = buttons.size()
	for i in buttons.size():
		var button := Button.new()
		button.text = buttons[i]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_finish.bind(i))
		CityWindow.style_button(button)
		_buttons.add_child(button)
	show()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_finish(0)
	elif event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish(_count - 1)


func _finish(index: int) -> void:
	hide()
	chosen.emit(index)
